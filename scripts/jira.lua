-- jira.lua - JIRA helper functions
latestComments = latestComments or {}

-- Function for getting info about a ticket
function jira_urls(sender, channel, channelLine)
    -- Do we have JIRA hints enabled in this channel?
    if sender and channel and cfg.channel[channel] and cfg.channel[channel].jiraName then
        -- pluck out the ticket name
        for jiraName in cfg.channel[channel].jiraName:gmatch("(%S+)") do
            local ticket = channelLine:match("^[A-Za-z]+-(%d+)%s*$") or channelLine:match("^jira [A-Za-z]+-(%d+)%s*$")
            if not channelLine:lower():match("^" .. jiraName:lower()) and not channelLine:match("^jira") then 
                ticket = nil
            end
            if ticket then
                ticket = jiraName .. "-" .. ticket
                -- Fetch JSON from JIRA
                local body = GET( ("https://issues.apache.org:443/jira/rest/api/latest/issue/%s?fields=summary"):format(ticket))
                if body and body:len() > 0 then
                    local description = ""
                    local okay, entry = pcall(function() return JSON:decode(body) end)
                    if okay and entry then
                        if entry.fields and entry.fields.summary then
                            description = entry.fields.summary
                        elseif entry.fields and entry.fields.description then
                            description = entry.fields.description:match("([^\r\n]+)")
                        end
                        if description:len() > 150 then
                            description = description:sub(1,148) .. "..."
                        end
                    else
                        description = "Could not get description (JSON error?)"
                    end
                    if description:len() > 0 then
                        say(channel or sender, ("%s: https://issues.apache.org/jira/browse/%s - %s"):format(sender, ticket, description))
                    else
                        say(channel or sender, ("%s: Sorry, I couldn't find any information about %s!"):format(sender, ticket))
                    end
                else
                    say(channel or sender, ("%s: https://issues.apache.org/jira/browse/%s"):format(sender, ticket))
                end
            end
        end
    end
end

-- Function for getting the Nth latest message about a JIRA issue
local nth = {'st','nd','rd'}

