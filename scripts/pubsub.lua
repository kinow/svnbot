-- pubsub.lua - The big mess that is all the PubSub services :3
PubSubs = PubSubs or {}

-- countDirs(): Counts the number of folders edited
function countDirs(files)
    local dirs = {}
    for k, path in pairs(files) do
        local found = false
        local dir = path:match("^(.+)/[^/]+$")
        if dir then
            for k, v in pairs(dirs) do if v == dir then found = true end end
            if not found then table.insert(dirs, dir) end
        end
    end
    return #dirs
end

-- findRoot(): Finds the root folder in a changeset
function findRoot(files)
    if type(files) == "string" then files = {files} end
    local dirs = countDirs(files)
    local mod = "no path provided"
    if #files > 1 then
        local prefix = ""
        for i = 2, files[1]:len() do
            local valid = true
            xprefix = files[1]:sub(1,i)
            for k, v in pairs(files) do
                if (v:len() < i or not (v:sub(1,i) == xprefix)) then
                    valid = false
                    break
                end
            end
            if valid then
                prefix = xprefix
            else
                break
            end 
        end
        if prefix:len() > 2 then
            if prefix:sub(prefix:len()) ~= "/" then prefix = prefix .. "*" end
            local joined = table.concat(files, ", ")
            if joined:len() < 80 then
                mod = joined
            else
                mod = prefix .. " (" .. #files .. " files in " .. dirs .. " director" ..((dirs == 1 and "y") or "ies") .. ")"
            end
        else
            local joined = table.concat(files, ", ")
            if joined:len() < 80 then
                mod = joined
            else
                mod = "/ (" .. #files .. " files in " .. dirs .. " director" ..((dirs == 1 and "y") or "ies") .. ")"
            end
        end
    end
    if #files == 1 then mod = files[1] end
    return mod
end

--replaceCommitString(): Used to make foo|bar or foo:123 work.
function replaceCommitString(str, commit)
    str = str:gsub("{([^}]+)}", 
        function(a) 
            if a:match("|") then
                for thing in a:gmatch("([^|]+)") do
                    if commit[thing] then
                        return commit[thing]
                    end
                end
            end
            if a:match("%S+:%d+") then
                local key, length = a:match("(%S+):(%d+)")
                length = tonumber(length) or 1
                local b = commit[key] or "nil"
                if b:len() > length then
                    b = b:sub(1,length - 3) ..  "..."
                end
                return b
            end
            return commit[a] or "(nil)"
        end
    )
    return str
end

