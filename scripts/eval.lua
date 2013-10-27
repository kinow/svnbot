
local e=_ENV

function debughook(event, line)
    local now = os.time()
    if now - when > 3 then
        coroutine.yield()
    end
end

function catch(err)
    return "Script timed out"
end

sandbox_env = {
  ipairs = ipairs,
  next = next,
  pairs = pairs,
  pcall = pcall,
  tonumber = tonumber,
  tostring = tostring,
  type = type,
  unpack = unpack,
  coroutine = { create = coroutine.create, resume = coroutine.resume, 
      running = coroutine.running, status = coroutine.status, 
      wrap = coroutine.wrap },
  string = { byte = string.byte, char = string.char, find = string.find, 
      format = string.format, gmatch = string.gmatch, gsub = string.gsub, 
      len = string.len, lower = string.lower, match = string.match, 
      rep = string.rep, reverse = string.reverse, sub = string.sub, 
      upper = string.upper },
  table = { insert = table.insert, maxn = table.maxn, remove = table.remove, 
      sort = table.sort },
  math = { abs = math.abs, acos = math.acos, asin = math.asin, 
      atan = math.atan, atan2 = math.atan2, ceil = math.ceil, cos = math.cos, 
      cosh = math.cosh, deg = math.deg, exp = math.exp, floor = math.floor, 
      fmod = math.fmod, frexp = math.frexp, huge = math.huge, 
      ldexp = math.ldexp, log = math.log, log10 = math.log10, max = math.max, 
      min = math.min, modf = math.modf, pi = math.pi, pow = math.pow, 
      rad = math.rad, random = math.random, sin = math.sin, sinh = math.sinh, 
      sqrt = math.sqrt, tan = math.tan, tanh = math.tanh },
  os = { date = os.date, clock = os.clock, difftime = os.difftime, time = os.time },
  d = function() debug.sethook(debughook, 'l') end
}

when = os.time()


function eval(sender, channel, params)
    local sb_orig_env=_G
    local ls = loadstring
    if not params then return nil end
    when = os.time()
    setfenv(0, sandbox_env)
    local func, err = ls([[d() return ]] .. params )
    if err then
        sb_orig_env.setfenv(0, sb_orig_env)
        debug.sethook()
        say(channel or sender, "<b>Error in eval:</b> " .. err)
        return
    end
    local okay, rv = xpcall(coroutine.wrap(func), catch)
    sb_orig_env.setfenv(0, sb_orig_env)
    debug.sethook()
    if not okay then
        say(channel or sender, "<b>Error in eval:</b> " .. rv)
    else
        rv = tostring(rv)
        for line in rv:gmatch("([^\r\n]+)") do
            say(channel or sender, sender .. ": " .. line)
        end
    end
end

registerHelperFunction("eval", eval, "Evaluates lua code and returns the output", 8)