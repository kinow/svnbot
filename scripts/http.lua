-- http.lua - implements fetching of documents via HTTP(S)

function GET(url, headers)
    -- If it's just a basic HTTP GET, use the socket.http library
    if not headers and url:match("^http://") then
        local b, c, h = http.request(url)
        return b or ""
    else
        -- Cut URL into scheme, domain, port and URI
        local scheme, domain, uri = url:match("^([a-z]+)://([^/]+)(/.*)$")
        local port = domain:match(":(%d+)$") or (scheme == "http" and 80 or 443)
        domain = domain:match("^([^:]+)")
        
        -- plain HTTP connection
        if scheme == "http" then
            local response_body = {}
            local b, c, h = http.request{
                url = url,
                sink = ltn12.sink.table(response_body),
                headers = headers,
                redirect = false
            }
            return table.concat(response_body, "")
            
        -- HTTPS requests
        elseif scheme == "https" then
            
            local ssl_params = {
                mode = "client",
                protocol = "sslv23",
                verify = "none",
                options = "all",
            }
        
            local ip = socket.dns.toip(domain)
            local try = socket.try
            local protect = socket.protect
            function create()
                local t = {c=socket.tcp()}

                function idx (tbl, key)
                    return function (prxy, ...)
                               local c = prxy.c
                               return c[key](c,...)
                           end
                end


                function t:connect(host, port)
                    self.c:settimeout(15)
                    port = 443 -- XXX: bug-sy malone?
                    local success, err =  self.c:connect(host, port)
                    if err then
                        print(err)
                    end
                    self.c = try(ssl.wrap(self.c,ssl_params))
                    local s = try(self.c:dohandshake())
                    return 1
                end

                return setmetatable(t, {__index = idx})
            end
            local response_body = {}
            local b, c, h = http.request{
                url = url,
                headers = headers,
                sink = ltn12.sink.table(response_body),
                create = create,
                redirect = false
            }
            return table.concat(response_body, "")
        end
    end
end
