-- subversion.lua - Subversion revision hints
function subversion_revision(sender, channel, params)
    if sender and channel and cfg.channel[channel].revisionHints then
        print("looking up revision... " .. params)
        local revision = params:match("(%d+)")
        local repo = cfg.channel[channel].svnRepo or cfg.reporting.svnRepo or ""
        -- The repo cannot be set to a non-URL value using IRC, but still, whitelist the chars.
        -- This should prevent a bad asfbot.cfg file from inflicting damage.
        repo = repo:gsub("[^a-zA-Z0-9:/._%-%%+]+", "")
        if revision then
            local f = io.popen(([[svn log -r %s "%s"]]):format(revision, repo))
            local a = 0
            if f then
                while true do
                    local line = f:read("*l")
                    if not line then break end
                    if not line:match("%-%-%-") and not line:match("^%s*$") then
                        a = a + 1
                        if a > 4 then                                                        
                            say(channel or sender, sender .. ": >> ...")
                            break
                        end
                        say(channel or sender, sender .. ": >> " .. line)
                    end
                end
                f:close()
                say(channel or sender, sender .. ": http://svn.apache.org/r" .. revision)
            else
                say(channel or sender, "Could not connect to svn :(")
            end
        end
    end
end

-- Register r12345 in the logger
registerLogger("subversion_hints", "^r%d+$", subversion_revision)
