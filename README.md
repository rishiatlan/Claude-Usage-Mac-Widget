# Claude Usage Mac Widget

A floating macOS desktop widget that shows your Claude API usage at a glance. Always-on-top, translucent, draggable — lives on your desktop across all Spaces.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## What It Does

- **Circular progress ring** showing real-time utilization % with color-coded status
- **Smart pace tracking** — compares actual vs expected usage so you know if you're burning through limits too fast
- **Reset countdown** — "Resets in 4h 23m" so you know when limits refresh
- **Always visible** — floating widget stays on top of all windows, across all virtual desktops
- **Draggable** — click and drag to reposition anywhere on screen
- **Remembers position** — reopens exactly where you left it
- **Near-realtime** — auto-refreshes every 30 seconds
- **Plain-English status** — shows "Plenty of room", "On pace — be mindful", "Almost out — slow down", etc.
- **Session expiry detection** — widget turns red and tells you to re-extract your session key when it expires
- **Cloudflare-aware** — distinguishes Cloudflare challenges from real auth errors so the widget doesn't falsely show "Session Expired"

## Understanding Your Usage

Claude enforces two types of rate limits. The widget tracks both so you always know where you stand.

### The Two Limits

| Metric | What it means | Resets |
|--------|--------------|--------|
| **5-hour limit** | Rolling window of the last 5 hours of activity. This is the limit that gates you in real-time — if it hits 100%, you're locked out until older messages age past the 5-hour mark. | Continuously — as your oldest messages fall outside the 5-hour window, capacity frees up |
| **7-day limit** | Your total weekly allowance across all Claude usage. This is the hard cap — if it hits 100%, you're done for the week regardless of the 5-hour limit. | Fixed weekly reset |

There is also a **7-day Sonnet-only** metric if you want to track just your Sonnet model usage separately.

### How to Read the Number

The percentage shown is **how much of that limit you've consumed**.

- **5-hour @ 36%** → You've used 36% of your rolling 5-hour budget. Plenty of room to keep chatting.
- **7-day @ 95%** → You've used 95% of your entire weekly allowance. Almost tapped out for the week.

**Which one matters right now?**
- The **5-hour limit** answers: *"Can I keep chatting right now?"*
- The **7-day limit** answers: *"How's my week looking?"*

If either one hits 100%, you'll be rate-limited. The 5-hour recovers on its own as time passes. The 7-day only resets once per week.

### Status Colors (Pace Tracking)

The widget doesn't just show raw usage — it compares your actual usage to where you *should* be based on how much time has elapsed in the window.

| Color | Meaning | Example |
|-------|---------|---------|
| 🟢 Green | **On track** — usage is more than 5% below expected pace | 2h into a 5h window (40% elapsed), and you're at 30% usage |
| 🟠 Orange | **Borderline** — within ±5% of expected pace | 2h into a 5h window, and you're at 38% usage |
| 🔴 Red | **Exceeding** — more than 5% above expected pace | 2h into a 5h window, and you're at 60% usage — slow down |

The **"pace"** line on the widget (e.g., `pace: 40%`) shows the expected usage for the current point in time. If your actual % is well below pace, you're in good shape.

The widget also shows a **plain-English status message** so you don't have to interpret the numbers yourself:

| Message | What it means |
|---------|--------------|
| Plenty of room | Under 30% and on track — chat away |
| On track — you're good | On track, above 30% |
| On pace — be mindful | Usage is roughly where expected |
| Above pace — slow down | You're burning through faster than expected |
| Almost out — slow down | Above 90% and exceeding pace |
| Limit reached — wait for reset | 100% — you're rate-limited until the window resets |

### Practical Tips

- **Start of the day?** Check the 7-day limit first. If it's above 80%, pace yourself.
- **Mid-conversation?** Watch the 5-hour limit. Green = keep going. Red = take a break or your messages will queue.
- **Hit 100% on 5-hour?** Wait it out — capacity recovers as older messages fall off the rolling window. Check the "Resets in..." countdown.
- **Hit 100% on 7-day?** You're done until the weekly reset. The widget will show when that happens.

## Quick Start

