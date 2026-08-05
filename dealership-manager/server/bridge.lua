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
    local args = { ... }
    local ok, result = pcall(function()
        return exports['jg-dealerships'][method](exports['jg-dealerships'], table.unpack(args))
    end)
    if not ok then
        error('jg-dealerships export "' .. method .. '" failed: ' .. tostring(result), 2)
    end
    return result
end

-- ── Vehicle name map (persisted to vehicle_names.json) ───────────────────────

local VNAMES_FILE = 'vehicle_names.json'
local vehicleNames = {}

local raw = LoadResourceFile(GetCurrentResourceName(), VNAMES_FILE)
if raw then vehicleNames = json.decode(raw) or {} end

local function saveVehicleNames()
    SaveResourceFile(GetCurrentResourceName(), VNAMES_FILE, json.encode(vehicleNames), -1)
end

-- ── Player name cache (populated via QBCore events) ──────────────────────────

local playerNames = {}

local function cacheQBPlayer(Player)
    pcall(function()
        local id = Player.PlayerData.citizenid
        local ci = Player.PlayerData.charinfo
        if id and ci then
            playerNames[id] = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):match('^%s*(.-)%s*$')
        end
    end)
end

AddEventHandler('QBCore:Server:PlayerLoaded', cacheQBPlayer)

AddEventHandler('playerDropped', function()
    pcall(function()
        local QBCore = exports['qb-core']:GetCoreObject()
        cacheQBPlayer(QBCore.Functions.GetPlayer(source))
    end)
end)

local function dbLookupPlayerName(identifier)
    -- Try oxmysql first (standard on qbox/QBCore)
    local ok1, rows = pcall(function()
        return exports.oxmysql:executeSync(
            'SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1',
            { identifier }
        )
    end)
    if not ok1 or not rows then
        -- Fall back to mysql-async style
        ok1, rows = pcall(function()
            return MySQL.query.await(
                'SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1',
                { identifier }
            )
        end)
    end
    if ok1 and rows and rows[1] then
        local ci = rows[1].charinfo
        if type(ci) == 'string' then
            local ok2, decoded = pcall(json.decode, ci)
            if ok2 then ci = decoded end
        end
        if type(ci) == 'table' and (ci.firstname or ci.lastname) then
            local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):match('^%s*(.-)%s*$')
            if name and name ~= '' then
                playerNames[identifier] = name
                return name
            end
        end
    end
end

local function lookupPlayerName(identifier)
    if not identifier or identifier == '' then return nil end
    if playerNames[identifier] then return playerNames[identifier] end
    -- Try live QBCore lookup (works if player is currently online)
    pcall(function()
        local QBCore = exports['qb-core']:GetCoreObject()
        local Player = QBCore.Functions.GetPlayerByCitizenId(identifier)
        if Player then cacheQBPlayer(Player) end
    end)
    if playerNames[identifier] then return playerNames[identifier] end
    -- Fall back to database for offline players
    return dbLookupPlayerName(identifier)
end

-- ── Router ───────────────────────────────────────────────────────────────────

