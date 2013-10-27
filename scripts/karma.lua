-- This is the karma plugin for ASFBot. It manages karma configurations and 
-- is used for assessing whether a user has access to a specific function or not.

karmaWaitingList = {}

-- hasKarma(): returns true if the user has the required karma, false otherwise.
function hasKarma(sender, level)
    if level == 0 then
        return true
    end
    for k, v in pairs(cfg.karma) do
        if (v.id == sender.identity and v.level >= level) then
            return true
        end
    end
    return false
end

-- 311 IRC callback for WHOIS checks
function karma_callback_whois(params)
    print(params)
    local nick, user, host = params:match("%S+ (%S+) (%S+) (%S+)")
    if nick and karmaWaitingList[nick] then
        cfg.karma[nick] = { id = host, level = karmaWaitingList[nick].level }
        say(karmaWaitingList[nick].channel, "Gave karma to " .. nick)
        karmaWaitingList[nick] = nil
    end
end

-- Karma control function
function karmaControl(sender, channel, params)
    if params == "" or params == "list" then
        local tbl = {}
        for k, v in pairs(cfg.karma) do table.insert(tbl, k .. "(" .. v.level ..")") end
        local karmaList = table.concat(tbl, ", ")
        say(channel or sender, "The following users have karma: " .. karmaList)
    else
        local cmd, usr, level = params:match("(%S+) (%S+) (%d+)")
        if not cmd then
            cmd, usr = params:match("(%S+) (%S+)")
        end
        if cmd and usr then
            if cmd == "add" and level then
                level = tonumber(level)
                if level > 9 then -- anything above 9 should be added to asfbot.cfg permanently
                    level = 9
                end
                if cfg.karma[usr] then
                    say(channel or sender, usr .. " already has karma!")
                else
                    -- queue karma request till we have an identity of the user
                    say(channel or sender, "Looking up " .. usr .. "...")
                    karmaWaitingList[usr] = {channel = channel or sender, level = level}
                    IRCSocket:send( ("WHOIS %s\r\n"):format(usr) )
                end
            elseif cmd == "add" then
                say(channel or sender, "You need to specify a karma level!")
            elseif cmd == "remove" then
                if usr == sender.name then
                    say(channel or sender, "You can't remove yourself from the list - get someone else to do it!")
                    return
                end
                local found = cfg.karma[usr]
                cfg.karma[usr] = nil
                if found then
                    say(channel or sender, usr .. " no longer has karma.")
                else
                    say(channel or sender, usr .. " never had any karma to begin with.")
                end
            end
        else 
            say(channel or sender, "Invalid syntax! see 'help karma' for a list of valid commands.")
        end
    end
end

registerHelperFunction("karma", karmaControl, "karma [add|remove] [recipient] [level] - Adds or removes karma from a user", 10)
registerEvent("whois_callback", "311", karma_callback_whois)

