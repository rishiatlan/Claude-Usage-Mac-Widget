# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A macOS floating desktop widget that displays Claude API usage limits in real-time. Single-file Swift app — no Xcode project, no dependencies, no package manager. Compiles with `swiftc` directly against Cocoa and SwiftUI frameworks.

The widget is the primary interface (not the menubar icon). It floats on the desktop across all Spaces using a borderless `NSPanel`.

## Build & Run

```bash
./build.sh                        # Compile + bundle into build/ClaudeUsage.app
open build/ClaudeUsage.app        # Launch (auto-shows widget)
killall ClaudeUsage               # Stop running instance
```

There are no tests, no linter, and no CI. The build is a single `swiftc` invocation:

```bash
swiftc ClaudeUsageApp.swift -o build/ClaudeUsage.app/Contents/MacOS/ClaudeUsage \
  -framework Cocoa -framework SwiftUI -parse-as-library
```

After editing `ClaudeUsageApp.swift`, always rebuild and relaunch — there is no hot reload.

## Architecture

Everything lives in `ClaudeUsageApp.swift` (~1660 lines). Key sections in order:

1. **Enums** — `MetricType`, `NumberDisplayStyle`, `ProgressIconStyle` define user-facing options
2. **LoginItemManager** — `SMAppService`-based Launch at Login (macOS 13+ native API, no special permissions required)
3. **UpdateChecker** — Fetches `VERSION` from GitHub raw, compares semver against local `CFBundleShortVersionString`, handles self-update (git pull → build.sh → relaunch)
4. **Preferences** — Singleton wrapping `UserDefaults.standard` for all settings
5. **SettingsView** — SwiftUI view hosted in an `NSWindowController`, with credential hints inline and update banner
6. **FloatingWidgetPanel** — `NSPanel` subclass: borderless, floating, non-activating, all Spaces, draggable
7. **WidgetState** — Enum: `.ok`, `.needsSetup`, `.sessionExpired`, `.loading`
8. **WidgetView** — SwiftUI view with four states, circular progress ring, pace tracking, status messages, blue update dot, context menu (Settings/Refresh/Quit)
9. **WidgetPanelController** — Manages panel lifecycle, saves/restores position via UserDefaults
10. **AppDelegate** — The core: menubar setup, 30-second fetch timer, 24-hour update check timer, HTTP requests, retry logic, status calculation
11. **Data Models** — `UsageResponse` and `UsageLimit` (Codable, maps to Claude API JSON)
12. **Main Entry** — `@main` struct bootstraps `NSApplication` as `.accessory` (no dock icon)

## Key Patterns

- **SwiftUI inside Cocoa**: All SwiftUI views are wrapped in `NSHostingView` for embedding in `NSPanel`/`NSWindow`
- **Settings propagation**: Save button posts `Notification.Name.settingsChanged`, AppDelegate observes it to re-fetch and resets `isSessionExpired` flag
- **Retry with backoff**: Failed API calls retry up to 3 times with exponential backoff (1s, 2s, 4s)
- **Cloudflare vs session expiry**: HTTP 401/403 responses are inspected — Cloudflare challenge pages (HTML with "Just a moment") trigger retry with backoff; real auth errors (JSON) trigger `.sessionExpired` widget state
- **Polling pause on expiry**: When session is confirmed expired (`isSessionExpired = true`), the 30-second timer skips API calls to avoid hammering the server. Resets when user saves new credentials via Settings.
- **Pace calculation**: `expectedUsage = (timeElapsed / windowDuration) * 100`, compared ±5% to determine on-track/borderline/exceeding
- **Multi-limit awareness**: When the selected metric is at 100% but other limits have room, the widget shows "Window full — still available" with a blue note showing other limits. "All limits reached" only appears when everything is exhausted.
- **No-cache API requests**: `cachePolicy = .reloadIgnoringLocalCacheData` + `Cache-Control: no-cache` on every fetch — ensures limit changes from admin console are reflected immediately

## API

Single endpoint, polled every 30 seconds:

```
GET https://claude.ai/api/organizations/{orgId}/usage
Cookie: sessionKey={key}
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ClaudeUsageWidget/1.0
```

Returns JSON with optional fields: `five_hour`, `seven_day`, `seven_day_sonnet`, etc. Each has `utilization: Double` and `resets_at: String?` (ISO8601).

**Cloudflare note**: The API sits behind Cloudflare. `curl` requests may get challenged with a 403 HTML page ("Just a moment..."). The app's `URLSession` typically passes through. Both the app and `setup.sh` detect Cloudflare challenges by checking the response body for markers (`Just a moment`, `challenge-platform`, `_cf_chl_opt`, `cf-browser-verification`) and handle them as transient errors rather than session expiry.

## Credentials

- **Setup**: `./setup.sh` — interactive CLI that guides session key paste, auto-fetches org ID via API, validates, and saves
- **Session key**: User pastes from browser cookies. Expires periodically — app detects via 401/403, widget shows "Session Expired"
- **Org ID**: Auto-fetched by `setup.sh` via `GET /api/organizations`. Never expires.
- Stored in `UserDefaults` (domain: `com.claude.usage`). Falls back to env vars `CLAUDE_SESSION_KEY` and `CLAUDE_ORGANIZATION_ID`.
- **Security**: `setup.sh` never reads browser files, Keychain, or cookies directly. Input is masked (`read -s`). No credentials in logs or temp files.

## File Roles

| File | Purpose |
|------|---------|
| `ClaudeUsageApp.swift` | Entire app source (~1660 lines) — edit this for all changes |
| `Info.plist` | Bundle config: `LSUIElement=true`, min macOS 13.0 |
| `build.sh` | Build script (invokes `swiftc` + `generate-icon.sh`) |
| `run.sh` | Kill existing + rebuild if needed + launch |
| `setup.sh` | Interactive credential setup — guides paste, auto-fetches org ID, validates, detects Cloudflare |
| `generate-icon.sh` | Programmatically draws app icon via inline Swift |
| `create-dmg.sh` | Packages app into distributable DMG |
| `README.md` | User-facing documentation and troubleshooting |
| `DEVELOPMENT.md` | Developer guide — architecture, adding features, debugging |
| `CLAUDE.md` | Claude Code guidance — this file |
| `icon.svg` | Source icon for the app |
| `VERSION` | Version string for update checking — bumped only for material releases |
| `assets/` | Widget screenshots for README |

## Logging

App logs to `~/.claude-usage/app.log` (append) and keeps last 50 entries in memory. Viewable in Settings → Log tab.

## Common Gotchas

- `LSUIElement=true` means no dock icon — the app only shows the floating widget and a menubar item
- The menubar icon may be invisible on macOS 26 (Tahoe) due to notch/overflow behavior — the widget is the reliable UI
- `generate-icon.sh` uses inline Swift compilation via heredoc — it may fail on some setups but build.sh continues gracefully
- Widget position is saved per-pixel in UserDefaults — resetting preferences (`defaults delete com.claude.usage`) clears everything including credentials
- **Cloudflare 403 ≠ session expired**: `curl` tests against the API may return 403 with an HTML challenge page — this is Cloudflare blocking non-browser requests, not an expired session. The app distinguishes these by checking the response body for Cloudflare markers before declaring session expired.
- **Polling pauses on expiry**: Once `isSessionExpired` is set, the 30-second timer skips fetches. The flag resets when `Notification.Name.settingsChanged` fires (user saves new credentials).