function get_jira_message(sender, channel, params)
    params = params or ""
    local ticket, number = params:match("(%S+) (%d+)")
    if not ticket then ticket = params end
    number = (tonumber(number or 1) or 1)
    local n = number .. (nth[(number)%10] or "th") .. " "
    local comments = latestComments[ticket:lower()]
    local comment = false
    if comments and type(comments) == "table" then
        comment = comments[#comments-(number-1)]
    elseif type(comments) == "string" then
        comment = comments
    end
    if comment then
        local maxLines = 8
        say(channel or sender, (number > 1 and n or "") .. "last message pertaining to " .. ticket:upper() .. ":")
        local i = 0
        for line in comment:gmatch("([^\r\n]+)") do
            if line and not line:match("^%s") then
                i = i + 1
                if i <= maxLines then
                    line = ">> " .. line
                    say(channel or sender, line)
                else
                    if maxLines ~= 1 then                
                        say(channel or sender, ">> ...")
                    end
                    break
                end
            end
        end
    else
        say(channel or sender, "I don't have any info on that subject.")
    end
end

function jira_reply(sender, channel, params)
    local ticket, message = params:match("^([A-Za-z]+%-%d+)%s+(.+)$") -- accept only INSTANCE-1234 as ticket
    if not ticket or not message then
        say(s, channel or sender, "Syntax: comment INSTANCE-1234 comment")
        return
    end
    local response = JSON:encode({body = ("Comment from %s via IRC:\n%s"):format(sender, message)})
    local f = io.open("jira_json.txt", "w")
    if f then
        f:write(response)
        f:flush()
        f:close()
        -- This uses CURL for the time being, but should be considered perfectly safe, as the URL is hardcoded and the instance ID can only contain [A-Z0-9]
        os.execute( ("curl --silent https://%s@issues.apache.org/jira/rest/api/latest/issue/%s/comment -H \"Content-Type: application/json\" -H \"Accept: application/json\" -X POST -d @jira_json.txt"):format(cfg.secretary.jiraCredentials or "", ticket))
        say(channel or sender, "Commented on " .. ticket)
    else
        say(channel or sender, "Could not create JSON object")
    end
end


function pasteData(data)
    local f = io.open("output.txt", "w")
    if f then
        f:write(data)
        f:close()
        -- Shouldn't be any security concerns here, curl reads from a file and posts to a hardcoded URL
        local prg = io.popen( ([[curl -F type=nocode -F "token=%s" -F paste=@output.txt https://paste.apache.org/store]]):format(cfg.secretary.pasteToken), "r")
        if prg then
            local link = prg:read("*l")
            prg:close()
            return link
        end
    end
end


-- Function for getting attachments from a ticket
function jira_attachments(sender, channel, params)
    -- pluck out the ticket name
    local ticket = params:match("^([A-Za-z]+-%d+)%s*$")
    if ticket then
        -- Fetch JSON from JIRA
        local body = GET( ("https://issues.apache.org:443/jira/browse/%s"):format(ticket))
        if body and body:len() > 0 then
            say(channel or sender, ("%s: Gathering attachments, please hold..."):format(sender))
            local k = 0
            local found = {}
            for file in body:gmatch("/jira/secure/attachment/([^\"]+)") do
                if not found[file] then
                    found[file] = true
                    local data = GET(("https://issues.apache.org:443/jira/secure/attachment/%s"):format(file))
                    if data and data:len() > 0 then
                        k = k + 1
                        link = pasteData(data)
                        if link then
                            say(channel or sender, ("%s: Attachment no. %u: %s"):format(sender, k, link))
                        end
                    end
                end
            end
            say(channel or sender, ("%s: End of attachments list"):format(sender))
        else
            say(channel or sender, ("%s: Sorry, I couldn't find any information about %s!"):format(sender, ticket))
        end
    else
        say(channel or sender, ("%s: Please provide a valid JIRA ticket name"):format(sender))
    end
end

-- Function for searching for JIRA tickets
function jira_search(sender, channel, params)
    params = params:gsub("[^'%sa-zA-Z0-9:/._%-%%&=+?]+", "")
    params = params:gsub("%s", "%%20")
    local chan = ""
    if cfg.channel[channel].jiraName and not cfg.channel[channel].jiraName:match("(%s)") then
        chan = "project%20%3D%20" .. cfg.channel[channel].jiraName .. "%20AND%20"
    end
    if params:len() > 2 then
        -- Fetch JSON from JIRA
        local body = GET("https://issues.apache.org/jira/rest/api/latest/search?jql="..chan.."status%20in%20%28Open%2C%20Reopened%2C%20%22Waiting%20for%20user%22%2C%20%22Waiting%20for%20Infra%22%29%20AND%20(summary%20~%20%22"..params.."%22%20OR%20text%20~%20%22"..params.."%22)&maxResults=5")
        if body and body:len() > 0 then
            local description = ""
            local okay, entry = pcall(function() return JSON:decode(body) end)
            if okay and entry and entry.issues and #entry.issues > 0 then
                for k, result in pairs(entry.issues) do
                    if k > 5 then break end
                    local desc = "No description available"
                    if result.fields and result.fields.summary then
                        desc = result.fields.summary
                        if desc:len() > 100 then
                            desc = desc:sub(1,97) .. "..."
                        end
                    end
                    say(channel or sender, ("https://issues.apache.org/jira/browse/%s - %s"):format(result.key, desc) )
                end
            else
                say(channel or sender, "Your search returned no matches :/")
            end
        else
            say(channel or sender, ("%s: Sorry, I couldn't find any matches!"):format(sender))
        end
    else
        say(channel or sender, ("%s: Please provide a valid query string"):format(sender))
    end
end

-- Register FOO-1234 as a callback in the logger
registerLogger("jira_urls", "^[A-Za-z]+-%d+", jira_urls)

-- register 'latest' and 'comment' as commands
registerHelperFunction("latest", get_jira_message, "latest [ticket ID] [message no] - Retrieves the Nth latest message from a JIRA ticket", 0)
registerHelperFunction("comment", jira_reply, "comment [ticket ID] [message] - Adds a comment to the specified JIRA ticket", 3)
registerHelperFunction("attachments", jira_attachments, "attachments [ticket ID] - Fetches attachments from a JIRA ticket and posts them to paste.a.o", 3)
registerHelperFunction("search", jira_search, "search [query] - Searches JIRA for tickets matching the criteria", 3)
