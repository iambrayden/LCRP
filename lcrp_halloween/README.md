# lcrp_halloween

Halloween countdown and daily spin wheel for Last Chance Roleplay (Qbox + ox_inventory).

## Features

- `/halloween` opens a NUI calendar with a live countdown to Halloween and to the next unlock.
- **One spin per day, Oct 1–31.** A day can only be spun on that day, plus one grace day after it (`Config.GraceDays`). After that it expires. The Oct 31 Halloween wheel stays spinnable through Nov 1.
- **Prizes are hidden and random.** The calendar never shows what a day gives. The wheel only shows prize tiers (Treat, Supplies, Cash, Fireworks, Rare, Jackpot). The server picks the segment, then a random item and amount inside that tier, so everyone gets something different.
- **Honest odds.** Each slice on the wheel is drawn at the size of its real chance.
- **It gets more intense as Halloween gets closer:**
  - The wheel odds slide from `weight` to `lateWeight` across the month: fewer food slices, more cash/rare/jackpot.
  - Cash and stack sizes are multiplied, ramping from x1.0 to x2.0, and x2.5 on Halloween.
  - A fear level climbs from Spooky → Creepy → Terrifying → Nightmare → Halloween. The menu turns redder, embers and a heartbeat pulse pick up, and the spin gets longer and tenser.
  - Halloween (day 31) uses its own wheel with the best odds of the month.
- **No rerolls.** A spin's result is saved before anything is given. If the player's pockets are full, the prize stays saved and they collect it after making room. They can't spin again.
- Chat message when a character loads, and a server-wide reminder every hour (`Config.Broadcast`).
- Claims are stored in MySQL per character (citizenid). Every spin is checked on the server.

## Install

1. Drop `lcrp_halloween` into your resources folder.
2. Add `ensure lcrp_halloween` to `server.cfg` **after** `ox_lib`, `oxmysql`, `qbx_core` and `ox_inventory`.
3. Restart. The `lcrp_halloween_claims` table is created automatically, and upgraded if it was created by an older version (`sql/halloween.sql` is there if you'd rather run it by hand).

## Config

Everything lives in `config.lua`:

| Option | Default | What it does |
|---|---|---|
| `Command` | `halloween` | Chat command that opens the calendar |
| `GraceDays` | `1` | Extra days a spin stays available after its own day (`0` = same day only) |
| `TrackBy` | `citizenid` | `citizenid` = one calendar per character, `license` = one per player |
| `DebugDay` | `nil` | Set to 1–31 to test a specific day. **Leave nil on live.** |
| `JoinMessage` | `true` | Chat message when a character loads |
| `Broadcast` | every 60 min | Server-wide chat reminder |
| `Tiers` | 6 tiers | The reward pool for each tier: `{ item, min, max }` or `{ money = { min, max } }` |
| `Wheel` | 12 segments | Days 1–30. `weight` (day 1) slides to `lateWeight` (day 30) |
| `HalloweenWheel` | 7 segments | Day 31 |
| `Intensity` | | Amount multiplier ramp and fear level names |

Days unlock at midnight **server time**. On start, the server prints a warning for any reward item that ox_inventory doesn't recognize, and every win is logged to the server console.

Item icons come from `ox_inventory/web/images/<item>.png`. An emoji is shown if an image is missing.
