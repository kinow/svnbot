-- factoids.lua - channel specific factoids

function factoid_get_channel(channel)
    local chan = channel
    if type(cfg.channel[channel].factoids) == "string" then
        chan = "#" .. cfg.channel[channel].factoids
    end
    return chan
end

function forget_factoid(sender, channel, params)
    if cfg.channel[channel] and cfg.channel[channel].factoids then
        local chan = factoid_get_channel(channel)
        factoids[chan] = factoids[chan] or {}
        local trigger = params:match("^(.+)$")
        if trigger then
                trigger = trigger:gsub("[%s%?.!]+$", ""):lower()
                local fact = factoids[chan][trigger]
                if fact then
                    factoids[chan][trigger] = nil
                    saveFactoids(chan)
                    say(channel or sender, ("I forgot '%s'"):format(trigger))
                else
                    say(channel or sender, ("I don't have anything called '%s' :("):format(trigger))
                end
            return true
        end
    else
        say(channel or sender, "Factoids aren't enabled for this channel :(")
    end
end

function list_factoids(sender, channel, params)
    if cfg.channel[channel] and cfg.channel[channel].factoids then
        local chan = factoid_get_channel(channel)
        factoids[chan] = factoids[chan] or {}
        facts = ""
        for trigger, fact in pairs(factoids[chan]) do
            facts = facts .. ("%s: %s\n"):format(trigger, fact)
        end
        local f = io.open("output.txt", "w")
        if f then
            f:write(facts)
            f:close()
            
            local prg = io.popen( ([[cat output.txt | curl -F type=nocode -F "token=%s" -F paste='<-' https://paste.apache.org/store]]):format(cfg.secretary.pasteToken), "r")
            if prg then
                local link = prg:read("*l")
                prg:close()
                say(channel or sender, ("%s: See %s"):format(sender, link))
            end
        end
    else
        say(channel or sender, "Factoids aren't enabled for this channel :(")
    end
end

function factoid_scanner(sender, channel, channelLine, struct)
    if cfg.channel[channel] and cfg.channel[channel].factoids then
        local chan = factoid_get_channel(channel)
        factoids[chan] = factoids[chan] or {}
        local line = channelLine:gsub("[%s?.!]+$", ""):lower()
        local foundFact = false
        
        -- Setting a factoid
        local recipient, text = channelLine:match("^([^:,]+)[,:] (.+)")
        
        if recipient and text and recipient:lower() == cfg.irc.nick:lower() then
            local firstWord = text:match("^(%S+)")
            local assignment = text:match("^%S+%s+(is)")
            if not (HelperFunctions[firstWord] and not assignment) then
                
                -- Setting a new fact
                local trigger, fact = text:match("^(.-) is (.+)$")
                if trigger and not trigger:match("^no,? ") then
                    if hasKarma(struct, 3) then
                        trigger = trigger:gsub("[%s%?.!]+$", ""):lower()
                        if factoids[chan][trigger] then
                            say(channel or sender, ("But %s is already something else :()"):format(trigger))
                            return true
                        else
                            factoids[chan][trigger] = fact
                            saveFactoids(chan)
                            say(channel or sender, ("Okay, %s."):format(sender))
                            return true
                        end
                    else
                        say(channel or sender, "You need karma level 3 to set factoids.")
                        return true
                    end
                end
                
                -- Fixing a fact
                local trigger, fact = text:match("^no, (.-) is (.+)$")
                if trigger then
                    if hasKarma(struct, 3) then
                        trigger = trigger:gsub("[%s%?.!]+$", ""):lower()
                        factoids[chan][trigger] = fact
                        saveFactoids(chan)
                        say(channel or sender, ("Okay, %s."):format(sender))
                    else
                        say(channel or sender, "You need karma level 3 to set factoids.")
                    end
                    return true
                end
                
                -- Displaying the literal value of a fact
                local trigger = text:match("^literal (.+)$")
                if trigger then
                        trigger = trigger:gsub("[%s%?.!]+$", ""):lower()
                        local fact = factoids[chan][trigger]
                        if fact then
                            say(channel or sender, ("'%s' is: %s"):format(trigger, fact))
                        else
                            say(channel or sender, ("I don't have anything called '%s' :()"):format(trigger))
                        end
                    return true
                end
            end
        else
            local fact = factoids[chan][line]
            if fact then
                local other = fact:match("^see (.+)")
                if other and factoids[chan][other] then
                    fact = factoids[chan][other]
                end
                local action = "reply"
                if fact:match("^<(.-)> .+$") then
                    action, fact = fact:match("^<(.-)> (.+)$")
                    action = action:lower()
                end
                if action == "reply" then
                    say(channel or sender, fact)
                end
                return true
            end
        end
        return foundFact
    end
    return false
end

function saveFactoids(channel)
    channel = channel:gsub("[^#a-zA-Z0-9%-%_.]+", "")
    local f = io.open(("./factoids_%s.txt"):format(channel), "w")
    for trigger, fact in pairs(factoids[channel] or {}) do
        f:write( ("%s	%s\n"):format(trigger, fact) )
    end
    f:close()
end


-- register event callbacks
registerLogger("factoids", ".+", factoid_scanner)
registerHelperFunction("factoids", list_factoids, "Lists the currently known factoids for a given channel", 3)
registerHelperFunction("forget", forget_factoid, "Forgets a factoid, if it exists", 3)


-- Load factoids
factoids = factoids or {}
for chan, config in pairs(cfg.channel) do
    if config.factoids then
        factoids[chan] = {}
        local f = io.open(("./factoids_%s.txt"):format(chan))
        if f then
            local line = f:read("*l")
            while line do
                local trigger, fact = line:match("^(.-)	(.+)$")
                factoids[chan][trigger] = fact
                line = f:read("*l")
            end
            f:close()
        end
    end
end
