local config = {}

function split(txt, delim)
    local tbl = {}
    for k in txt:gmatch("([^"..delim.."]+)" .. delim) do
        table.insert(tbl, k)
    end
    return tbl
end

function config.read(file)
    local f = io.open(file)
    local cfg = {}
    if f then
        local name, key, value, pobj
        while true do
            local line = f:read("*l")
            if not line then break end
            if not line:match("^%s*#") then
                local n = line:match("^%[(%S+)%]")
                if n then
                    name = n
                    local o = cfg
                    for child in n:lower():gmatch("([^:]+)") do
                        o[child] = o[child] or {}
                        o = o[child]
                    end
                    pobj = o
                else
                    local k, v = line:match("%s*(%S+):%s+([^#]*)")
                    if k and v then
                        if v:sub(#v,#v) == [[\]] then
                            v = v:sub(1,#v-1)
                            while true do
                                local line = f:read("*l")
                                if not line then break end
                                local b = (line:sub(#line, #line) ~= [[\]])
                                v = v .. (b and line or line:sub(1,#line-1))
                                if b then break end
                            end
                        end
                        v = v:gsub("\\n", "\n")
                        local fname = v:match("read%('([^']+)'%)")
                        if fname then
                            local i = io.open(fname)
                            if i then
                                v = i:read("*a")
                                i:close()
                            end
                        end
                        if v:match("^%d+$") then
                            v = tonumber(v)
                        else
                            if v == "true" then v = true elseif v == "false" then v = false end
                        end
                        pobj[k] = type(v) == "string" and v:gsub("%s+$", "") or v
                    end
                end
            end
        end
        f:close()
        return cfg
    else
        return nil
    end
end

function config.fix(cfg)
    if arg and arg[1] and arg[1] == "debug" then
        cfg.misc.debug = true
    end
    cfg.pubsub.repositories = split(cfg.pubsub.repositories, "%s*")
    for k, channel in pairs(cfg.channel) do
        if channel.tags then
            channel.tags = split(channel.tags, "%s*")
        end
        if channel.hook then
            channel.hook = loadstring("return " .. channel.hook)()
        end
    end
    for k, ident in pairs(cfg.karma) do
        local ident, level = ident:match("(%S+)%s+(%d+)")
        cfg.karma[k] = { id = ident, level = tonumber(level) }
    end
    if cfg.misc.debug then
        cfg.irc.nick = "ASFBotDebug"
        cfg.channel = { ['#asfbot'] = { tags = {".+"} } }
    end
end

return config
