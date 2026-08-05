-- ─────────────────────────────────────────────────────────────────────────────
-- dealership-manager · HTTP bridge for jg-dealerships
--
-- Set an API key (optional but recommended) in server.cfg:
--   set dealership_manager_api_key "your-secret-key"
--
-- Endpoint base: http://<server>:<port>/dealership-manager/
-- ─────────────────────────────────────────────────────────────────────────────

local API_KEY = GetConvar('dealership_manager_api_key', '')

local CORS = {
    ['Access-Control-Allow-Origin']  = '*',
    ['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS',
    ['Access-Control-Allow-Headers'] = 'Content-Type, X-API-Key',
    ['Content-Type']                 = 'application/json',
}

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function respond(res, status, data)
    res.writeHead(status, CORS)
    res.send(json.encode(data))
end

local function ok(res, data)
    respond(res, 200, data)
end

local function err(res, status, msg)
    respond(res, status, { error = msg })
end

local function authorized(req)
    if API_KEY == '' then return true end
    local k = req.headers['x-api-key'] or req.headers['X-Api-Key'] or req.headers['X-API-Key']
    return k == API_KEY
end

-- Split "/a/b/c" → {"a","b","c"}
local function parts(path)
    local t = {}
    for seg in path:gmatch('[^/]+') do t[#t + 1] = seg end
    return t
end

local function jg(method, ...)
    return exports['jg-dealerships'][method](exports['jg-dealerships'], ...)
end

-- ── Router ───────────────────────────────────────────────────────────────────

local function route(req, res, body)
    if not authorized(req) then
        return err(res, 401, 'Unauthorized — set X-API-Key header')
    end

    local method = req.method
    local p      = parts(req.path)
    local q      = req.query or {}

    local bodyData = {}
    if body and #body > 0 then
        bodyData = json.decode(body) or {}
    end

    -- ── UI ───────────────────────────────────────────────────────────────────
    -- GET / → serve the management UI
    if #p == 0 and method == 'GET' then
        local html = LoadResourceFile(GetCurrentResourceName(), 'ui/index.html')
        if not html then
            return err(res, 500, 'UI file not found')
        end
        res.writeHead(200, { ['Content-Type'] = 'text/html; charset=utf-8' })
        res.send(html)
        return
    end

    -- GET /health
    if #p == 1 and p[1] == 'health' and method == 'GET' then
        return ok(res, { ok = true, resource = 'dealership-manager', version = '1.0.0' })
    end

    -- ── Dealerships ─────────────────────────────────────────────────────────
    -- GET /dealerships
    if #p == 1 and p[1] == 'dealerships' and method == 'GET' then
        return ok(res, jg('getDealerships') or {})
    end

    -- Routes under /dealerships/{id}/…
    if #p >= 2 and p[1] == 'dealerships' then
        local dealershipId = p[2]

        -- GET /dealerships/{id}
        if #p == 2 and method == 'GET' then
            local d = jg('getDealership', dealershipId)
            if not d then return err(res, 404, 'Dealership not found') end
            return ok(res, d)
        end

        -- GET /dealerships/{id}/balance
        if #p == 3 and p[3] == 'balance' and method == 'GET' then
            local bal, e = jg('getDealershipBalance', dealershipId)
            if bal == false then return err(res, 400, e or 'Failed') end
            return ok(res, { balance = bal })
        end

        -- POST /dealerships/{id}/balance/add   { amount }
        if #p == 4 and p[3] == 'balance' and p[4] == 'add' and method == 'POST' then
            local amount = tonumber(bodyData.amount)
            if not amount then return err(res, 400, 'amount required') end
            local s, e = jg('addDealershipBalance', dealershipId, amount)
            if not s then return err(res, 400, e or 'Failed') end
            return ok(res, { success = true })
        end

        -- POST /dealerships/{id}/balance/remove   { amount }
        if #p == 4 and p[3] == 'balance' and p[4] == 'remove' and method == 'POST' then
            local amount = tonumber(bodyData.amount)
            if not amount then return err(res, 400, 'amount required') end
            local s, e = jg('removeDealershipBalance', dealershipId, amount)
            if not s then return err(res, 400, e or 'Failed') end
            return ok(res, { success = true })
        end

        -- GET /dealerships/{id}/vehicles
        if #p == 3 and p[3] == 'vehicles' and method == 'GET' then
            local v = jg('getShowroomVehicles', dealershipId)
            if v == false then return err(res, 404, 'Dealership not found') end
            return ok(res, v or {})
        end

        -- GET /dealerships/{id}/employees
        if #p == 3 and p[3] == 'employees' and method == 'GET' then
            return ok(res, jg('getEmployees', dealershipId) or {})
        end

        -- GET /dealerships/{id}/sales?limit=50
        if #p == 3 and p[3] == 'sales' and method == 'GET' then
            local limit = math.min(tonumber(q.limit) or 50, 500)
            return ok(res, jg('getSalesHistory', dealershipId, limit) or {})
        end

        -- GET /dealerships/{id}/total-sales
        if #p == 3 and p[3] == 'total-sales' and method == 'GET' then
            return ok(res, { total = jg('getTotalSales', dealershipId) or 0 })
        end

        -- POST /dealerships/{id}/coupons   { discount_type, discount_value, … }
        if #p == 3 and p[3] == 'coupons' and method == 'POST' then
            local coupon, e = jg('createCoupon', dealershipId, bodyData)
            if not coupon then return err(res, 400, e or 'Failed') end
            return ok(res, coupon)
        end

        -- GET /dealerships/{id}/coupons/validate?code=&spawnCode=&category=&isFinanced=
        if #p == 4 and p[3] == 'coupons' and p[4] == 'validate' and method == 'GET' then
            if not q.code then return err(res, 400, 'code required') end
            local valid, msg, discount, dtype, dvalue = jg(
                'validateCoupon',
                q.code, dealershipId,
                q.spawnCode or nil,
                q.category  or nil,
                q.isFinanced == 'true'
            )
            return ok(res, {
                valid          = valid,
                message        = msg,
                discount       = discount,
                discount_type  = dtype,
                discount_value = dvalue,
            })
        end

        -- Stock routes /dealerships/{id}/stock/{spawnCode}/…
        if #p >= 4 and p[3] == 'stock' then
            local spawnCode = p[4]

            -- GET /dealerships/{id}/stock/{spawnCode}
            if #p == 4 and method == 'GET' then
                local stock, e = jg('getVehicleStock', spawnCode, dealershipId)
                if stock == false then return err(res, 400, e or 'Failed') end
                return ok(res, { stock = stock })
            end

            -- POST /dealerships/{id}/stock/{spawnCode}/increment   { amount? }
            if #p == 5 and p[5] == 'increment' and method == 'POST' then
                local s, e = jg('incrementStock', dealershipId, spawnCode, tonumber(bodyData.amount))
                if not s then return err(res, 400, e or 'Failed') end
                return ok(res, { success = true })
            end

            -- POST /dealerships/{id}/stock/{spawnCode}/decrement   { amount? }
            if #p == 5 and p[5] == 'decrement' and method == 'POST' then
                local s, e = jg('decrementStock', dealershipId, spawnCode, tonumber(bodyData.amount))
                if not s then return err(res, 400, e or 'Failed') end
                return ok(res, { success = true })
            end

            -- POST /dealerships/{id}/stock/{spawnCode}/set   { stock }
            if #p == 5 and p[5] == 'set' and method == 'POST' then
                local stock = tonumber(bodyData.stock)
                if stock == nil then return err(res, 400, 'stock required') end
                local s, e = jg('setStock', dealershipId, spawnCode, stock)
                if not s then return err(res, 400, e or 'Failed') end
                return ok(res, { success = true })
            end
        end

        -- GET /dealerships/{id}/price/{spawnCode}
        if #p == 4 and p[3] == 'price' and method == 'GET' then
            local price, e = jg('getVehiclePrice', p[4], dealershipId)
            if price == false then return err(res, 400, e or 'Failed') end
            return ok(res, { price = price })
        end
    end

    -- ── Base catalog price ───────────────────────────────────────────────────
    -- GET /price/{spawnCode}
    if #p == 2 and p[1] == 'price' and method == 'GET' then
        local price, e = jg('getVehiclePrice', p[2])
        if price == false then return err(res, 400, e or 'Failed') end
        return ok(res, { price = price })
    end

    -- ── Finance ──────────────────────────────────────────────────────────────
    if #p >= 2 and p[1] == 'finance' then

        -- GET /finance/plate/{plate}
        if #p == 3 and p[2] == 'plate' and method == 'GET' then
            local v = jg('getFinanceByPlate', p[3])
            if not v then return err(res, 404, 'Not found or not financed') end
            return ok(res, v)
        end

        -- POST /finance/payment   { src, plate }
        if #p == 2 and p[2] == 'payment' and method == 'POST' then
            local src   = tonumber(bodyData.src)
            local plate = bodyData.plate
            if not src or not plate then return err(res, 400, 'src and plate required') end
            local s, e = jg('makeFinancePayment', src, plate)
            if not s then return err(res, 400, e or 'Failed') end
            return ok(res, { success = true })
        end

        -- GET /finance/{identifier}/count
        if #p == 3 and p[3] == 'count' and method == 'GET' then
            return ok(res, { count = jg('getPlayerFinanceCount', p[2]) or 0 })
        end

        -- GET /finance/{identifier}
        if #p == 2 and method == 'GET' then
            return ok(res, jg('getPlayerFinancedVehicles', p[2]) or {})
        end
    end

    -- ── Catch-all ────────────────────────────────────────────────────────────
    return err(res, 404, 'Route not found: ' .. method .. ' ' .. req.path)
end

-- ── HTTP handler ─────────────────────────────────────────────────────────────

SetHttpHandler(function(req, res)
    -- OPTIONS preflight (CORS)
    if req.method == 'OPTIONS' then
        req.setDataHandler(function()
            res.writeHead(200, CORS)
            res.send('{}')
        end)
        return
    end

    req.setDataHandler(function(body)
        CreateThread(function()
            local success, routeErr = pcall(route, req, res, body)
            if not success then
                res.writeHead(500, CORS)
                res.send(json.encode({ error = 'Internal server error', detail = tostring(routeErr) }))
            end
        end)
    end)
end)

if API_KEY == '' then
    print('^3[dealership-manager]^0 Warning: no API key set. Add ^5set dealership_manager_api_key "secret"^0 to server.cfg')
end

-- Fetch public IP then print the access URL
PerformHttpRequest('https://api.ipify.org', function(status, body)
    local ip = (status == 200 and body and body:match('[%d%.]+')) or '<server-ip>'
    local port = GetConvar('sv_httpPort', GetConvar('netPort', '30120'))
    print('^2[dealership-manager]^0 UI ready → ^5http://' .. ip .. ':' .. port .. '/dealership-manager/^0')
end, 'GET', '', { ['Accept'] = 'text/plain' })
