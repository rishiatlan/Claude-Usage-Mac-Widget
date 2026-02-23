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

Everything lives in `ClaudeUsageApp.swift` (~1400 lines). Key sections in order:

1. **Enums** — `MetricType`, `NumberDisplayStyle`, `ProgressIconStyle` define user-facing options
2. **LoginItemManager** — AppleScript-based Launch at Login (not LaunchAgent)
3. **Preferences** — Singleton wrapping `UserDefaults.standard` for all settings
4. **SettingsView** — SwiftUI view hosted in an `NSWindowController`, with credential hints inline
5. **FloatingWidgetPanel** — `NSPanel` subclass: borderless, floating, non-activating, all Spaces, draggable
6. **WidgetState** — Enum: `.ok`, `.needsSetup`, `.sessionExpired`, `.loading`
7. **WidgetView** — SwiftUI view with four states, circular progress ring, pace tracking, status messages, context menu (Settings/Refresh/Quit)
8. **WidgetPanelController** — Manages panel lifecycle, saves/restores position via UserDefaults
9. **AppDelegate** — The core: menubar setup, 30-second fetch timer, HTTP requests, retry logic, status calculation
10. **Data Models** — `UsageResponse` and `UsageLimit` (Codable, maps to Claude API JSON)
11. **Main Entry** — `@main` struct bootstraps `NSApplication` as `.accessory` (no dock icon)

## Key Patterns

- **SwiftUI inside Cocoa**: All SwiftUI views are wrapped in `NSHostingView` for embedding in `NSPanel`/`NSWindow`
- **Settings propagation**: Save button posts `Notification.Name.settingsChanged`, AppDelegate observes it to re-fetch
- **Retry with backoff**: Failed API calls retry up to 3 times with exponential backoff (1s, 2s, 4s)
- **Session expiry detection**: HTTP 401/403 triggers `.sessionExpired` widget state (red border, user prompt)
- **Pace calculation**: `expectedUsage = (timeElapsed / windowDuration) * 100`, compared ±5% to determine on-track/borderline/exceeding

## API

Single endpoint, polled every 30 seconds:

```
GET https://claude.ai/api/organizations/{orgId}/usage
Cookie: sessionKey={key}
```

Returns JSON with optional fields: `five_hour`, `seven_day`, `seven_day_sonnet`, etc. Each has `utilization: Double` and `resets_at: String?` (ISO8601).

## Credentials

- **Session key**: Extracted from browser cookies at claude.ai. Expires periodically — app detects this via 401/403.
- **Org ID**: From any claude.ai API request URL. Never expires.
- Stored in `UserDefaults` (domain: `com.claude.usage`). Falls back to env vars `CLAUDE_SESSION_KEY` and `CLAUDE_ORGANIZATION_ID`.

## File Roles

| File | Purpose |
|------|---------|
| `ClaudeUsageApp.swift` | Entire app source — edit this for all changes |
| `Info.plist` | Bundle config: `LSUIElement=true`, min macOS 13.0 |
| `build.sh` | Build script (invokes `swiftc` + `generate-icon.sh`) |
| `run.sh` | Kill existing + rebuild if needed + launch |
| `generate-icon.sh` | Programmatically draws app icon via inline Swift |
| `create-dmg.sh` | Packages app into distributable DMG |

## Logging

App logs to `~/.claude-usage/app.log` (append) and keeps last 50 entries in memory. Viewable in Settings → Log tab.

## Common Gotchas

- `LSUIElement=true` means no dock icon — the app only shows the floating widget and a menubar item
- The menubar icon may be invisible on macOS 26 (Tahoe) due to notch/overflow behavior — the widget is the reliable UI
- `generate-icon.sh` uses inline Swift compilation via heredoc — it may fail on some setups but build.sh continues gracefully
- Widget position is saved per-pixel in UserDefaults — resetting preferences (`defaults delete com.claude.usage`) clears everything including credentials
