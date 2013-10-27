-- wall.lua - implements the 'wall' feature for broadcasting a message to multiple channels at once

function wall(sender, channel, params)
    -- Prepend [Announcement] to the msg
    params = "[Announcement] " .. params
    
    -- Then, speak up in the channels we're permanently in, unless told not to.
    for channel, entry in pairs(cfg.channel) do
        if not entry.hideAlerts then
            say(channel, params)
        end
    end
    
    -- Then, speak up in the other channels (and join/leave them)
    if cfg.wall and cfg.wall.channels then
        for channel in cfg.wall.channels:gmatch("(#%S+)") do
            IRCSocket:send( ("JOIN %s\r\n\r\n"):format(channel) )
            say(channel, params)
            IRCSocket:send( ("PART %s\r\n\r\n"):format(channel) )
        end
    end
end

registerHelperFunction("wall", wall, "wall [message] - Sends a message to all channels ASFBot is configured to access", 8)

