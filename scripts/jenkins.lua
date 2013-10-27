-- jenkins.lua - Jenkins monitoring
local jenkins = {}

-- formatDuration(): format a timespan into a human readable string
function formatDuration (diff)
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

-- Timed callback that fetches JSON and announces any builder changes
function jenkins_update(s)
    local now = os.time()
    local changes = {}
    local json_global = {}
    for channel, settings in pairs(cfg.channel) do
        if settings.jenkins_url and settings.jenkins_match and not json_global[settings.jenkins_url] then
            -- native call, no need to check validity
            local data = GET(("%sapi/json?depth=1"):format(settings.jenkins_url))
            if data and data:len() > 0 then
                local okay, json = pcall(function() return JSON:decode(data) end)
                if okay and json then
                    json.url = settings.jenkins_url
                    json_global[settings.jenkins_url] = json
                end
            end
        end
    end
    for k, json in pairs(json_global) do
        if json.url:match("/job/") then
            for k, build in pairs(json.builds) do
                name = json.displayName .. "/" .. build.number
                if not jenkins[name] then
                    jenkins[name] = { status = false, lastUpdate = now, duration = 0, description = "Idle", prev = "Idle", culprits = "" }          
                end
                local pct = "(unknown timespan)"
                if build.estimatedDuration and build.estimatedDuration > 0 and build.estimatedDuration > build.duration then
                    pct = formatDuration((build.estimatedDuration - build.duration)/1000)
                end
                if jenkins[name].status ~= build.building then
                    if build.building then
                        jenkins[name].description = ("#%s started building, estimated %s left. %s"):format(build.number, formatDuration(build.estimatedDuration/1000), build.url)
                        if build.changeSet and build.changeSet.items then
                            for k, item in pairs(build.changeSet.items) do
                                if item.msg and item.author and item.author.fullName then
                                    item.msg = item.msg:gsub("%[#", "[") -- allura workaround for now
                                    jenkins[name].description = jenkins[name].description .. ("\n<b>%s:</b> %s"):format(item.author.fullName, item.msg)
                                elseif item.msg then
                                    jenkins[name].description = jenkins[name].description .. ("\n%s"):format(item.msg)
                                end
                            end
                        end
                    else
                        local what = "built successfully"
                        local status = ""
                        if (build.result or "SUCCESS") == "ABORTED" then
                            what = "ABORTED"
                        end
                        if (build.result or "SUCCESS") == "FAILURE" then
                            what = "FAILED"
                            if build.culprits then
                                local culprits = {}
                                for k, v in pairs(build.culprits or {}) do
                                    table.insert(culprits, v.fullName or v.id)
                                end
                                local blamelist = table.concat(culprits, ", ")
                                status = (", blame list: %s"):format(blamelist)
                            end
                        end
                        build.duration = build.duration or 0
                        jenkins[name].description = ("#%s %s after %s%s %s"):format(build.number, what, formatDuration(build.duration/1000), status, build.url or "")
                    end
                    jenkins[name].status = build.building
                    jenkins[name].lastUpdate = now
                end
            end
        else
            for k, job in pairs(json.jobs) do
                local name = job.name
                if not jenkins[name] then
                    jenkins[name] = { status = job.color, lastUpdate = now, duration = 0, description = "Idle", prev = "Idle", culprits = "" }
                else
                    if jenkins[name].status ~= job.color then
                        jenkins[name].status = job.color
                        jenkins[name].duration = now - jenkins[name].lastUpdate
                        jenkins[name].lastUpdate = now
                        local blamelist = ""
                        local culprits = {}
                        if job.lastBuild and job.lastBuild.culprits then
                            for k, v in pairs(job.lastBuild.culprits or {}) do
                                table.insert(culprits, v.fullName or v.id)
                            end
                        end
                        if #culprits > 0 then
                            blamelist = "Blamelist: " .. table.concat(culprits, ", ")
                        end
                        local tmpprev = jenkins[name].description:match("^([^.]+)")
                        if job.color:match("anime") then
                            jenkins[name].description = "Started building. " .. (jenkins[name].prev ~= "Idle" and ("Previously: " .. tmpprev) or "")
                        elseif job.color:match("abort") then
                            jenkins[name].description = ("Aborted after %d min, %d sec. %s. %s"):format(jenkins[name].duration/60, jenkins[name].duration%60, job.lastBuild.url, blamelist)
                        elseif job.color:match("blue") then
                            jenkins[name].description = ("Built successfully after %d min, %d sec. %s"):format(jenkins[name].duration/60, jenkins[name].duration%60, job.lastBuild.url)
                        elseif job.color:match("red") then
                            jenkins[name].description = ("Failed after %d min, %d sec. %s. %s"):format(jenkins[name].duration/60, jenkins[name].duration%60, job.lastBuild.url, blamelist)
                        end
                    end
                end
            end
        end
    end
    for channel, settings in pairs(cfg.channel) do
        if settings.jenkins_match then
            for name, entry in pairs(jenkins) do
                if entry.lastUpdate == now and name:match(settings.jenkins_match) and not (entry.description == "Idle") then
                    say(channel, ("%s: %s"):format(name, entry.description) )
                end        
            end
        end
    end
end


