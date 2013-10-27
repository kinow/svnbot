-- beertab.lua - beer tabs!
owed = {}

-- owe_stuff(): the 'owe' feauture.
function owe_stuff(sender, channel, params)
    local recipient, number, what = params:match("(%S+)%s+(%d+)%s+(.+)")
    if not recipient or not number or not what then
        say(channel or sender, "Invalid syntax - please use: owe [recipient] [number] [item], fx: owe Humbedooh 1 beer")
        return
    end
    number = tonumber(number) or 1
    recipient = recipient:lower()
    local lsender = sender:lower()
    owed[recipient] = owed[recipient] or {}
    owed[recipient][lsender] = owed[recipient][lsender] or {}
    owed[recipient][lsender][what] = (owed[recipient][lsender][what] or 0) + number
    local howmany = owed[recipient][lsender][what] 
    say(channel or sender, ("%s now owes %s %d %s%s"):format(sender, recipient, howmany, what, howmany ~= 1 and "s" or ""))
    
    local f = io.open("tab.txt", "w")
    if f then
        for recipient, entry in pairs(owed) do
            for sender, entry in pairs(entry) do
                for what, howmany in pairs(entry) do
                    f:write( ("%s %s %d %s\n"):format(recipient, sender, howmany, what) )
                end
            end
        end
        f:close()
    end
end

-- pay_stuff(): paying back stuff
function pay_stuff(sender, channel, params)
    local recipient, number, what = params:match("(%S+)%s+(%d+)%s+(.+)")
    if not recipient or not number or not what then
        say(channel or sender, "Invalid syntax - please use: paid [recipient] [number] [item], fx: paid Humbedooh 1 beer")
        return
    end
    number = tonumber(number) or 1
    recipient = recipient:lower()
    local lsender = sender:lower()
    owed[recipient] = owed[recipient] or {}
    owed[recipient][lsender] = owed[recipient][lsender] or {}
    owed[recipient][lsender][what] = (owed[recipient][lsender][what] or 0) - number
    if owed[recipient][lsender][what] < 0 then
        owed[recipient][lsender][what] = 0
    end
    local howmany = owed[recipient][lsender][what] 
    say(channel or sender, ("%s now owes %s %d %s%s"):format(sender, recipient, howmany, what, howmany ~= 1 and "s" or ""))
    
    local f = io.open("tab.txt", "w")
    if f then
        for recipient, entry in pairs(owed) do
            for sender, entry in pairs(entry) do
                for what, howmany in pairs(entry) do
                    f:write( ("%s %s %d %s\n"):format(recipient, sender, howmany, what) )
                end
            end
        end
        f:close()
    end
end

-- Displaying the tab
function tab(sender, channel, params)
    local list = {}
    local lsender = sender:lower()
    if params ~= "" then
        lsender = params:lower()
    end
    for osender, entry in pairs(owed[lsender] or {}) do
        for what, howmany in pairs(entry) do
            if howmany > 0 then
                table.insert(list, ("%s owes %s %d %s%s"):format(osender, lsender, howmany, what, howmany ~= 1 and "s" or ""))
            end
        end
    end
    for recipient, entry in pairs(owed) do
        for sender, entry in pairs(entry) do
            if sender == lsender then
                for what, howmany in pairs(entry) do
                    if howmany > 0 then
                        table.insert(list, ("%s owes %s %d %s%s"):format(lsender, recipient, howmany, what, howmany ~= 1 and "s" or ""))
                    end
                end
            end
        end
    end
    if #list == 0 then
        say(channel or sender, ("%s does not owe or is owed anything"):format(lsender) )
    else
        if #list > 5 then
            local output = table.concat(list, "\n")
            local f = io.open("output.txt", "w")
            if f then
                f:write(output)
                f:close()
                -- Shouldn't be any security concerns here, curl reads from a file and posts to a hardcoded URL
                local prg = io.popen( ([[cat output.txt | curl -F type=nocode -F "token=%s" -F paste='<-' https://paste.apache.org/store]]):format(cfg.secretary.pasteToken), "r")
                if prg then
                    local link = prg:read("*l")
                    prg:close()
                    say(channel or sender, ("%s: See %s"):format(sender, link))
                end
            end
        else
            for k, item in pairs(list) do
                say(channel or sender, item)
            end
        end
    end
end

-- Register owe, paid and tab as functions
registerHelperFunction("owe", owe_stuff, "owe [recipient] [amount] [item] - Owe someone something, fx. 'owe Humbedooh 1 beer'", 0)
registerHelperFunction("paid", pay_stuff, "paid [recipient] [amount] [item] - Pay someone something, fx. 'paid Humbedooh 1 beer'", 0)
registerHelperFunction("tab", tab, "tab [user] - Show your own or [user]'s current tab", 0)

-- Open up the stored beer tab and load it into memory
-- This is run when the plugin is reloaded or ASFBot is started.
local f = io.open("tab.txt")
if f then
    while true do
        local line = f:read("*l")
        if not line then break end
        local recipient, sender, howmany, what = line:match("^(%S+) (%S+) (%d+) (.-)$")
        if what then
            owed[recipient] = owed[recipient] or {}
            owed[recipient][sender] = owed[recipient][sender] or {}
            owed[recipient][sender][what] = (owed[recipient][sender][what] or 0) + tonumber(howmany)
        end
    end
    f:close()
end
