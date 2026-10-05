Config = {}

-- Chat command that opens the calendar.
Config.Command = 'halloween'

-- Month the calendar runs in (10 = October). Day N of the calendar unlocks at
-- midnight server time on day N of this month.
Config.Month = 10

-- Number of days in the calendar. The last day is the Halloween grand spin.
Config.TotalDays = 31

-- Year the claims are tracked under. nil = current year, so the calendar
-- resets automatically next October.
Config.Year = nil

-- How many extra days a spin stays available after its own day.
-- 1 = today's spin plus yesterday's as a grace period. 0 = today only.
-- Anything older is expired for good.
Config.GraceDays = 1

-- 'citizenid' = one calendar per character.
-- 'license'   = one calendar per Rockstar license, shared by all characters.
Config.TrackBy = 'citizenid'

-- Testing only: set to a number (1-31) to pretend it is that day of the month.
-- Leave nil on the live server.
Config.DebugDay = nil

-- Chat message shown to a player when their character loads.
Config.JoinMessage = true

-- Chat message broadcast to everyone on an interval.
Config.Broadcast = {
    enabled = true,
    intervalMinutes = 60,
}

Config.ChatPrefix = 'Halloween'
Config.ChatColor = { 255, 122, 24 }

---------------------------------------------------------------------------
-- Prize tiers
--
-- A spin first lands on a wheel segment (which belongs to a tier), then picks
-- one random reward from that tier. Players only ever see the tier names on
-- the wheel, never the item lists.
--
-- Reward formats (every item name here exists in ox_inventory):
--   { item = 'name', min = 1, max = 3 }  -> random amount between min and max
--   { money = { min = 500, max = 2000 } } -> random cash, rounded to $50
-- Add `weight = n` to a reward to make it more (or less) likely inside its
-- tier. The default weight is 1.
---------------------------------------------------------------------------

Config.Tiers = {
    treat = {
        label = 'Treat',
        icon = '🍬',
        color = '#ff7a18',
        rewards = {
            { item = 'water', min = 2, max = 4 },
            { item = 'coffee', min = 1, max = 3 },
            { item = 'sandwich', min = 1, max = 3 },
            { item = 'burger', min = 1, max = 3 },
            { item = 'cooked_fries', min = 1, max = 3 },
            { item = 'cooked_pizza', min = 1, max = 2 },
            { item = 'grape', min = 3, max = 6 },
            { item = 'sprunk_drink', min = 2, max = 4 },
            { item = 'cola_drink', min = 2, max = 4 },
            { item = 'orange_drink', min = 2, max = 4 },
            { item = 'grapejuice', min = 2, max = 4 },
            { item = 'wine', min = 1, max = 2 },
            { item = 'beer', min = 2, max = 6 },
            { item = 'vodka', min = 1, max = 1 },
            { item = 'whiskey', min = 1, max = 1 },
        },
    },

    supplies = {
        label = 'Supplies',
        icon = '🩹',
        color = '#7d3cff',
        rewards = {
            { item = 'bandage', min = 3, max = 6 },
            { item = 'gauze', min = 3, max = 6 },
            { item = 'firstaid', min = 1, max = 2 },
            { item = 'repair_kit', min = 1, max = 2 },
        },
    },

    cash = {
        label = 'Cash',
        icon = '💵',
        color = '#2fbf71',
        rewards = {
            { money = { min = 500, max = 2500 } },
        },
    },

    fireworks = {
        label = 'Fireworks',
        icon = '🎆',
        color = '#e0408a',
        rewards = {
            { item = 'firework1', min = 1, max = 3 },
            { item = 'firework2', min = 1, max = 3 },
            { item = 'firework3', min = 1, max = 3 },
            { item = 'firework4', min = 1, max = 3 },
        },
    },

    rare = {
        label = 'Rare',
        icon = '💀',
        color = '#2d9cdb',
        rewards = {
            { item = 'fishing_rod', min = 1, max = 1 },
            { item = 'fishing_kit', min = 1, max = 1 },
            { item = 'metal_detector', min = 1, max = 1 },
            { item = 'WEAPON_FLASHLIGHT', min = 1, max = 1 },
            { item = 'WEAPON_KNIFE', min = 1, max = 1 },
        },
    },

    jackpot = {
        label = 'Jackpot',
        icon = '👑',
        color = '#ffd23f',
        rewards = {
            { money = { min = 7500, max = 15000 } },
        },
    },
}

---------------------------------------------------------------------------
-- Wheels
--
-- Segments go clockwise from the top. A segment's chance of being hit is its
-- weight divided by the total weight of the wheel, and its slice on screen is
-- drawn at the same size, so what players see matches the real odds.
--
-- `weight` is used on day 1 and `lateWeight` on the day before Halloween.
-- Days in between slide smoothly from one to the other, so the wheel gets
-- better every day: food slices shrink, cash/rare/jackpot slices grow.
---------------------------------------------------------------------------

-- Used on days 1-30. Roughly percentages.
Config.Wheel = {
    { tier = 'treat',     weight = 16, lateWeight = 8 },
    { tier = 'supplies',  weight = 10, lateWeight = 8 },
    { tier = 'cash',      weight = 7,  lateWeight = 10 },
    { tier = 'treat',     weight = 16, lateWeight = 8 },
    { tier = 'fireworks', weight = 6,  lateWeight = 9 },
    { tier = 'rare',      weight = 3,  lateWeight = 6 },
    { tier = 'treat',     weight = 16, lateWeight = 8 },
    { tier = 'supplies',  weight = 10, lateWeight = 8 },
    { tier = 'cash',      weight = 7,  lateWeight = 10 },
    { tier = 'fireworks', weight = 6,  lateWeight = 9 },
    { tier = 'jackpot',   weight = 1,  lateWeight = 6 },
    { tier = 'rare',      weight = 3,  lateWeight = 6 },
}

-- Used on Halloween (the last day). Best odds of the month, no food.
Config.HalloweenWheel = {
    { tier = 'cash',      weight = 20 },
    { tier = 'fireworks', weight = 15 },
    { tier = 'rare',      weight = 15 },
    { tier = 'jackpot',   weight = 10 },
    { tier = 'cash',      weight = 20 },
    { tier = 'supplies',  weight = 10 },
    { tier = 'rare',      weight = 10 },
}

---------------------------------------------------------------------------
-- Intensity
--
-- Everything ramps up as Halloween gets closer.
---------------------------------------------------------------------------

Config.Intensity = {
    -- Multiplies cash and stack sizes. Day 1 uses `start`, the day before
    -- Halloween uses `finish`, and Halloween itself uses `halloween`.
    -- Single items (max = 1, like the knife) are never multiplied.
    amountMultiplier = { start = 1.0, finish = 2.0, halloween = 2.5 },

    -- "Fear level" shown in the menu. Each level starts on `fromDay`.
    levels = {
        { fromDay = 1,  label = 'Spooky' },
        { fromDay = 11, label = 'Creepy' },
        { fromDay = 21, label = 'Terrifying' },
        { fromDay = 28, label = 'Nightmare' },
        { fromDay = 31, label = 'Halloween' },
    },
}
