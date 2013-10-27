-- Libraries used by ASFBot
socket = require "socket"     -- Lua Socket
http = require "socket.http"  -- Lua Socket HTTP Library
ltn12 = require "ltn12"       -- LTN12 Sink
ssl = require "ssl"           -- SSL Library
JSON = require "JSON"         -- JSON: http://regex.info/code/JSON.lua
config = require "config"     -- configuration reader

-- Globally declared variables and configuration
IRCSocket = false
HelperFunctions = {}
TimedCallbacks = {}
EventCallbacks = {}
Loggers = {}
PubSubSockets = {}
cfg = config.read('asfbot.cfg')
hasStarted = false
lastUpdate = 0
joinedChannels = {}

-- Fix up some vars in the config
config.fix(cfg)


--[[ Core functions ]]--

-- say(socket, recipient, message): Sends a message to a user or a channel
-- Messages can be formatted using <b>,<u> and <cN>
function say(recipient, msg)
    msg = msg:gsub("<b>", string.char(0x02))
    msg = msg:gsub("<u>", string.char(0x1f))
    msg = msg:gsub("</b>", string.char(0x0f))
    msg = msg:gsub("</u>", string.char(0x0f))
    msg = msg:gsub("<c([0-9,]*)>", function(a) return string.char(0x03)..(a or "") end)
    msg = msg:gsub("</c>", string.char(0x03) .. "")
    if type(recipient) == "table" then
        recipient = recipient.name
    end
    if IRCSocket and recipient then 
        for line in msg:gmatch("([^\r\n]+)") do
            if recipient:match("^#") then
                local channel = recipient
                if cfg.channel[channel] and cfg.channel[channel].log and writeToLog then
                    writeToLog(channel, ("%s MSG ASFBot %s\r\n"):format(os.time(), msg))
                end
            end
            IRCSocket:send( ("PRIVMSG %s :%s\r\n"):format(recipient, line) )
            os.execute("sleep 0.25")
        end
    end
end

-- loadExtensions(): Loads the scripts associated with ASFBot
function loadExtensions(channel)
    -- Unload callbacks
    HelperFunctions = {}
    IRCCallbacks = {}
    TimedCallbacks = {}
    
    -- For each file in the scripts dir, load it.
    local p = io.popen("ls scripts/") -- skip installing LFS
    if p then
        while true do
            local filename = p:read("*l")
            if not filename then break end
            if filename:match("%.lua$") then
                local ok, err = pcall(loadfile("scripts/"..filename))
                if not ok then
                    if s and err then 
                        say(channel or cfg.irc.owner, err)
                    end
                end
            end
        end
        p:close()
    end
end

-- registerHelperFunction(): Register an IRC helper function with ASFBot
-- This is your basic ASFBot functions such as help, reload, karma, etc etc
function registerHelperFunction(functionName, functionCallback, functionDescription, karmaRequired)
    if type(functionCallback) == "function" then
        HelperFunctions[functionName] = {
            callback =      functionCallback,
            description =   functionDescription,
            karma =         karmaRequired or 0
        }
    end
end

-- registerTimedCallback(): Register a callback that happens every N seconds.
-- This is only used for the PubSub plugin which needs to check the PubSub channels for updates
function registerTimedCallback(functionName, functionCallback, functionInterval, runAtStart)
    if type(functionCallback) == "function" then
        TimedCallbacks[functionName] = {
            callback =  functionCallback,
            interval =  functionInterval,
            lastRun =   os.time()
        }
        if runAtStart and not hasStarted then
            pcall(function() functionCallback() end)
        end
    end
end

-- registerLogger(): Register a channel logger callback
-- This is used for the channel logger, r1234 callbacks and the meeting plugin
function registerLogger(functionName, functionMatch, functionCallback)
    if type(functionCallback) == "function" then
        Loggers[functionName] = {
            match =     functionMatch or ".+",
            callback =  functionCallback
        }
    end
end

-- registerEvent(): Registers a callback for an IRC event
-- This is stuff like topic changes, WHOIS lookups etc.
function registerEvent(functionName, functionEvent, functionCallback)
    if type(functionCallback) == "function" then
        EventCallbacks[functionName] = {
            event =     functionEvent,
            callback =  functionCallback
        }
    end
end


-- runCallbacks(): Runs timed callbacks, such as PubSub listeners
function runCallbacks()
    local now = os.time()
    for k, entry in pairs(TimedCallbacks) do
        if (entry.lastRun + entry.interval) < now then
            local okay, err = pcall(function() entry.callback() end)
            if not okay then
                print(err)
            end
            entry.lastRun = now
        end
    end
end


