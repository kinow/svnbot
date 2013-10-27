-- bugzilla.lua - bugzilla ticket helper

htmlCodes = {
    quot = '"',
    lt = '<',
    gt = '>',
    amp = '&',
    apos = "'"
}

function bugzilla_ticket(sender, channel, params)
    -- Are bugzilla hints enabled?
    if sender and channel and cfg.channel[channel].bugzilla then
        -- parse ticket no.
        local ticket = params:match("(%d+)")
        if ticket then
            -- fetch xml
            local body = GET(("%sxml.cgi?id=%s"):format(cfg.channel[channel].bugzilla, ticket))
            local title = body:match("<short_desc>(.-)</short_desc>")
            if not title then -- if xml.cgi didn't work, let's try show_bug.cgi with a ctype
                local body = GET(("%sshow_bug.cgi?ctype=xml&id=%s"):format(cfg.channel[channel].bugzilla, ticket))
                title = body:match("<short_desc>(.-)</short_desc>")
            end
            title = (title or "(no title)"):gsub("&([a-z]+);", function(a) return htmlCodes[a] or "?" end)
            ticket = cfg.channel[channel].bugzilla .. "show_bug.cgi?id=" .. ticket
            say(channel or sender, ("%s: %s - %s"):format(sender, ticket, title or "??"))
        end
    end
end

-- register 'issue' as a logger function
registerLogger("bugzilla_logger", "^issue ", bugzilla_ticket)