local function route(req, res, body)
    local method   = req.method
    local rawPath  = req.path:match('^([^?#]*)') or req.path
    local p        = parts(rawPath)
    local q        = req.query or {}

    local bodyData = {}
    if body and #body > 0 then
        bodyData = json.decode(body) or {}
    end

    -- ── UI ───────────────────────────────────────────────────────────────────
    -- GET / → serve the management UI (no auth required)
    if #p == 0 and method == 'GET' then
        local html = LoadResourceFile(GetCurrentResourceName(), 'ui/index.html')
        if not html then
            return err(res, 500, 'UI file not found')
        end
        res.writeHead(200, { ['Content-Type'] = 'text/html; charset=utf-8' })
        res.send(html)
        return
    end

    -- All API routes below require auth
    if not authorized(req) then
        return err(res, 401, 'Unauthorized — set X-API-Key header')
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

        -- GET /dealerships/{id}/coupons
        if #p == 3 and p[3] == 'coupons' and method == 'GET' then
            local coupons = {}
            -- Try jg export; only use result if it returns a non-empty table
            local jg_ok, jg_err = pcall(function()
                local r = jg('getCoupons', dealershipId)
                if r and #r > 0 then coupons = r end
            end)
            print('^5[dealership-manager]^0 [coupons] jg_ok=' .. tostring(jg_ok) .. ' count=' .. #coupons .. ' err=' .. tostring(jg_err))
            -- Fall through to DB if export failed OR returned empty
            if #coupons == 0 then
                local rows
                local db_err1, db_err2
                local db_ok = pcall(function()
                    rows = exports.oxmysql:executeSync(
                        'SELECT * FROM jg_dealership_coupons ORDER BY id DESC LIMIT 200',
                        {}
                    )
                end)
                if not db_ok or not rows then
                    local ma_ok
                    ma_ok, db_err2 = pcall(function()
                        rows = MySQL.query.await(
                            'SELECT * FROM jg_dealership_coupons ORDER BY id DESC LIMIT 200',
                            {}
                        )
                    end)
                    print('^5[dealership-manager]^0 [coupons] oxmysql_ok=' .. tostring(db_ok) .. ' mysql-async_ok=' .. tostring(ma_ok) .. ' err=' .. tostring(db_err2))
                end
                if rows and #rows > 0 then
                    local keys = {}
                    for k in pairs(rows[1]) do keys[#keys+1] = k end
                    print('^5[dealership-manager]^0 [coupons] columns: ' .. table.concat(keys, ', '))
                    print('^5[dealership-manager]^0 [coupons] total rows=' .. #rows .. ' dealershipId=' .. tostring(dealershipId))
                    for _, row in ipairs(rows) do
                        local rid = row.dealership_id or row.dealershipId or row.dealership or ''
                        if rid == dealershipId then
                            coupons[#coupons+1] = row
                        end
                    end
                    if #coupons == 0 then
                        print('^5[dealership-manager]^0 [coupons] no match, sample row: ' .. json.encode(rows[1]))
                    end
                else
                    print('^5[dealership-manager]^0 [coupons] DB returned nil/empty rows')
                end
            end
            return ok(res, coupons)
        end

        -- POST /dealerships/{id}/coupons   { discount_type, discount_value, … }
        if #p == 3 and p[3] == 'coupons' and method == 'POST' then
            local coupon, e
            local ok_jg = pcall(function() coupon, e = jg('createCoupon', dealershipId, bodyData) end)
            if not ok_jg then return err(res, 501, 'createCoupon export not available in this jg-dealerships version') end
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
    -- GET /finance?limit=100  (all active finance deals via direct DB query)
    if #p == 1 and p[1] == 'finance' and method == 'GET' then
        local limit = math.min(tonumber(q.limit) or 100, 1000)
        local rows = {}
        local ok_q = pcall(function()
            rows = exports.oxmysql:executeSync(
                'SELECT * FROM jg_dealership_finance ORDER BY id DESC LIMIT ?',
                { limit }
            ) or {}
        end)
        if not ok_q then
            -- fallback: try mysql-async style
            pcall(function()
                rows = MySQL.query.await(
                    'SELECT * FROM jg_dealership_finance ORDER BY id DESC LIMIT ?',
                    { limit }
                ) or {}
            end)
        end
        -- Attach resolved player names
        for _, row in ipairs(rows) do
            local name = lookupPlayerName(row.identifier)
            if name then row.player_name = name end
        end
        return ok(res, rows)
    end

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

    -- ── Vehicle names ────────────────────────────────────────────────────────
    -- GET /vehicle-names
    if #p == 1 and p[1] == 'vehicle-names' and method == 'GET' then
        return ok(res, vehicleNames)
    end

    -- POST /vehicle-names   { spawnCode: displayName, … }
    if #p == 1 and p[1] == 'vehicle-names' and method == 'POST' then
        for k, v in pairs(bodyData) do
            vehicleNames[k] = tostring(v)
        end
        saveVehicleNames()
        return ok(res, { success = true })
    end

    -- ── Player lookup ────────────────────────────────────────────────────────
    -- GET /player/{identifier}
    if #p == 2 and p[1] == 'player' and method == 'GET' then
        return ok(res, { name = lookupPlayerName(p[2]) })
    end

    -- ── Catch-all ────────────────────────────────────────────────────────────
    return err(res, 404, 'Route not found: ' .. method .. ' ' .. rawPath)
end

-- ── HTTP handler ─────────────────────────────────────────────────────────────

local function handle(req, res, body)
    local success, routeErr = pcall(route, req, res, body or '')
    if not success then
        res.writeHead(500, CORS)
        res.send(json.encode({ error = 'Internal server error', detail = tostring(routeErr) }))
    end
end

SetHttpHandler(function(req, res)
    print('^5[dealership-manager]^0 ' .. req.method .. ' ' .. req.path)

    local m = req.method
    if m == 'OPTIONS' then
        -- CORS preflight — no body expected
        res.writeHead(200, CORS)
        res.send('{}')
    elseif m == 'GET' or m == 'DELETE' then
        -- No body expected; invoke route directly
        handle(req, res, '')
    else
        -- POST/PUT/PATCH — wait for body
        req.setDataHandler(function(body)
            handle(req, res, body)
        end)
    end
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
