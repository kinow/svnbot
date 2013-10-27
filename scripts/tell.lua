-- tell.lua - implements the 'tell' feature.
awayMessages = awayMessages or {}

-- howLong(): turn a timediff into days, hours and minutes
function howLong(when)
    local now = os.time()
    local diff = now - when
    local days = math.floor(diff / 86400)
    local hours = math.floor((diff % 86400) / 3600)
    local minutes = math.floor((diff % 3600) / 60)
    local output = string.format("%d minute%s", minutes, minutes ~= 1 and "s" or "")
    if diff >= 86400 then
        output = string.format("%d day%s, %d hour%s and %d minute%s", days, days ~= 1 and "s" or "",hours, hours ~= 1 and "s" or "", minutes, minutes ~= 1 and "s" or "")
    elseif diff >= 3600 then
        output = string.format("%d hour%s and %d minute%s", hours, hours ~= 1 and "s" or "", minutes, minutes ~= 1 and "s" or "")
    end
    return output
end

-- event callback for people joining a channel
function secretary_check_joins(who, ident, channel)
    if who and channel then
        local whol = who:lower()
        for k, item in pairs(awayMessages) do
            if item.channel == channel and item.recipient == whol then
                say(channel, ("%s: %s ago, %s said; %s"):format(who, howLong(item.timestamp), item.sender, item.message))
                awayMessages[k] = nil
            end
        end
    end
end

-- event callback for people speaking
function secretary_check_messages(sender, channel, channelLine)
    if sender and channel then
        local whol = sender:lower()
        for k, item in pairs(awayMessages) do
            if item.channel == channel and item.recipient == whol then
                say(channel, ("%s: %s ago, %s said; %s"):format(sender, howLong(item.timestamp), item.sender, item.message))
                awayMessages[k] = nil
            end
        end
    end
end

-- The tell feature
function secretary_tell(sender, channel, params)
    local recipient, message = params:match("(%S+) (.+)$")
    if recipient and message and channel then
        say(channel or sender, "I'll pass that along, " .. sender .. "!")
        table.insert(awayMessages, { sender = sender, recipient = recipient:lower(), timestamp = os.time(), message = message, channel = channel })
    else
        say(channel or sender, "Bad parameters. Usage: tell [recipient] [message]")
    end
end


-- Register 'tell' as a function
registerHelperFunction("tell", secretary_tell, "tell [recipient] [message] - Tell someone something when they log on or speak up.", 0)

-- Register loggers and event callbacks
registerLogger("tell_logger", ".+", secretary_check_messages)
registerEvent("tell_joins", "JOIN", secretary_check_joins)