### 1. Build

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/rishiatlan/Claude-Usage-Mac-Widget.git
cd Claude-Usage-Mac-Widget
chmod +x build.sh run.sh setup.sh generate-icon.sh
./build.sh
```

### 2. Setup Credentials

Run the interactive setup — it walks you through everything:

```bash
./setup.sh
```

The setup script will:
1. Guide you to copy your **session key** from browser cookies (one paste)
2. **Automatically fetch your org ID** from the Claude API (no manual step)
3. **Validate both credentials** with a test API call and show your current usage
4. Save to the app and offer to launch it

That's it. The widget appears on your desktop with live data.

> **When your session key expires**, just run `./setup.sh` again — it detects existing credentials and only asks for the new key.

### Manual Setup (alternative)

If you prefer to configure manually instead of using the setup script:

<details>
<summary>Click to expand manual instructions</summary>

#### Session Key

1. Open **claude.ai** in Chrome/Safari and make sure you're logged in
2. Open DevTools — `Cmd + Option + I`
3. Go to the **Application** tab (Chrome) or **Storage** tab (Safari)
4. In the left sidebar, expand **Cookies** → click **https://claude.ai**
5. Find the row named **`sessionKey`** and copy the full value

#### Organization ID

1. Still in DevTools, switch to the **Network** tab
2. Send any message in a Claude chat
3. Find any request URL containing `/organizations/` — the UUID after it is your org ID

#### Configure

1. **Right-click** the widget → **Settings...**
2. Paste your **Session Key** and **Organization ID**
3. Select which metric to display (5-hour recommended)
4. Click **Save**

</details>

## Usage

| Action | How |
|--------|-----|
| Open Settings | Right-click widget → Settings... |
| Refresh data | Right-click widget → Refresh |
| Quit app | Right-click widget → Quit |
| Reposition | Click and drag the widget |
| Change metric | Settings → Display Metric dropdown |

### Which Metric Should I Display?

- **5-hour limit** (recommended) — Best for day-to-day use. Tells you in real-time if you can keep chatting.
- **7-day limit (All Models)** — Useful to check periodically so you don't burn through your weekly budget early.
- **7-day limit (Sonnet)** — If you primarily use Sonnet and want to track that model specifically.

You can switch between them anytime in Settings.

### Environment Variable Fallback

If you prefer not to use the Settings UI, you can set environment variables:

```bash
export CLAUDE_SESSION_KEY="sk-ant-sid01-..."
export CLAUDE_ORGANIZATION_ID="your-org-uuid"
```

## How It Works

The app calls the Claude API usage endpoint every 30 seconds:

```
GET https://claude.ai/api/organizations/{orgId}/usage
Cookie: sessionKey={key}
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ClaudeUsageWidget/1.0
```

It parses the response for your current utilization percentage, computes expected pace based on time elapsed in the billing window, and renders it as a floating translucent widget using `NSPanel` with `.ultraThinMaterial` background.

### Architecture

Single-file Swift app (`ClaudeUsageApp.swift`) — no Xcode project, no dependencies, no frameworks beyond Cocoa and SwiftUI. Compiles with `swiftc` directly.

Key components:
- `FloatingWidgetPanel` — borderless `NSPanel` subclass (always-on-top, all Spaces, draggable)
- `WidgetView` — SwiftUI view with four states: setup, session expired, loading, data display
- `WidgetPanelController` — lifecycle manager with position/visibility persistence
- `AppDelegate` — data fetching, 30-second refresh timer, credential management

## Building from Source

```bash
# One-step build
./build.sh

# Manual build
mkdir -p build/ClaudeUsage.app/Contents/MacOS
swiftc ClaudeUsageApp.swift \
  -o build/ClaudeUsage.app/Contents/MacOS/ClaudeUsage \
  -framework Cocoa \
  -framework SwiftUI \
  -parse-as-library

# Run
open build/ClaudeUsage.app
```

## Troubleshooting

**Widget shows "Setup Needed"**
- Run `./setup.sh` or right-click → Settings → enter your session key and org ID

**Widget shows "Session Expired" (red border)**
- Your session key has genuinely expired. Run `./setup.sh` to enter a fresh one — the org ID is remembered and doesn't need to be re-entered.
- Once expired, the widget pauses polling to avoid hammering the API. Saving new credentials in Settings or `./setup.sh` resumes it automatically.

**Widget not appearing**
- The app runs as a background process (no dock icon). Check Activity Monitor for "ClaudeUsage"
- Try quitting and relaunching: `open build/ClaudeUsage.app`

**Stuck at the same percentage**
- The number is accurate — it reflects what Claude's API returns. The 5-hour limit recovers gradually as older messages age out. The 7-day limit only resets once per week.
- Try switching metrics (Settings → Display Metric) to see a different view of your usage.

**Data not loading**
- If the widget shows "Session Expired", re-extract the session key (see above)
- Check that your org ID is correct (it never expires, so if it worked before, it's still good)
- Verify network connectivity

**`setup.sh` shows "Cloudflare blocked the request"**
- This is normal — Cloudflare sometimes challenges `curl` requests. Your session key is probably fine.
- The setup script will ask you to enter the org ID manually instead. The widget app uses macOS `URLSession` which typically passes through Cloudflare without issues.
- You can safely save credentials and launch the widget — it will validate them on its own.

**Build fails with SwiftBridging error**
- Reinstall Command Line Tools: `sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install`

**Widget disappeared after restart**
- The app needs to be running for the widget to show. Enable "Launch at Login" in Settings, or add it to your Login Items manually.

## Privacy & Security

- **No browser access** — `setup.sh` does not read your cookies, Keychain, or any browser data. You paste the session key yourself.
- **Input is masked** — session key entry is hidden (`read -s`) and never echoed to the terminal or written to logs
- **Local storage only** — credentials are saved to macOS UserDefaults on your machine
- **No telemetry** — no analytics, no tracking. The only network calls go to `claude.ai/api` for usage data
- **Cloudflare-aware** — the app and `setup.sh` both detect Cloudflare challenge pages and handle them gracefully, without falsely reporting session expiry
- **Smart polling** — when session genuinely expires, the app pauses API polling to avoid unnecessary requests until new credentials are saved
- **Org ID never expires** — you only need to set it up once. Session keys expire periodically (re-run `./setup.sh`)
- **Fully open source** — read `setup.sh` and `ClaudeUsageApp.swift` to verify everything

## Credits

Built on top of [claude-usage](https://github.com/amoga-org/claude-usage) by amoga-org. Desktop widget adaptation by [@rishiatlan](https://github.com/rishiatlan).

## License

MIT