-- reportCommit(): Where a commit gets prepped and reported to IRC
function reportCommit(commit, channel, options)
    if IRCSocket and channel and channel:match("^#") then
        local format = options.svnFormat or cfg.reporting.svnFormat or "(no report format configured?)"
        local svnURL = ""
        local url = cfg.viewvc[commit.repository or ""] or ""
        if url and url:len() > 0 then
            svnURL = replaceCommitString(url, commit)
        end
        commit.link = svnURL
        local changed = {}
        if commit.changed then
            for k, v in pairs(commit.changed) do table.insert(changed, k) end 
        end
        commit.changed_paths = findRoot((#changed > 0 and changed) or commit.dirs_changed or {})
        if commit.repository == "git" or commit.repository == "git-prop-edit" then
            if commit.tag then
                commit.log = "New tag: " .. commit.tag
                commit.ref = commit.tag
                commit.hash = "xxxxxxx"
            end
            if commit.ref then
                commit.ref = commit.ref:gsub("refs/heads/", "") -- cut away 'refs/heads/', we don't need it.
            end
            commit.revision = "["..(commit.revision or "??") .. "]"
            if type(commit.files) == "table" then
                commit.changed_paths = findRoot(commit.files or {})
            elseif type(commit.files) == "string" then
                commit.changed_paths = commit.files
            end
            format = options.gitFormat or cfg.reporting.gitFormat or format
        end
        if commit.repository == "JIRA" then
            format = options.jiraFormat or cfg.reporting.jiraFormat or format
            if commit.instance and commit.ticket then
                if commit.text and commit.text:match("[^\r\n]") then
                    local ticket = commit.instance:lower().."-"..commit.ticket
                    if not latestComments[ticket] or type(latestComments[ticket]) ~= "table" then
                        latestComments[ticket] = {}
                    end
                    latestComments[ticket][#latestComments[ticket]+1] = commit.text
                end
            end
        end
        if commit.repository == "comments" then
            format = options.commentsFormat or cfg.reporting.commentsFormat or format
            commit.log = commit.log or ""
        end
        if commit.repository == "wiki" or commit.repository == "circonus" then
            format = options.wikiFormat or cfg.reporting.wikiFormat or format
            commit.log = commit.log or ""
        end
        -- truncateLines: Truncates foo\nbar\n\nbaz to foo bar\nbaz
        if options.truncateLines then
            commit.log = commit.log:gsub("([\r\n]+)", 
                function(a) 
                    if a:match("(\n.*\n)") then 
                        return "\n "
                    else
                        return " "
                    end
                end
                )
        end
        -- colored paths (visual aid for spotting branches)
        local coloredPath = commit.changed_paths
        coloredPath = coloredPath:gsub("/trunk/", "/<c7>trunk</c>/")
        coloredPath = coloredPath:gsub("/branches/([^/]+)/", "/<c7>branches/%1</c>/")
        coloredPath = coloredPath:gsub("/tags/([^/]+)/", "/<c7>tags/%1</c>/")
        commit.changed_paths_colored = coloredPath
        local goAhead = true
        if options.hook and type(options.hook) == "function" then
            local good, ret = pcall(function() return options.hook(commit, options) end)
            if not good then 
                say(cfg.irc.owner, "Error in hook for " .. channel .. ": " .. ret)
            else
                if type(ret) == "boolean" and ret == false then
                    goAhead = false
                elseif type(ret) == "string" then
                    say(channel, ret)
                end
            end
        end
        local output = replaceCommitString(format, commit)
        local maxLines = options.linesPerCommit or cfg.reporting.linesPerCommit or 5
        local i = 0
        if goAhead then
            for line in output:gmatch("([^\r\n]+)") do
                i = i + 1
                if i <= maxLines then
                    if i > 1 then line = ">> " .. line end
                    say(channel, line)
                else
                    if maxLines ~= 1 then                
                        say(channel, ">> ...")
                    end
                    break
                end
            end
        end
    end
end

-- The initial connection to pubsub services
function connectToPubSub(url)
    local server, port, uri = url:match("^([^:]+):(%d+)(/.+)$")
    print("Connecting to PubSub server " .. server .. "\n")
    local s = socket.tcp()
    s:settimeout(1)
    local success, err = s:connect(socket.dns.toip(server) or server, tonumber(port))
    if not success then
        print("Failed to connect: ".. err .. "\n")
        return false
    end
    s:send("GET " .. uri .. " HTTP/1.1\r\n");
    s:send("Host: " .. server .. "\r\n\r\n");
    s:settimeout(1)
    return s
end


-- Reading one or more line from a pubsub service
function readPubSub(s)
    for k, v in pairs(PubSubs) do
        local socket = v[1]
        local url = v[2]
        local retries = v[3] or 0
        local lastPing = v[4] or os.time()
        if socket then
            while true do
                local receive, err = socket:receive('*l')
                if receive and receive:match("^([[a-zA-Z0-9]+)$") then
                    local howMuch = tonumber(receive, 16)
                    receive, err = socket:receive(howMuch+2)
                end
                if receive then
                    v[4] = os.time()
                    if receive:match([[^{"commit":]]) and receive:len() > 3 then
                        
                        local c = JSON:decode(receive:gsub("\0", ""):gsub(",\r?\n?$", ""))
                        local commit = c.commit or {}
                        local changed = {}
                        if commit.changed then
                            for k, v in pairs(commit.changed) do table.insert(changed, k) end 
                        end
                        commit.dirs_changed = commit.dirs_changed or (#changed > 0 and changed) or {commit.project }
                        if type(commit.dirs_changed) == "string" then
                            commit.dirs_changed = {commit.dirs_changed}
                        end
                        if commit.log then
                            for k, v in pairs(cfg.channel) do
                                local found = false
                                for k, dir in pairs(v.tags or {}) do
                                    for k, cdir in pairs(commit.dirs_changed) do
                                        if cdir:match("^" .. dir) then
                                            found = true
                                            break
                                        end
                                    end
                                end
                                if found then
                                    reportCommit(commit, k, v)
                                end
                            end
                        end
                    end
                else
                    if err == "timeout" then
                        if lastPing < (os.time() - 30) then
                            if config.alertChannel then
                                say(cfg.irc.alertChannel, ("PubSub connection to %s has timed out, dropping connection"):format(url) )
                            end
                            err = "disconnected"
                            retries = 0
                        end
                    end
                    if err ~= "timeout" then
                        if retries == 0 then
                            if config.alertChannel then
                                say(cfg.irc.alertChannel, ("PubSub connection to %s has failed, trying to reconnect"):format(url) )
                            end
                        elseif retries == 1 then
                            say(config.owner, ("Still cannot connect to %s - trying again"):format(url) )
                            if config.alertChannel then
                                say(cfg.irc.alertChannel, ("Still cannot connect to %s - trying again"):format(url) )
                            end
                        end
                        socket = connectToPubSub(url)  -- reconnect to PubSub server
                        v[1] = socket
                        if socket then 
                            v[3] = 0
                            say(s, config.owner, "Reconnected to " .. url)
                            if config.alertChannel then
                                say(s, cfg.irc.alertChannel, "Reconnected to " .. url)
                            end
                        else
                            retries = retries + 1
                            v[3] = retries
                        end
                    end
                    break -- timeout, nothing more to receive at the moment, let's get back to responding to PINGs
                end
            end
        elseif v[3] and v[3] < 3 then
            socket = connectToPubSub(url) -- Connection failed last time, let's try again.
            v[1] = socket
            if socket then 
                v[3] = 0 
                say(cfg.irc.owner, "Reconnected to " .. url) -- it's always okay to spam Humbedooh
                if config.alertChannel then
                    say(cfg.irc.alertChannel, "Reconnected to " .. url)
                end
            else
                if retries == 0 then
                    if config.alertChannel then
                        say(cfg.irc.alertChannel, ("PubSub connection to %s has failed, trying to reconnect"):format(url) )
                    end
                elseif retries == 1 then
                    if config.alertChannel then
                        say(cfg.irc.alertChannel, ("Still cannot connect to %s - trying again"):format(url) )
                    end
                elseif retries == 2 then
                    if config.owner then
                        say(cfg.irc.owner, ("Alert: Cannot connect to %s - tried 3 times so far."):format(url) )
                    end
                end
                retries = retries + 1
                v[3] = retries
            end
        end
    end
end

-- 'subscribe [tag]'
function subscribe(sender, channel, params)
    for k, v in pairs(cfg.channel) do
        if k == channel then
            v.tags = v.tags or {}
            table.insert(v.tags, params)
            say(channel or sender, "Subscribed to " .. params)
            break
        end
    end
end

-- 'unsubscribe [tag]'
function unsubscribe(sender, channel, params)
    for k, v in pairs(cfg.channel) do
        if k == channel then
            for k, dir in pairs(v.tags) do
                if dir == params then v.tags[k] = nil end
            end
            say(channel or sender, "Unsubscribed from " .. params)
            break
        end
    end
end

-- 'subs'
function listSubs(sender, channel, params)
    for k, v in pairs(cfg.channel) do
        if k == channel then
            local svns = table.concat(v.tags or {}, ", ")
            say(channel or sender, "Currently subscribed to the following tags: " .. svns)
            break
        end
    end
end

-- reconnect to a server if told so
function reconnect(sender, channel, params)
    if params == "" then
        say(channel or sender, "Please specify a server to reconnect to (hint: see the 'status' command) or use 'all' to reconnect to all services")
    else
        local found = false
        for k, v in pairs(PubSubs) do
            local url = v[2]
            local server = url:match("^([^:]+)")
            local ip = socket.dns.toip(server) or server
            -- Either we have a specific server to reconnect to, or 'all'
            if params and (params == server or params == "all") then
                found = true
                say(channel or sender, ("Re-establishing connection to %s (%s)..."):format(server, ip))
                if sock then sock:close() end
                sock = connectToPubSub(url)
                if sock then say(channel or sender, ("%s (%s): Connection established"):format(server, ip))
                else say(channel or sender, ("%s (%s): Connection failed, will retry in a couple of seconds"):format(server, ip))
                end
                v[1] = sock
            end
        end
        if not found then
            say(channel or sender, "No such host to connect to. See the 'status' command for a list of available servers")
        end
    end
end

-- connection status list
function pubsub_status(sender, channel, params)
    say(channel or sender, "Connection status:")
    for k, v in pairs(PubSubs) do
        local sock = v[1]
        local url = v[2]
        local retries = v[3] or 0
        local server = url:match("^([^:]+)")
        local ip = server
        if ip:match("[^0-9.]") then -- if this is not an IP, look up the IP
            ip = socket.dns.toip(server) or server
        end
        if sock then say(channel or sender, ("%s (%s): Connection established"):format(server, ip))
        else say(channel or sender, ("%s (%s): Connection failed (%u retries so far)"):format(server, ip, retries))
        end
    end
end

-- Register sub, unsub and subs as helper functions
registerHelperFunction("subscribe", subscribe, "subscribe [tag] - Subscribes ASFBot to a specific svn/git/jira tag.", 6)
registerHelperFunction("unsubscribe", unsubscribe, "unsubscribe [tag] - Unsubscribes ASFBot from a specific svn/git/jira tag.", 6)
registerHelperFunction("subs", listSubs, "subs - Lists the current tags ASFBot is subscribed to for the active channel", 3)

-- Register status and reconnect as helpers
registerHelperFunction("status", pubsub_status, "status - Display the current PubSub connections", 8)
registerHelperFunction("reconnect", reconnect, "reconnect [server|all] - Reconnect to one or all servers", 8)

-- Connect and set up PubSubs if this is the first time we're running this script
if #PubSubs == 0 then
    for k, url in pairs(cfg.pubsub.repositories) do
        local sock = connectToPubSub(url)
        table.insert(PubSubs, {sock, url, 0})
    end
end

-- Register timed callback for pubsub reads
registerTimedCallback("pubsubs", readPubSub, 2, false)

