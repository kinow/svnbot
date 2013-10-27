#!/usr/local/bin/lua-5.1

local out = nil -- Plain text output, set to nil to disable
local pubsub = true -- post to local pubsub? (true/false)

local JSON = require "JSON"
local socket
if pubsub then
    socket = require "socket"
end

function parse_headers(data)
    local headers = {}
    data = ("\n" .. data .. "$end$:\n"):gsub("\r", "")
    local i, j = 1, 1
    local key, value, _
    while 1 do
        j = string.find(data, "\n%S-:", i+1)
        if not j then break end
        _, _, key, value = string.find(string.sub(data, i+1, j-1), "(%S-):(.*)")
        value = string.gsub(value or "", "\r\n", "\n")
        value = string.gsub(value, "\n%s*", " "):gsub("^%s*", "")
        if key then
            key = string.lower(key)
            if headers[key] then headers[key] = headers[key] .. ", " ..  value
            else headers[key] = value end
        end
        i, j = j, i
    end
    return headers
end

function parse(message)
    local _, headers, body
    _, _, headers, body = string.find(message, "^(.-\r?\n)\r?\n(.*)")
    headers = headers or ""
    body = body or ""
    return { headers = parse_headers(headers), body = body }
end

do
    local input = io.read("*a")
    local message = parse(input)
    if message.headers.subject and message.headers.from then
        -- Check for JIRA messages
        from = message.headers.from:match([[^"(.-) %(JIRA%)"]])
        if from then 
            if out then
                local f = io.open(out, "a")
                if f then
                  local hash = string.format("%x8x%8x", math.random(1,os.time()), os.time())
                  f:write( ("%s <%s> %s\n"):format(hash, from, message.headers.subject) )
                  f:close()
                end
            end
            if pubsub then
                local long, skip = {}, true
                for line in message.body:gmatch("([^\r\n]+)") do
                    if line:match("^>") then break end
                    if not skip and not line:match("^%s+$") then table.insert(long, line) end
                    if line:match("^%-+$") then
                        skip = false
                    end
                end
                local action = message.headers.subject:match("%[jira%] (.+)") or "??"
                local instance, ticket = message.headers.subject:match("%((%S+)%-(%d+)%)")
                if instance and ticket then
                    local commit = { repository="JIRA", text = table.concat(long, "\n"), dirs_changed = {"JIRA:"..instance}, instance=instance, ticket=ticket, log = ("%s %s"):format(from, action) }
                    local out = JSON:encode({commit=commit})
                    local s = socket.tcp()
                    s:settimeout(0.5)
                    local success, err = s:connect("127.0.0.1", 2069)
                    if success then
                        s:send("PUT /json HTTP/1.1\r\n")
                        s:send("Content-Length: " .. out:len() + 2)
                        s:send("Host: localhost\r\n\r\n")
                        s:send(out .."\r\n")
                        s:shutdown()
                        s:close()
                    else
                        print(err)
                    end
                end
            end
        end
        -- Check for wiki updates
        if message.headers.from:match("wikidiffs@apache.org") then
            local wiki = message.headers.subject:match("(%[(.-) Wiki)")
            local trivial = message.headers.subject:match("Trivial Update")
            if wiki then
                local page, editor, changeset, what, line = message.body:match("The \"(.-)\" page has been changed by (.-):%s+(http://%S+)%s+([^\r\n]+)[\r\n]+([^\r\n]+)")
                if page and editor and changeset then
                    local upd = trivial and "Trivial update" or "Update"
                    local comment = line
                    if what == "New page" then
                        comment = "New page created"
                    end
                    local commit = { repository = "wiki", dirs_changed = {"wiki:" .. wiki}, log = ("%s of '%s' by %s - %s\n%s"):format(upd, page, editor, changeset, comment) }
                    local out = JSON:encode({commit=commit})
                    local s = socket.tcp()
                    s:settimeout(0.5)
                    local success, err = s:connect("127.0.0.1", 2069)
                    if success then
                        s:send("PUT /json HTTP/1.1\r\n")
                        s:send("Content-Length: " .. out:len() + 2)
                        s:send("Host: localhost\r\n\r\n")
                        s:send(out .."\r\n")
                        s:shutdown()
                        s:close()
                    else
                        print(err)
                    end
                end
            end
        end
    end
end
