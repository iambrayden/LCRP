local TOTAL_DAYS = Config.TotalDays
local RESOURCE = GetCurrentResourceName()

local busy = {}
local welcomed = {}
local itemCache = {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function itemData(name)
    if itemCache[name] == nil then
        itemCache[name] = exports.ox_inventory:Items(name) or false
    end
    return itemCache[name] or nil
end

local function chat(target, message)
    TriggerClientEvent('chat:addMessage', target, {
        color = Config.ChatColor,
        multiline = true,
        args = { ('🎃 %s'):format(Config.ChatPrefix), message },
    })
end

local function getIdentifier(src)
    if Config.TrackBy == 'citizenid' then
        local player = exports.qbx_core:GetPlayer(src)
        return player and player.PlayerData.citizenid
    end
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

--- Returns year, calendar day index, and phase ('before' | 'active' | 'after').
--- The index counts days from day 1 of Config.Month, so it is <= 0 before the
--- calendar opens and > TOTAL_DAYS after it ends (e.g. 32 on November 1st).
local function calendarNow()
    local t = os.date('*t')
    local year = Config.Year or t.year

    local index
    if Config.DebugDay then
        index = Config.DebugDay
    else
        -- Compare at noon so daylight saving changes can't shift the day count.
        local todayNoon = os.time({ year = t.year, month = t.month, day = t.day, hour = 12 })
        local startNoon = os.time({ year = year, month = Config.Month, day = 1, hour = 12 })
        index = math.floor((todayNoon - startNoon) / 86400 + 0.5) + 1
    end

    local phase = index < 1 and 'before' or index > TOTAL_DAYS and 'after' or 'active'
    return year, index, phase
end

local function graceDays()
    return math.max(0, Config.GraceDays or 0)
end

--- A day can be spun on its own day and for Config.GraceDays days after.
local function inWindow(day, index)
    return day <= index and index - day <= graceDays()
end

--- True while any spin can still be used (the month plus the grace period after it).
local function isRunning(index)
    return index >= 1 and index <= TOTAL_DAYS + graceDays()
end

---------------------------------------------------------------------------
-- Intensity: everything ramps from day 1 to the day before Halloween
---------------------------------------------------------------------------

--- 0 on day 1, 1 on the day before Halloween (and on Halloween).
local function progress(day)
    if day >= TOTAL_DAYS - 1 or TOTAL_DAYS <= 2 then return 1 end
    return math.max(0, (day - 1) / (TOTAL_DAYS - 2))
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function amountMultiplier(day)
    local m = Config.Intensity.amountMultiplier
    if day == TOTAL_DAYS then return m.halloween or m.finish end
    return lerp(m.start, m.finish, progress(day))
end

local function fearLevel(day)
    local label = Config.Intensity.levels[1].label
    for _, level in ipairs(Config.Intensity.levels) do
        if day >= level.fromDay then label = level.label end
    end
    return label
end

--- The wheel for a day, with weights slid between `weight` and `lateWeight`.
local function wheelForDay(day)
    if day == TOTAL_DAYS then return Config.HalloweenWheel end

    local t = progress(day)
    local wheel = {}
    for i, segment in ipairs(Config.Wheel) do
        local early = segment.weight or 1
        local late = segment.lateWeight or early
        wheel[i] = { tier = segment.tier, weight = math.floor(lerp(early, late, t) * 100 + 0.5) / 100 }
    end
    return wheel
end

---------------------------------------------------------------------------
-- Rolling
---------------------------------------------------------------------------

local function weightedPick(list)
    local total = 0
    for i = 1, #list do
        total = total + (list[i].weight or 1)
    end

    local roll = math.random() * total
    for i = 1, #list do
        roll = roll - (list[i].weight or 1)
        if roll <= 0 then return i, list[i] end
    end
    return #list, list[#list]
end

--- Rolls a wheel segment, then a reward inside that segment's tier.
local function rollReward(day)
    local segmentIndex, segment = weightedPick(wheelForDay(day))
    local _, reward = weightedPick(Config.Tiers[segment.tier].rewards)
    local multiplier = amountMultiplier(day)

    if reward.money then
        local amount = math.random(reward.money.min, reward.money.max) * multiplier
        return segmentIndex, { tier = segment.tier, money = math.max(50, math.floor(amount / 50 + 0.5) * 50) }
    end

    local min = reward.min or 1
    local max = reward.max or min
    local count = math.random(min, max)
    if max > 1 then
        count = math.floor(count * multiplier + 0.5)
    end

    return segmentIndex, { tier = segment.tier, item = reward.item, count = count }
end

--- What the client is allowed to see about a reward that has already been rolled.
local function describeReward(reward)
    if not reward then return nil end
    local tier = Config.Tiers[reward.tier]
    local info = { tier = reward.tier, tierLabel = tier and tier.label }

    if reward.money then
        info.name, info.label, info.count, info.money = 'money', 'Cash', reward.money, true
    else
        local data = itemData(reward.item)
        info.name = reward.item
        info.label = data and data.label or reward.item
        info.count = reward.count
    end
    return info
end

--- Wheel layout for the client: tier names, icons, colours and weights only.
local function describeWheel(wheel)
    local segments = {}
    for i = 1, #wheel do
        local tier = Config.Tiers[wheel[i].tier]
        segments[i] = {
            tier = wheel[i].tier,
            label = tier.label,
            icon = tier.icon,
            color = tier.color,
            weight = wheel[i].weight or 1,
        }
    end
    return segments
end

---------------------------------------------------------------------------
-- Database
---------------------------------------------------------------------------

local function getClaims(identifier, year)
    local claims = {}
    local rows = MySQL.query.await(
        'SELECT `day`, `status`, `segment`, `reward` FROM `lcrp_halloween_claims` WHERE `identifier` = ? AND `year` = ?',
        { identifier, year }
    ) or {}
    for i = 1, #rows do
        local row = rows[i]
        claims[row.day] = {
            status = row.status,
            segment = row.segment,
            reward = row.reward and json.decode(row.reward),
        }
    end
    return claims
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local function dayStatus(day, index, claim)
    if claim and claim.status == 'claimed' then return 'claimed' end
    if day > index then return 'locked' end
    if not inWindow(day, index) then return 'missed' end
    return claim and 'pending' or 'available'
end

local function buildState(src)
    local identifier = getIdentifier(src)
    if not identifier then return nil end

    local year, index, phase = calendarNow()
    local claims = getClaims(identifier, year)

    local days = {}
    for day = 1, TOTAL_DAYS do
        local claim = claims[day]
        days[day] = {
            day = day,
            status = dayStatus(day, index, claim),
            intensity = day == TOTAL_DAYS and 1 or progress(day),
            fear = fearLevel(day),
            wheel = describeWheel(wheelForDay(day)),
            -- Only reveal a prize once it has been rolled.
            reward = claim and describeReward(claim.reward) or nil,
            segment = claim and claim.segment or nil,
        }
    end

    local nextUnlock
    if not Config.DebugDay and index < TOTAL_DAYS then
        nextUnlock = os.time({ year = year, month = Config.Month, day = math.max(index, 0) + 1, hour = 0 })
    end

    return {
        now = os.time(),
        halloween = os.time({ year = year, month = Config.Month, day = TOTAL_DAYS, hour = 0 }),
        nextUnlock = nextUnlock,
        today = index,
        phase = phase,
        graceDays = graceDays(),
        days = days,
    }
end

local function countOpen(state)
    local count = 0
    for i = 1, #state.days do
        local status = state.days[i].status
        if status == 'available' or status == 'pending' then count += 1 end
    end
    return count
end

---------------------------------------------------------------------------
-- Spinning
---------------------------------------------------------------------------

local function canCarry(src, reward)
    if reward.money then return true end
    return exports.ox_inventory:CanCarryItem(src, reward.item, reward.count) and true or false
end

local function giveReward(src, day, reward)
    if reward.money then
        return exports.qbx_core:AddMoney(src, 'cash', reward.money, ('halloween-wheel-day-%d'):format(day)) ~= false
    end

    local success, response = exports.ox_inventory:AddItem(src, reward.item, reward.count)
    if not success then
        lib.print.warn(('Failed to give %s x%d to %s for day %d (%s)'):format(
            reward.item, reward.count, GetPlayerName(src), day, tostring(response)))
    end
    return success and true or false
end

local function spin(src, day)
    if not exports.qbx_core:GetPlayer(src) then
        return { ok = false, message = 'Your character is not loaded yet.' }
    end

    local identifier = getIdentifier(src)
    if not identifier then
        return { ok = false, message = 'Could not find your character.' }
    end

    local year, index = calendarNow()
    local claim = getClaims(identifier, year)[day]
    local status = dayStatus(day, index, claim)

    if status ~= 'available' and status ~= 'pending' then
        local reasons = {
            claimed = 'You already spun the wheel for this day.',
            locked = 'This spin has not unlocked yet.',
            missed = 'This spin has expired.',
        }
        return { ok = false, message = reasons[status] or 'You cannot spin this day.', state = buildState(src) }
    end

    -- Roll once and save it before anything else. If the player can't carry the
    -- prize it stays saved as pending, so emptying or filling pockets never
    -- gives them a second roll.
    local freshSpin = not claim
    if freshSpin then
        local segment, reward = rollReward(day)
        local inserted = MySQL.update.await(
            'INSERT IGNORE INTO `lcrp_halloween_claims` (`identifier`, `year`, `day`, `status`, `segment`, `reward`) VALUES (?, ?, ?, ?, ?, ?)',
            { identifier, year, day, 'pending', segment, json.encode(reward) }
        )
        if inserted and inserted > 0 then
            claim = { status = 'pending', segment = segment, reward = reward }
        else
            -- Another request got there first; use whatever it saved.
            freshSpin = false
            claim = getClaims(identifier, year)[day]
            if not claim or claim.status ~= 'pending' then
                return { ok = false, message = 'You already spun the wheel for this day.', state = buildState(src) }
            end
        end
    end

    local result = {
        segment = claim.segment,
        reward = describeReward(claim.reward),
        animate = freshSpin,
    }

    if not canCarry(src, claim.reward) then
        result.ok = false
        result.message = 'Your pockets are full! Your prize is saved. Make some room and collect it.'
        result.state = buildState(src)
        return result
    end

    local updated = MySQL.update.await(
        'UPDATE `lcrp_halloween_claims` SET `status` = ? WHERE `identifier` = ? AND `year` = ? AND `day` = ? AND `status` = ?',
        { 'claimed', identifier, year, day, 'pending' }
    )
    if not updated or updated < 1 then
        return { ok = false, message = 'You already collected this prize.', state = buildState(src) }
    end

    if not giveReward(src, day, claim.reward) then
        -- Put it back to pending so the player can try collecting again.
        MySQL.update.await(
            'UPDATE `lcrp_halloween_claims` SET `status` = ? WHERE `identifier` = ? AND `year` = ? AND `day` = ?',
            { 'pending', identifier, year, day }
        )
        result.ok = false
        result.message = 'Something went wrong giving your prize. It is saved, try collecting again.'
        result.state = buildState(src)
        return result
    end

    local prize = result.reward.money and ('$%s'):format(result.reward.count)
        or ('%dx %s'):format(result.reward.count, result.reward.label)
    lib.print.info(('%s (%s) won %s on day %d'):format(GetPlayerName(src), identifier, prize, day))

    result.ok = true
    result.message = ('You won %s!'):format(prize)
    result.state = buildState(src)
    return result
end

---------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------

lib.callback.register('lcrp_halloween:getState', function(src)
    return buildState(src)
end)

lib.callback.register('lcrp_halloween:spin', function(src, day)
    day = tonumber(day)
    if not day or day % 1 ~= 0 or day < 1 or day > TOTAL_DAYS then
        return { ok = false, message = 'Invalid day.' }
    end
    if busy[src] then
        return { ok = false, message = 'Slow down!' }
    end

    busy[src] = true
    local success, result = pcall(spin, src, day)
    busy[src] = nil

    if not success then
        lib.print.error(('Spin failed for %s (day %d): %s'):format(GetPlayerName(src), day, result))
        return { ok = false, message = 'Something went wrong. Please try again.' }
    end
    return result
end)

---------------------------------------------------------------------------
-- Chat messages
---------------------------------------------------------------------------

RegisterNetEvent('lcrp_halloween:server:loaded', function()
    local src = source
    if not Config.JoinMessage or welcomed[src] then return end
    welcomed[src] = true

    local _, index = calendarNow()
    if not isRunning(index) then return end

    local state = buildState(src)
    local open = state and countOpen(state) or 0
    local cmd = '/' .. Config.Command

    if open > 0 then
        local yesterday = index > 1 and state.days[index - 1]
        local expiring = yesterday and (yesterday.status == 'available' or yesterday.status == 'pending')
        chat(src, ('Fear level: %s. You have %d Halloween spin%s waiting%s. Type %s to spin the wheel!'):format(
            fearLevel(math.min(index, TOTAL_DAYS)), open, open == 1 and '' or 's',
            expiring and ' (yesterday\'s expires at midnight)' or '', cmd))
    elseif index < TOTAL_DAYS then
        chat(src, ('You have used every spin so far. The wheel gets better every day. Type %s to see the countdown.'):format(cmd))
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    welcomed[src] = nil
    busy[src] = nil
end)

if Config.Broadcast.enabled then
    CreateThread(function()
        local interval = math.max(1, Config.Broadcast.intervalMinutes) * 60000
        while true do
            Wait(interval)
            local _, index = calendarNow()
            local cmd = '/' .. Config.Command
            if index >= 1 and index < TOTAL_DAYS then
                local left = TOTAL_DAYS - index
                chat(-1, ('%d day%s until Halloween. Fear level: %s. The wheel gets better every day. Type %s to spin!')
                    :format(left, left == 1 and '' or 's', fearLevel(index), cmd))
            elseif index == TOTAL_DAYS then
                chat(-1, ('Happy Halloween! The Halloween wheel has the best odds of the month. Type %s to spin it.'):format(cmd))
            elseif isRunning(index) then
                chat(-1, ('Last chance! The Halloween wheel can still be spun with %s.'):format(cmd))
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

local function validateConfig()
    for _, wheelName in ipairs({ 'Wheel', 'HalloweenWheel' }) do
        for i, segment in ipairs(Config[wheelName]) do
            if not Config.Tiers[segment.tier] then
                lib.print.error(('Config.%s segment %d uses unknown tier "%s"'):format(wheelName, i, segment.tier))
            end
        end
    end

    for tierName, tier in pairs(Config.Tiers) do
        for _, reward in ipairs(tier.rewards) do
            if reward.item and not itemData(reward.item) then
                lib.print.warn(('Tier "%s" reward "%s" does not exist in ox_inventory'):format(tierName, reward.item))
            end
        end
    end
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lcrp_halloween_claims` (
            `identifier` VARCHAR(64) NOT NULL,
            `year` SMALLINT UNSIGNED NOT NULL,
            `day` TINYINT UNSIGNED NOT NULL,
            `status` VARCHAR(10) NOT NULL DEFAULT 'claimed',
            `segment` TINYINT UNSIGNED NULL,
            `reward` LONGTEXT NULL,
            `claimed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`, `year`, `day`)
        )
    ]])

    -- Upgrade tables created by the first version of this resource.
    local hasReward = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'lcrp_halloween_claims' AND COLUMN_NAME = 'reward'
    ]])
    if hasReward == 0 then
        MySQL.query.await([[
            ALTER TABLE `lcrp_halloween_claims`
                ADD COLUMN `status` VARCHAR(10) NOT NULL DEFAULT 'claimed' AFTER `day`,
                ADD COLUMN `segment` TINYINT UNSIGNED NULL AFTER `status`,
                ADD COLUMN `reward` LONGTEXT NULL AFTER `segment`
        ]])
    end

    validateConfig()

    if Config.DebugDay then
        lib.print.warn(('%s is running with Config.DebugDay = %d. Turn it off on the live server.')
            :format(RESOURCE, Config.DebugDay))
    end
end)