function jenkins_status( sender, channel, params)
    local data = "{}"
    local matches = {".+"}
    if params ~= "" then
        matches = {}
        for match in params:gmatch("(%S+)") do
            table.insert(matches, match)
        end
    end
    local url = cfg.channel[channel].jenkins_url
    if url then
        -- native call (although we still validate the URL if set via IRC)
        data = GET(("%sapi/json?depth=1"):format(url))
    else
        say(channel or sender, "No Jenkins URL configured for this channel")
        return
    end
    local okay, json = pcall(function() return JSON:decode(data) end)
    if okay and json then
        if url:match("/job/") then
            local build = json.builds[1]
            if not build.building then
                say(channel or sender, "No jobs are currently building.")
                local what = "built successfully"
                local status = ""
                if build.result == "FAILURE" then
                    what = "FAILED"
                    if build.culprits then
                        local culprits = {}
                        for k, v in pairs(build.culprits or {}) do
                            table.insert(culprits, v.fullName or v.id)
                        end
                        local blamelist = table.concat(build.culprits, ", ")
                        status = (", blame list: %s"):format(blamelist)
                    end
                end
                local details = ("Last build: #%s %s after %s%s. %s"):format(build.number, what, formatDuration(build.duration/1000), status, build.url)
                say(channel or sender, details)
                if build.changeSet and build.changeSet.items then
                    for k, item in pairs(build.changeSet.items) do
                        if item.msg and item.author and item.author.fullName then
                            item.msg = item.msg:gsub("%[#", "[") -- allura workaround for now
                            say(channel or sender, ("\n<b>%s:</b> %s"):format(item.author.fullName, item.msg))
                        elseif item.msg then
                            say(channel or sender, ("\n%s"):format(item.msg))
                        end
                    end
                end
            else
                local pct = "(unknown timespan)"
                if build.estimatedDuration and build.estimatedDuration > 0 and build.estimatedDuration > build.duration then
                    pct = formatDuration((build.estimatedDuration - build.duration)/1000)
                end
                say(channel or sender, ("Currently building, started %s ago, estimated %s left."):format(formatDuration(build.duration/1000), pct))
            end
            return
        else
            for k, job in pairs(json.jobs) do
                local status = ""
                local blamelist = ""
                local culprits = {}
                if job.lastBuild and job.lastBuild.culprits then
                    for k, v in pairs(job.lastBuild.culprits or {}) do
                        table.insert(culprits, v.fullName or v.id)
                    end
                end
                if #culprits > 0 then
                --    blamelist = "Possible culprit(s): " .. table.concat(culprits, ", ")
                end
                local url = ""
                if job.lastBuild and job.lastBuild.url then
                    url = job.lastBuild.url
                end
                if job.color:match("blue") then status = "Last build successful. " end
                if job.color:match("red") then status = "Last build failed. " .. blamelist end
                if job.color:match("aborted") then status = "Last build was aborted. " .. blamelist end
                if job.color:match("anime") then status = "Building, " .. status end
                local match = 0
                for k, v in pairs(matches) do
                    if job.name:match(v) or job.color:match(v) or status:match(v) then
                        match = match + 1
                    end
                end
                if match == #matches then
                    say(channel or sender, ("%s: %s - %s"):format(job.name, status, url) )
                end
            end
        end
    else
        say(channel or sender, ("Invalid JSON received from %sapi/json"):format(url))
    end
end


function jenkins_count(sender, channel, params)
    local data = "{}"
    local matches = {"none"}
    local where = params
    if where and where == "all" then
        matches = {".+"}
    elseif where then
        matches = {}
        for word in where:gmatch("(%S+)") do
            table.insert(matches, word)
        end
    end
    local url = cfg.channel[channel].jenkins_url
    if url then
        -- same as earlier, native call, validated if set via IRC
        data = GET(("%sapi/json?depth=1"):format(url))
    else
        say(channel or sender, "No Jenkins URL configured for this channel")
        return
    end
    local count = 0
    local okay, json = pcall(function() return JSON:decode(data) end)
    if okay and json then
        for k, job in pairs(json.jobs) do
            local status = ""
            local blamelist = ""
            local culprits = {}
            if job.lastBuild and job.lastBuild.culprits then
                for k, v in pairs(job.lastBuild.culprits or {}) do
                    table.insert(culprits, v.fullName or v.id)
                end
            end
            if #culprits > 0 then
                blamelist = "Possible culprit(s): " .. table.concat(culprits, ", ")
            end
            if job.color:match("blue") then status = "Last build successful. " end
            if job.color:match("red") then status = "Last build failed. " .. blamelist end
            if job.color:match("aborted") then status = "Last build was aborted. " .. blamelist end
            if job.color:match("anime") then status = "Building, " .. status end
            local match = 0
            for k, v in pairs(matches) do
                if job.name:match(v) or status:match(v) then
                    match = match + 1
                end
            end
            if match == #matches then
                count = count + 1 
            end
        end
        say(channel or sender, tostring(count))
    else
        say(channel or sender, ("Invalid JSON received from %sapi/json"):format(url))
    end
end


-- Register functions
registerHelperFunction("jstatus", jenkins_status, "jstatus [pattern] - Displays the current status of builds matching [pattern], e.g. 'jstatus openwebbeans x64'", 2)
registerHelperFunction("jcount", jenkins_count, "jcount [pattern] - Counts the builds matching [pattern], for instance: jcount marmotta failed", 2)
registerTimedCallback("jenkins_status", jenkins_update, 15, false)

