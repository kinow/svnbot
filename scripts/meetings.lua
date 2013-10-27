-- meetings.lua - Record keeping for meetings.

-- Some vars and placeholders
meetings = meetings or {}
previousMeeting = previousMeeting or {}
meeting_points = { 'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z' }
local meeting_email_format = 
[[From: "ASF IRC Services" <asfbot@wilderness.apache.org>
To: "Summary Recipient" <%s>
Subject: Summary of IRC meeting in %s, %s
MIME-Version: 1.0
Content-Type: multipart/alternative; boundary="=_NextPart_DC7E1BB5_1105_4DB3_BAE3_2A6208EB099D"

--=_NextPart_DC7E1BB5_1105_4DB3_BAE3_2A6208EB099D
Content-Type: text/plain; charset=us-ascii

%s
--=_NextPart_DC7E1BB5_1105_4DB3_BAE3_2A6208EB099D
Content-Type: text/html; charset=us-ascii
Content-Transfer-Encoding: quoted-printable

%s

--=_NextPart_DC7E1BB5_1105_4DB3_BAE3_2A6208EB099D--
]]
sendmailPath = "/usr/sbin/sendmail -t -oi"

-- fired when a topic changes
function meeting_change_topic(who, ident, channel, topic)
    if topic and channel and who ~= cfg.irc.nick then
        if meetings[channel] then
            if not meetings[channel].topic then
                meetings[channel].topic = topic
                print("Set original topic to: " .. topic)
            else
                table.insert(meetings[channel].minutes, { topic = topic, log = {}, info = {} })
                print("Set new topic to: " .. topic)
            end
        end
    end
end

-- callback for fetching the current topic of a channel
function server_callback_topic(params)
    local sender, channel, topic = params:match("(%S+) (#%S+) :(.+)$")
    if topic and channel then
        if meetings[channel] then
            if not meetings[channel].topic then
                meetings[channel].topic = topic
                print("Set original topic to: " .. topic)
            else
                table.insert(meetings[channel].minutes, { topic = topic, log = {}, info = {} })
            end
        end
    end
end

