-- This is the help plugin for ASFBot. It displays a help page.

function help(sender, channel, params)
    params = params:lower()
    if params == "" then
        local funcs = {}
        for k, v in pairs(HelperFunctions) do
            table.insert(funcs, k)
        end
        table.sort(funcs)
        local functions = table.concat(funcs, ", ")
        say(channel or sender, "Available commands: " .. functions)
        say(channel or sender, "Type help [command] to get detailed information about a command")
        say(channel or sender, "Visit http://wilderness.apache.org/ for more detailed instructions")
    else
        if HelperFunctions[params] then
            say(channel or sender, "Usage: " .. HelperFunctions[params].description)
        else
            say(channel or sender, "No such helper function")
        end
    end
end

function version(sender, channel, params)
    collectgarbage()
    local count = collectgarbage("count")
    say(channel or sender, ("This is ASFBot/2.0 - utilizing COMPUTRON vector optimizations for that extra spiffiness, using %dkb memory"):format(count))
    say(channel or sender, "Source code available at: https://svn.apache.org/repos/infra/infrastructure/trunk/projects/svnbot/")
end

function ping(sender, channel, params)
    say(channel or sender, sender .. ": pong!")
end

registerHelperFunction("help", help, "help [command] - Displays useful information about a function", 0)
registerHelperFunction("version", version, "version - displays the ASFBot version, d'uh", 0)
registerHelperFunction("ping", ping, "ping - you say ping, I say pong...", 0)
