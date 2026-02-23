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
chmod +x build.sh run.sh generate-icon.sh
./build.sh
open build/ClaudeUsage.app
```

The widget will appear on your desktop automatically on first launch.

### 2. Get Your Claude Credentials

You need two values from [claude.ai](https://claude.ai):

#### Session Key

1. Open **claude.ai** in Chrome/Safari and make sure you're logged in
2. Open DevTools — `Cmd + Option + I`
3. Go to the **Application** tab (Chrome) or **Storage** tab (Safari)
4. In the left sidebar, expand **Cookies** → click **https://claude.ai**
5. Find the row named **`sessionKey`**
6. Copy the full value — it starts with `sk-ant-sid01-...`

> **Note:** Session keys expire periodically. If the widget stops updating, re-extract the key from your browser cookies.

#### Organization ID

1. Still in DevTools, switch to the **Network** tab
2. Send any message in a Claude chat
3. Look at the network requests — find any URL containing `/organizations/`
4. The UUID after `/organizations/` is your org ID — it's in standard `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` format

> **Tip:** The org ID doesn't change. You only need to grab it once.

### 3. Configure

1. **Right-click** the widget → **Settings...**
2. Paste your **Session Key** and **Organization ID**
3. Select which metric to display (5-hour recommended for day-to-day use)
4. Click **Save**

The widget will immediately fetch your usage data and display it.

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
```

It parses the response for your current utilization percentage, computes expected pace based on time elapsed in the billing window, and renders it as a floating translucent widget using `NSPanel` with `.ultraThinMaterial` background.

### Architecture

Single-file Swift app (`ClaudeUsageApp.swift`) — no Xcode project, no dependencies, no frameworks beyond Cocoa and SwiftUI. Compiles with `swiftc` directly.

Key components:
- `FloatingWidgetPanel` — borderless `NSPanel` subclass (always-on-top, all Spaces, draggable)
- `WidgetView` — SwiftUI view with three states: setup, loading, data display
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
- Right-click → Settings → enter your session key and org ID

**Widget not appearing**
- The app runs as a background process (no dock icon). Check Activity Monitor for "ClaudeUsage"
- Try quitting and relaunching: `open build/ClaudeUsage.app`

**Stuck at the same percentage**
- The number is accurate — it reflects what Claude's API returns. The 5-hour limit recovers gradually as older messages age out. The 7-day limit only resets once per week.
- Try switching metrics (Settings → Display Metric) to see a different view of your usage.

**Data not loading**
- Session keys expire periodically — re-extract from claude.ai cookies
- Check that your org ID is correct
- Verify network connectivity

**Build fails with SwiftBridging error**
- Reinstall Command Line Tools: `sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install`

**Widget disappeared after restart**
- The app needs to be running for the widget to show. Enable "Launch at Login" in Settings, or add it to your Login Items manually.

## Privacy

- Credentials are stored locally in macOS UserDefaults
- No telemetry, no analytics, no data sent anywhere except to `claude.ai/api` for usage data
- Fully open source — read the single source file to verify

## Credits

Built on top of [claude-usage](https://github.com/amoga-org/claude-usage) by amoga-org. Desktop widget adaptation by [@rishiatlan](https://github.com/rishiatlan).

## License

MIT