-- logger function for all messages sent to a channel. Stuff beginning with [off] is ignored.
function meeting_channel_message(sender, channel, channelLine)
    if channel and channelLine:match("^#meetingstart") then
        meeting(s, sender, channel, "start")
    elseif channel and channelLine:match("^#meetingend") then
        meeting(s, sender, channel, "end")
    elseif meetings[channel] and not channelLine:match("^%[off%]") then
        channelLine = channelLine:gsub("(https?://[^%s,]+)", function(a) return ([[<a href="%s" target="_blank">%s</a>]]):format(a,a) end)
        local newtopic = channelLine:match("^#topic (.+)$")
        if newtopic then
            IRCSocket:send( ("TOPIC %s :%s\r\n"):format(channel, newtopic) )
            table.insert(meetings[channel].minutes, { topic = newtopic, log = {}, info = {} })
        else
            table.insert(meetings[channel].minutes[#meetings[channel].minutes].log, ("%s [%s]: %s"):format(os.date("!%H:%M:%S"), sender, channelLine))
        end
        meetings[channel].people[sender] = (meetings[channel].people[sender] or 0) + 1
    end
end

-- sending email to lists
function meeting_email(sender, channel, params)
    if meetings[channel] and previousMeeting[channel] and not params:match("previous$") then
        say(s, channel or sender, "A meeting is currently taking place, please end it before sending out the summary.")
        say(s, channel or sender, ("If you meant to send out the previous meeting, please type 'meeting %s previous'"):format(params))
    elseif previousMeeting[channel] then
        local m = previousMeeting[channel]
        local email = params:match("send ([^@ ]+@[^@ ]+)")
        if email then
            say(s, channel or sender, "Sending meeting summary to " .. email)
            local f = io.popen(sendmailPath, "w")
            if f then
                f:write(meeting_email_format:format(email, channel, m.date or os.date("!%c"), m.raw, m.html))
                f:close()
                say(channel or sender, "Meeting summary sent!")
                local filename = channel:gsub("[^a-zA-Z%-]", "") .. "-" .. os.date("%d_%m_%Y") .. "-" .. math.random(1, 12345)
                f = io.open(cfg.secretary.meetingFolder .. "/" .. filename .. ".txt",  "w")
                if f then
                    f:write(m.raw)
                    say(channel or sender, "Raw summary available at: " .. cfg.secretary.publicURL .. filename .. ".txt")
                    f:close()
                end
            else
                say(channel or sender, "Could not send the email :(")
            end
        else
            say(channel or sender, "Invalid email address specified!")
        end
    else
        say(channel or sender, "Sorry, I couldn't find any previous meetings held in this channel.")
    end
end

-- meeting helper function (begin/start, end/stop and send)
function meeting(sender, channel, params)
    if channel then
        local now = os.date("!%c")
        local now_raw = os.date("%d_%m_%Y")
        local chan = channel:sub(2)
        if params == "start" or params == "begin" then
            if cfg.channel[channel] and cfg.channel[channel].allowLogging then
                IRCSocket:send("TOPIC " .. channel .. "\r\n")
                meetings[channel] = {
                    started = now,
                    started_raw = now_raw,
                    people = {},
                    topic = nil,
                    minutes = { {log = {}, topic = "Preface"} }
                }
                say(channel, "Meeting started at " .. now)
                say(channel, "Any message starting with [off] is considered off-the-record and will not be logged.")
            else
                say(channel, "Record keeping is not enabled for this channel. Please contact infrastructure.")
            end
        elseif params:match("^send") then
            meeting_email(sender, channel, params)
        elseif (params == "end" or params == "stop") and meetings[channel] then
            meetings[channel].ended = now
            local filename = chan:gsub("[^a-zA-Z#-_]", "") .. "-" .. meetings[channel].started_raw .. "-" .. math.random(1,12345) .. ".html"
            say(channel, "Meeting ended at " .. now)
            if meetings[channel].topic then
                IRCSocket:send( ("TOPIC %s :%s\r\n"):format(channel, meetings[channel].topic))
            end
            say(channel, "Minutes available at: " .. cfg.secretary.publicURL .. filename)
            local HTML = ""
            local raw = ""
            local f = io.open(cfg.secretary.meetingFolder .. "/" .. filename,  "w")
            if f then
                f:write( ([[
<!DOCTYPE html>
<html lang="en">
<head>
<meta http-equiv="Content-type" content="text/html;charset=UTF-8" />
<title>Meeting for %s, %s</title>
<link type="text/css" rel="stylesheet" href="agenda.css" />
</head>
<body>]]):format(channel, meetings[channel].started) )
                HTML = HTML .. ([[
<!DOCTYPE html>
<html lang="en">
<head>
<meta http-equiv="Content-type" content="text/html;charset=UTF-8" />
<title>Meeting for %s, %s</title>
</head>
<body>]]):format(channel, meetings[channel].started)
                f:write( ("<h1>Meeting in %s, started %s, ended %s:</h1>\n"):format(channel, meetings[channel].started, now ) )
                HTML = HTML .. ("<h2>Meeting in %s, started %s, ended %s:</h2>\n"):format(channel, meetings[channel].started, now )
                f:write([[
                <script type="text/javascript">
                    function disableStyles() {
                        for ( i=0; i<document.styleSheets.length; i++) {
	                        void(document.styleSheets.item(i).disabled=true);
                        }
                    }
                </script>
                 <a href="#" onclick="disableStyles();">Disable styles</a><br/> 
                 ]])
                local people = {}
                local actions = {}
                for person, lines in pairs(meetings[channel].people) do
                    table.insert(people, person)
                end
                local persons = table.concat(people, ", ")
                f:write("<p><b>Members present:</b> " .. persons .. "</p>")
                HTML = HTML .. ("<p><b>Members present:</b> " .. persons .. "</p>")
                raw = raw .. ("Members present: " .. persons .. "\n\n")
                f:write("<p><b>Meeting summary:</b></p><ol>")
                HTML = HTML ..("<p><b>Meeting summary:</b></p><ol>")
                raw = raw .. "----------------\nMeeting summary:\n----------------\n\n" 
                local tx = 0
                for k, topic in pairs(meetings[channel].minutes) do
                    local subs = ""
                    local subsraw = ""
                    tx = tx + 1
                    local m = 0
                    for k, line in pairs(topic.log) do
                        local t, sender, cmd, info = line:match("(%S+) %[(.-)%]: #(%S+) (.+)")
                        if cmd and (cmd == "info" or cmd == "link") and info and sender then
                            m = m + 1
                            subs = subs .. ("<li>%s (%s, <a href='#l%u.%u'>%s</a>)</li>"):format(info, sender, tx, k, t)
                            subsraw = subsraw .. ("  %s. %s (%s, %s)\n"):format(meeting_points[m] or "?", info:gsub("<a .->(.-)</a>", function(a) return a end), sender, tx, k, t)
                        end
                        if cmd and cmd == "action" and info and sender then
                            m = m + 1
                            table.insert(actions, ([[%s (%s, <a href='l%u.%u'>%s</a>)]]):format(info, sender, tx, k, t))
                            subs = subs .. ("<li>%s (%s, <a href='#l%u.%u'>%s</a>)</li>"):format(info, sender, tx, k, t)
                            subsraw = subsraw .. ("  %s. %s (%s, %s)\n"):format(meeting_points[m] or ">", info:gsub("<a .->(.-)</a>", function(a) return a end), sender, tx, k, t)
                        end
                    end
                    if subs ~= "" then subs = "<ol type='a'>"..subs.."</ol>" end
                    f:write( ("<li><a href='#%u'>%s</a>%s</li>"):format(k, topic.topic, subs) )
                    HTML = HTML .. ( ("<li><a href='#%u'>%s</a>%s</li>"):format(k, topic.topic, subs) )
                    raw = raw .. ("%s. %s\n%s\n"):format(k, topic.topic, subsraw)
                end
                f:write("</ol>")
                HTML = HTML .. "</ol>"
                
                if #actions > 0 then
                    f:write("<p><b>Actions:</b></p><ol>")
                    HTML = HTML .. ("<p><b>Actions:</b></p><ol>")
                    raw = raw .. "\n--------\nActions:\n--------\n"
                    for k, v in pairs(actions) do
                        f:write("<li>"..v.."</li>\n")
                        HTML = HTML .. ("<li>"..v.."</li>\n")
                        raw = raw .. "- " .. v:gsub("<a .->(.-)</a>", function(a) return a end) .. "\n"
                    end
                    f:write("</ol>\n")
                    HTML = HTML .. "</ol>"
                    raw = raw .. "\n"
                end
                tx = 0
                raw = raw .. "IRC log follows:\n\n"
                HTML = HTML .. "<h3>IRC log:</h3>"
                for k, topic in pairs(meetings[channel].minutes) do
                    tx = tx + 1
                    f:write( ("<h4><a name='%u'></a> %s </h4><p>"):format(k, topic.topic) )
                    HTML = HTML.. ( ("<h3><a name='%u'></a> %s </h3><p>"):format(k, topic.topic) )
                    raw = raw .. ("\n# %s. %s #\n"):format(k, topic.topic)
                    for k, line in pairs(topic.log) do
                        local t, sender, cmd, info = line:match("(%S+) %[(.-)%]: #(%S+) (.+)")
                        if cmd and (cmd == "info" or cmd == "action" or cmd == "link") and info and sender then
                            f:write( ("</p><div class='%s'><a name='l%u.%u'></a>%s: %s</div><p>\n"):format(cmd, tx, k, sender, info) )
                            HTML = HTML .. ( ("</p><div class='%s'><a name='l%u.%u'></a>%s: %s</div><p>\n"):format(cmd, tx, k, sender, info) )
                        else
                            f:write(("<a name='l%u.%u'></a>"):format(tx, k) .. line .. "<br/>\n")
                            HTML = HTML .. (("<a name='l%u.%u'></a>"):format(tx, k) .. line .. "<br/>\n")
                        end
                        raw = raw .. line:gsub("<a .->(.-)</a>", function(a) return a end) .. "\n"
                    end
                    f:write("</p>")
                    raw = raw .. "\n"
                end
                f:write("</body></html>")
                f:close()
                previousMeeting[channel] = {
                    raw = raw,
                    html = HTML,
                    date = meetings[channel].started,
                    reallyraw = meetings[channel]
                }
            end
            meetings[channel] = nil
        else
            say(channel, "Invalid command. Options are: 'meeting start', 'meeting end' or 'meeting send [email address]' (for sending summaries to a list).")
        end
    end
end


-- Register calllbacks --
registerEvent("meeting_topic_fetch", "332", server_callback_topic)
registerEvent("meeting_topic_set", "TOPIC", meeting_change_topic)
registerHelperFunction("meeting", meeting, "meeting [start|end|send foo@bar] - Starts/stops a meeting or sends out a meeting summary via email", 3)
registerLogger("meeting_logger", ".+", meeting_channel_message)
