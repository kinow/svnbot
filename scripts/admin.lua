-- admin.lua - Administrative helper functions (restart, reload, join/leave, set options)

-- Options that are allowed to be set via IRC. The rest must be manually set in asfbot.cfg
allowed_options = {
    'linesPerCommit',
    'truncateLines',
    'svnFormat',
    'gitFormat',
    'revisionHints',
    'log',
    'bugzilla',
    'svnRepo',
    'allowLogging',
    'log',
    'jiraName',
    'jiraFormat',
    'commentsFormat',
    'jenkins_url',
    'jenkins_match',
    'gitHub',
    'factoids'
}

-- Options that can have multiline values
multiline_options = {
    'svnFormat',
    'gitFormat',
    'jiraFormat',
    'commentsFormat'
}

-- Options that can be set, but can only contain URL characters
url_only_options = {
    'svnRepo',
    'bugzilla',
    'jenkins_url',
    'gitHub'
}

-- Function for reconfiguring the bot
function reload(sender, channel, params)
    say(channel or sender, "Reloading configuration and plugins, please wait...")
    cfg = config.read('asfbot.cfg')
    config.fix(cfg)
    loadExtensions(channel or sender)
    say(channel or sender, "Config + plugins loaded!")
end

-- Function for temporarily setting an option
function set_option(sender, channel, params)
    if not params:match("%s") and params:match("[a-zA-Z]+") then
        key = params:match("([a-zA-Z]+)")
        local val = cfg.channel[channel][key] or (cfg.reporting[key] and (cfg.reporting[key] .. " (inherited from global defaults)")) or 'nothing'
        val = val:gsub("\n", "\\n")
        say(channel or sender, ("%s is set to: %s"):format(key, val))
        return
    end
    local key, value = params:match("^(%S+) ([^\r\n]+)$")
    if not key or not value or not channel then
        say(channel or sender, "Syntax: option key [value]. Cannot be run through private messaging")
        return
    end
    
    -- Check if the option is in the whitelist
    local found = false
    for k, v in pairs(allowed_options) do
        if v == key then
            found = true
            break
        end
    end
    -- If not found, bork!
    if not found then
        say(channel or sender, "You are not allowed to set this option via IRC")
    -- Else, transform and save
    else
        local val = value
        -- true, false, nils and numbers
        if value == "true" then val = true end
        if value == "false" then val = false end
        if value:match("^(%d+)$") then val = tonumber(value) end
        if value == "nil" or value == "null" then val = nil end
        
        -- Multiline option?
        for k, v in pairs(multiline_options) do
            if v == key and type(val) == "string" then
                val = val:gsub("\\n", "\n")
                break
            end
        end
        
        -- Option that may only contain a URL?
        for k, v in pairs(url_only_options) do
            if v == key and type(val) == "string" then
                val = val:gsub("[^a-zA-Z0-9:/._%-%%&=+?]+", "")
                if val ~= value then
                    say(channel or sender, "This option can only be set to a valid URL")
                    return
                end
            end
        end
        -- Set the option and ack it.
        cfg.channel[channel] = cfg.channel[channel] or {}
        local oldVal = cfg.channel[channel][key] or 'nothing'
        cfg.channel[channel][key] = val
        say(channel or sender, ("Set option %s to '%s' (was '%s')"):format(key, value, tostring(oldVal)) )
    end
end

-- restart(): restarts the bot - only needed when the core script (asfbot.lua) gets changed.
function restart(sender, channel, params)
    if params ~= "confirm" then
        say(channel or sender, "Please type 'restart confirm' to confirm the restart!")
    else
        IRCSocket:send("QUIT :Restarting by order of " .. sender .. "\r\n\r\n")
        IRCSocket:close()
        os.execute("nohup lua-5.1 asfbot.lua &")
        os.exit()
    end
end

-- quit(): exits the program
function quit(sender, channel, params)
    if params ~= "confirm" then
        say(channel or sender, "Please type 'quit confirm' to confirm the exit!")
    else
        IRCSocket:send("QUIT :Shutting down by order of " .. sender .. "\r\n\r\n")
        IRCSocket:close()
        os.exit()
    end
end

-- joinChannel(): Joins a channel and sets up a temporary config space for it
function joinChannel(sender, channel, params)
    local chan = params:match("(#%S+)")
    if chan then
        say(channel or sender, "Joining " .. chan)
        IRCSocket:send("JOIN " .. chan .. "\r\n\r\n");
        cfg.channel[chan] = cfg.channel[chan] or { tags = {} }
        joinedChannels[chan] = true
    else
        say(channel or sender, "Erroneous channel name given")
    end
end

-- leaveChannel(): Leaves a channel, must be called from the channel ASFBot is leaving or with params
function leaveChannel(sender, channel, params)
    if params == "" then
        params = channel
    end
    params = params:match("(#%S+)")
    if params then 
        say(channel or sender, "Leaving " .. params .. ", bye bye!")
        IRCSocket:send("PART " .. params .. "\r\n\r\n");
        cfg.channel[k] = nil
        joinedChannels[params] = nil
    else
        say(channel or sender, "Erroneous channel name given.")
    end
end

-- Register 'options', 'restart' and 'reconfigure' as helper functions
registerHelperFunction("reload", reload, "reload - Reloads the current configuration and any installed plugins.", 10)
registerHelperFunction("restart", restart, "restart - Restarts the bot. Only needed to apply changes to the core program", 10)
registerHelperFunction("option", set_option, "option [key] [value] - Sets a channel specific option. Not all options can be set this way. Use 'nil' or 'null' to delete a channel specific option (and rely on global defaults).", 10)
registerHelperFunction("quit", quit, "quit - Exits the bot's program :(", 10)

-- Register join/leave
registerHelperFunction("join", joinChannel, "join [channel name] - Joins a channel", 8)
registerHelperFunction("leave", leaveChannel, "leave - Leaves a channel. Must be called from the channel to leave", 8)