-- handleMessage(): Handles an incoming message in a channel or privately
function handleMessage(line)
    if line then
        -- Split up the sender name and his/her identity
        local sender, identity = line:match("^:([^%!]+)!.-@(%S+)")
        -- Check if this message is in a channel or a private one
        local channel = line:match("PRIVMSG (#%S+) :") or nil
        
        -- Parse line, optional command and recipient of command
        local channelLine = line:match("PRIVMSG #%S+ :(.+)") or ""
        local text = nil
        local recipient = nil
        if channel then
            recipient, text = channelLine:match("([^:,]+)[,:]%s+(.+)")
        end
        if not channel then recipient, text = line:match("PRIVMSG ([^ ]+) :(.+)") end
        local ignore = false
        
        -- Is this a line for our logger functions? (this now comes before commands are processed)
        if channel and channelLine then
            for k, v in pairs(Loggers) do
                if channelLine:match(v.match or ".+") then
                    local senderStruct = { name = sender, identity = identity }
                    if not ignore then
                        okay, ignore = pcall(function() return v.callback(sender, channel, channelLine, senderStruct) end)
                    end
                    if not okay then print(ignore) end
                end
            end
        end
        
        -- Is this meant for ASFBot? (or asfbot or aSfBoT etc)
        if sender and text and recipient:lower() == cfg.irc.nick:lower() and not ignore then
            local found = false
            local command = text:match("^(%S+)") or ""
            local params = text:sub(command:len()+2):gsub("^%s+", "")
            
            -- We only want a-zA-Z as a command
            command = (command or ""):gsub("[^a-zA-Z]+",""):lower()
            
            -- Is this a helper command we understand?
            if HelperFunctions[command] then
                -- Check if sender has karma to do this
                if hasKarma( {name=sender, identity = identity}, HelperFunctions[command].karma ) then
                    local ok, err = pcall(function() HelperFunctions[command].callback(sender, channel, params) end)
                    if err then
                        say(channel or sender, "<b>Error in callback:</b> " .. err)
                    end
                else
                    say(channel or sender, "You do not have enough karma to use this command")
                end
            -- We don't know this command, so let's bork
            else
                say(channel or sender, ("Unknown command; %s - try 'help' for a list of available commands."):format(command))
            end
        end
    end
end


-- readIRC(): Reads a line from the IRC socket and deals with it
function readIRC(s)
    while true do
        local receive, err = IRCSocket:receive('*l')
        local now = os.time()
        if receive then
--            print(receive)
            receive = receive:gsub("[\r]+", "") -- chop away \r if it somehow snuck in
            -- Ping? PONG!
            if string.find(receive, "PING :") then
                IRCSocket:send("PONG :" .. string.sub(receive, (string.find(receive, "PING :") + 6)) .. "\r\n\r\n")
            else
                -- private/channel messages
                if string.find(receive, "PRIVMSG") then
                    handleMessage(receive)
                    
                -- topic changes, joins/leaves etc
                elseif string.match(receive, "^%S+ ([A-Z]+) #%S+") then
                    local who, ident, cmd, channel, params = string.match(receive, "^:([^!]+)!(%S+) ([A-Z]+) (#%S+)(.*)")
                    if params then params = params:sub(3) end
                    -- Do we have any callbacks registered for this type of command?
                    for k, v in pairs(EventCallbacks) do
                        if cmd and cmd:upper() == v.event then
                            pcall(function() v.callback(who, ident, channel, params) end)
                        end
                    end
                -- identity responses etc
                elseif string.match(receive, ":%S+ (%d+) .+") then
                    local server, code, params = string.match(receive, ":(%S+) (%d+) (.+)")
                    for k, v in pairs(EventCallbacks) do
                        if code == v.event then
                            pcall(function() v.callback(params) end)
                        end
                    end 
                end
            end
        -- if the server closed the connection, break the loop and reconnect
        elseif err == "closed" then
            break
        end
        
        -- Do timed callbacks
        if (now - lastUpdate > 2) then
            runCallbacks(s)
            lastUpdate = os.time()
        end 
    end
end

-- Self explanatory, connects to IRC and joins channels
function connectToIRC()
    local s = socket.tcp()
    IRCSocket = s
    local success, err = s:connect(socket.dns.toip(cfg.irc.server), 6667)
    if not success then
        print("Failed to connect: ".. err .. "\n")
        return false
    end
    s:send("USER " .. cfg.irc.username .. " " .. " " .. cfg.irc.nick .. " " .. cfg.irc.nick .. " " .. ":" .. cfg.irc.realname .. "\r\n\r\n")
    s:send("NICK " .. cfg.irc.nick .. "\r\n\r\n")
    if cfg.irc.password then 
        s:send("PRIVMSG nickserv :identify " .. cfg.irc.password .. "\r\n\r\n");
    end
    for k, entry in pairs(cfg.channel) do
        print("Joining " .. k)
        s:send("JOIN " .. k .. "\r\n\r\n");
        s:receive("*l")
        os.execute("sleep 0.5")
        joinedChannels[k] = true
    end
    s:settimeout(1)
    return s
end

-- Load plugins
loadExtensions()


-- Idle and read from IRC and PubSubs
while true do
    IRCSocket = connectToIRC()
    if IRCSocket then
        print "Idling..."
        readIRC(s)
    else
        print("Connection failed, retrying...")
        os.execute("sleep 5")
    end
end
