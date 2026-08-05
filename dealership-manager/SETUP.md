# dealership-manager — Setup

HTTP bridge resource exposing `jg-dealerships` exports to the web management UI.
Requires **jg-dealerships v2.1.1 or newer**.

## 1. Install the resource

Copy the `dealership-manager/` folder into your server's `resources/` directory.

```
resources/
  dealership-manager/
    fxmanifest.lua
    server/
      bridge.lua
```

## 2. Configure server.cfg

```cfg
# Required — start order matters: jg-dealerships must start before dealership-manager
ensure jg-dealerships
ensure dealership-manager

# Optional but strongly recommended — set a secret API key
set dealership_manager_api_key "change-me-to-something-secret"
```

## 3. Verify

After starting the server, the resource logs:

```
[dealership-manager] HTTP bridge ready — base URL: /dealership-manager/
```

Test with: `http://<your-server>:30120/dealership-manager/`  
Expected response: `{"ok":true,"resource":"dealership-manager","version":"1.0.0"}`

## 4. Use the web UI

Open `dealership-ui/index.html` directly in your browser (no web server needed).

- **FiveM Server URL**: `<ip>:30120`  (e.g. `localhost:30120` or `play.yourrp.com:30120`)
- **API Key**: whatever you set in `dealership_manager_api_key`

## API endpoints

All endpoints are relative to `http://<server>:<port>/dealership-manager/`.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/dealerships` | List all dealerships |
| GET | `/dealerships/{id}` | Get specific dealership |
| GET | `/dealerships/{id}/balance` | Account balance |
| POST | `/dealerships/{id}/balance/add` | Add funds `{amount}` |
| POST | `/dealerships/{id}/balance/remove` | Remove funds `{amount}` |
| GET | `/dealerships/{id}/vehicles` | Showroom vehicles with stock + pricing |
| GET | `/dealerships/{id}/employees` | Employee list |
| GET | `/dealerships/{id}/sales?limit=50` | Sales history |
| GET | `/dealerships/{id}/total-sales` | Total revenue |
| POST | `/dealerships/{id}/coupons` | Create coupon |
| GET | `/dealerships/{id}/coupons/validate?code=&spawnCode=&category=&isFinanced=` | Validate coupon |
| GET | `/dealerships/{id}/stock/{spawnCode}` | Get vehicle stock |
| POST | `/dealerships/{id}/stock/{spawnCode}/increment` | Increment stock `{amount?}` |
| POST | `/dealerships/{id}/stock/{spawnCode}/decrement` | Decrement stock `{amount?}` |
| POST | `/dealerships/{id}/stock/{spawnCode}/set` | Set stock `{stock}` |
| GET | `/dealerships/{id}/price/{spawnCode}` | Per-dealership price |
| GET | `/price/{spawnCode}` | Base catalog price |
| GET | `/finance/{identifier}` | Player financed vehicles |
| GET | `/finance/{identifier}/count` | Finance plan count |
| GET | `/finance/plate/{plate}` | Finance record by plate |
| POST | `/finance/payment` | Make payment `{src, plate}` |

## HTTPS / mixed content note

If you host the web UI on an HTTPS site but your FiveM server is HTTP-only,
the browser will block requests (mixed content policy). Two options:

1. **Open the HTML file locally** (`file://` — no restriction, recommended for internal use)
2. **Reverse proxy** FiveM's HTTP port behind HTTPS (nginx/Caddy)
