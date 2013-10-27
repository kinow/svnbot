-- logger.lua - channel logging features

function logger_pointer(sender, channel, params)
    if not channel then return end
    if cfg.channel[channel] and cfg.channel[channel].log then
        local now = os.time()
        local filename = ("%s-%s"):format(channel, os.date("%Y_%m_%d", os.time())):gsub("#", "")
        say(s, channel or sender, sender.name .. ": http://wilderness.apache.org/channels/?f=" .. filename .. "#" .. now)
    end
end

function writeToLog(channel, message)
    local filename = ("%s/%s-%s.log"):format(cfg.secretary.logFolder, channel, os.date("%Y_%m_%d", os.time()))
    local f = io.open(filename, "a")
    if f then
        f:write(message)
        f:close()
    end
end

function logger_log_messages(sender, channel, channelLine)
    if cfg.channel[channel] and cfg.channel[channel].log and not channelLine:match("^%[off%]") then
        writeToLog(channel, ("%s MSG %s %s\r\n"):format(os.time(), sender, channelLine))
    end
end

function logger_log_join(sender, ident, channel)
    if cfg.channel[channel] and cfg.channel[channel].log then
        writeToLog(channel, ("%s JOIN %s %s\r\n"):format(os.time(), sender, channel))
    end
end

function logger_log_part(sender, ident, channel)
    if cfg.channel[channel] and cfg.channel[channel].log then
        writeToLog(channel, ("%s PART %s %s\r\n"):format(os.time(), sender, channel))
    end
end

function logger_log_topic(sender, ident, channel, topic)
    if cfg.channel[channel] and cfg.channel[channel].log then
        writeToLog(channel, ("%s TOPIC %s %s\r\n"):format(os.time(), sender, topic))
    end
end

function logger_log_notice(sender, ident, channel, topic)
    if cfg.channel[channel] and cfg.channel[channel].log then
        writeToLog(channel, ("%s NOTICE %s %s\r\n"):format(os.time(), sender, topic))
    end
end

function logger_log_mode(sender, ident, channel, mode)
    if cfg.channel[channel] and cfg.channel[channel].log then
        writeToLog(channel, ("%s MODE %s %s\r\n"):format(os.time(), sender, mode))
    end
end

function logger_log_nick(sender, ident, channel, nick)
    if cfg.channel[channel] and cfg.channel[channel].log then
        writeToLog(channel, ("%s NICK %s %s\r\n"):format(os.time(), sender, nick))
    end
end

-- register event callbacks
registerLogger("logger", ".+", logger_log_messages)
registerEvent("logger_join", "JOIN", logger_log_join)
registerEvent("logger_part", "PART", logger_log_part)
registerEvent("logger_topic", "TOPIC", logger_log_topic)
registerEvent("logger_notice", "NOTICE", logger_log_notice)
registerEvent("logger_mode", "MODE", logger_log_mode)
registerEvent("logger_nick", "NICK", logger_log_nick)

