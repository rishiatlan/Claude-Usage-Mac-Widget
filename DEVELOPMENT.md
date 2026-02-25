# Development Guide

## Project Overview

A macOS floating desktop widget built with Swift and SwiftUI that monitors Claude API usage limits with intelligent pace-based tracking. Runs as a standalone always-on-top widget — no menubar dependency.

## Architecture

### Key Components

```
ClaudeUsageApp.swift
├── MetricType (enum)              - Available metrics to track
├── Preferences (singleton)        - UserDefaults wrapper for settings
├── SettingsWindowController       - Settings window management
├── SettingsView (SwiftUI)         - Settings UI with credential guidance
├── FloatingWidgetPanel (NSPanel)  - Borderless, always-on-top, all-Spaces widget
├── WidgetState (enum)             - ok, needsSetup, sessionExpired, loading
├── WidgetView (SwiftUI)           - Four-state widget UI with context menu
├── WidgetPanelController          - Widget lifecycle, position persistence
└── AppDelegate                    - Data fetching, timer, credential management
```

### Data Flow

1. **Startup**: App launches → Reads preferences → Shows widget → Fetches usage data → Updates widget
2. **Auto-refresh**: Timer triggers every 30 seconds → Fetches usage data → Updates widget (skipped if `isSessionExpired`)
3. **User interaction**: Right-click context menu → Settings/Refresh/Quit
4. **Session expired**: API returns 401/403 with JSON body → `isSessionExpired = true` → Polling paused → Widget shows "Session Expired" (red border)
5. **Cloudflare challenge**: API returns 403 with HTML body → Treated as transient error → Retry with exponential backoff (up to 3 times)
6. **Credentials missing**: Widget shows "Setup Needed" → auto-opens Settings on first launch
7. **Settings saved**: `Notification.Name.settingsChanged` fires → `isSessionExpired` and `consecutiveFailures` reset → Immediate re-fetch

## Code Structure

### Preferences Storage

```swift
// Session key and selected metric stored in UserDefaults
Preferences.shared.sessionKey: String?
Preferences.shared.selectedMetric: MetricType
```

### API Integration

```swift
// Endpoint
https://claude.ai/api/organizations/{org_id}/usage

// Authentication
Cookie: sessionKey={value}
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ClaudeUsageWidget/1.0

// Response structure
{
  "five_hour": { "utilization": 19.0, "resets_at": "..." },
  "seven_day": { "utilization": 6.0, "resets_at": "..." },
  "seven_day_sonnet": { "utilization": 6.0, "resets_at": "..." }
}
```

### Cloudflare Handling

The API sits behind Cloudflare, which may challenge non-browser requests with a 403 HTML page. The app distinguishes Cloudflare challenges from real auth errors by checking the response body:

```swift
// Cloudflare markers checked in response body
"Just a moment"           // Cloudflare interstitial title
"cf-browser-verification" // Cloudflare JS challenge
"challenge-platform"      // Cloudflare challenge script
"_cf_chl_opt"             // Cloudflare challenge options object
```

- **Cloudflare 403**: Retry with exponential backoff (transient error)
- **Real 401/403**: Set `isSessionExpired = true`, show "Session Expired" widget state, pause polling

The `setup.sh` script uses the same detection with a `is_cloudflare_challenge()` bash function and sends a browser-like `User-Agent` header to reduce challenge frequency.

### Pace Calculation Algorithm

The app determines icon color based on consumption pace:

```swift
// Calculate time elapsed in the window
timeElapsed = windowDuration - timeRemaining

// Expected consumption if usage is evenly distributed
expectedConsumption = (timeElapsed / windowDuration) * 100

// Example: 5-hour window, 3 hours remaining
// timeElapsed = 2 hours
// expectedConsumption = (2 / 5) * 100 = 40%
// If actual = 60%, then 20% over expected

// Status logic (±5% threshold)
if utilization < expectedConsumption - 5:
    status = .onTrack     // ✅ Green — below pace
else if utilization <= expectedConsumption + 5:
    status = .borderline  // ⚠️ Orange — roughly on pace
else:
    status = .exceeding   // 🚨 Red — above pace
```

## Development Setup

### Prerequisites

```bash
# Install Xcode Command Line Tools (includes Swift compiler)
xcode-select --install

# Verify Swift installation
swift --version
```

### Building

```bash
# Development build
./build.sh

# Manual build with flags
swiftc ClaudeUsageApp.swift \
  -o build/ClaudeUsage.app/Contents/MacOS/ClaudeUsage \
  -framework Cocoa \
  -framework SwiftUI \
  -parse-as-library
```

### Running

```bash
# Run directly
open build/ClaudeUsage.app

# Run with console output (for debugging)
./build/ClaudeUsage.app/Contents/MacOS/ClaudeUsage

# With environment variable
CLAUDE_SESSION_KEY="your-key" ./build/ClaudeUsage.app/Contents/MacOS/ClaudeUsage
```

## Adding New Features

### Adding a New Metric

1. **Add to MetricType enum:**
```swift
enum MetricType: String, CaseIterable {
    case newMetric = "Display Name"
}
```

2. **Update getSelectedMetricData():**
```swift
case .newMetric:
    guard let limit = data.new_metric else { return nil }
    return (limit.utilization, limit.resets_at, "Display Name")
```

3. **Add menu item in showMenu():**
```swift
if let newMetric = data.new_metric {
    let item = NSMenuItem(
        title: "\(formatUtilization(newMetric.utilization))% Display Name",
        action: currentMetric == .newMetric ? nil : #selector(switchToNewMetric),
        keyEquivalent: ""
    )
    if currentMetric == .newMetric {
        item.state = .on
    }
    menu.addItem(item)
    menu.addItem(NSMenuItem(title: "  Resets \(formatRelativeDate(newMetric.resets_at))", action: nil, keyEquivalent: ""))
    menu.addItem(NSMenuItem.separator())
}
```

4. **Add switch action:**
```swift
@objc func switchToNewMetric() {
    Preferences.shared.selectedMetric = .newMetric
    updateMenuBarIcon()
}
```

### Changing Refresh Interval

```swift
// In applicationDidFinishLaunching()
timer = Timer.scheduledTimer(
    withTimeInterval: 30,  // Change this (in seconds) — currently 30s
    repeats: true
) { [weak self] _ in
    self?.fetchUsageData()
}
```

### Modifying Icon Logic

Edit `updateMenuBarIcon()` function to change:
- Icon selection logic
- Pace calculation thresholds
- Fallback behavior

### Customizing UI

**Settings Window:**
```swift
// In SettingsWindowController init()
contentRect: NSRect(x: 0, y: 0, width: 520, height: 580)  // Adjust size
```

**Settings View Layout:**
```swift
// In SettingsView body
VStack(alignment: .leading, spacing: 20) {  // Adjust spacing
    // Modify UI elements here
}
```

## Debugging

### Console Logging

```swift
// Add debug prints
print("Debug: utilization = \(utilization)")
print("Debug: expectedConsumption = \(expectedConsumption)")

// View logs in Console.app or terminal
./build/ClaudeUsage.app/Contents/MacOS/ClaudeUsage
```

### Common Issues

**Widget not updating:**
- Check `updateMenuBarIcon()` is being called (also updates widget)
- Verify `usageData` is populated
- Check date parsing in `formatRelativeDate()`

**Widget shows "Session Expired":**
- API returned HTTP 401 or 403 with a JSON response (real auth error, not Cloudflare)
- Session key has expired — user needs to re-extract from browser cookies
- Org ID never expires — no need to re-enter
- Once expired, polling pauses (`isSessionExpired = true`) — save new credentials in Settings to resume

**Cloudflare blocking `curl` but not the app:**
- `curl` may get a 403 HTML challenge page from Cloudflare — this is NOT a session expiry
- The app's `URLSession` usually passes through Cloudflare without issues
- Both the app and `setup.sh` detect Cloudflare challenges by checking the response body for markers

**API errors:**
- Verify session key is valid (they expire periodically)
- Check network connectivity
- Inspect response data structure

**Settings not persisting:**
- Check UserDefaults write permissions
- Verify `Preferences.shared` calls
- Look for errors in Console.app

### Testing Changes

1. Make code changes
2. Rebuild: `./build.sh`
3. Kill existing instance: `killall ClaudeUsage`
4. Run: `open build/ClaudeUsage.app`
5. Check desktop widget for updates

## File Structure

```
Claude-Usage-Mac-Widget/
├── ClaudeUsageApp.swift    - Main application code (single file, ~1420 lines)
├── Info.plist              - App bundle configuration (LSUIElement = true)
├── build.sh                - Build script
├── run.sh                  - Run script with environment check
├── setup.sh                - Interactive credential setup (CLI)
├── generate-icon.sh        - App icon generator
├── create-dmg.sh           - DMG packaging script
├── icon.svg                - Source icon
├── VERSION                 - Version string for update checking (bumped per material release)
├── README.md               - User documentation
├── DEVELOPMENT.md          - This file
├── CLAUDE.md               - Claude Code guidance
├── assets/                 - Widget screenshots for README
│   ├── widget-on-track.png - Widget screenshot (green state)
│   └── widget-limit-reached.png - Widget screenshot (limit reached)
└── build/                  - Build output directory
    └── ClaudeUsage.app/    - Built application bundle
```

## Code Organization

### Sections in ClaudeUsageApp.swift

1. **MetricType Enum** — Available metrics (5-hour, 7-day, Sonnet)
2. **Display Style Enums** — NumberDisplayStyle, ProgressIconStyle
3. **LoginItemManager** — Launch at Login via `SMAppService` (macOS 13+ native API)
4. **UpdateChecker** — Fetches remote VERSION from GitHub, compares semver, handles self-update (git pull → build → relaunch)
5. **Preferences Manager** — UserDefaults wrapper for all settings
6. **SettingsWindowController** — NSWindowController for Settings
7. **SettingsView (SwiftUI)** — Settings UI with credential hints and update banner
8. **FloatingWidgetPanel** — Borderless NSPanel subclass
9. **WidgetState Enum** — ok, needsSetup, sessionExpired, loading
10. **WidgetViewData** — Data container for widget display (includes multi-limit awareness fields)
11. **WidgetView (SwiftUI)** — Four-state widget with context menu, status messages, other-limits note, blue update dot
12. **WidgetPanelController** — Widget lifecycle, position/visibility persistence
13. **AppDelegate** — App lifecycle, data fetching, 30s timer, 24h update checker, credential management
14. **Data Models** — UsageResponse, UsageLimit (Codable)
15. **Main Entry Point** — NSApplication bootstrap

## Performance Considerations

- **API calls**: Every 30 seconds (~1KB response)
- **Memory**: Minimal — only stores current usage data
- **CPU**: Negligible — only active during API calls and UI updates
- **Network**: ~1KB every 30 seconds (~2.8MB/day)

## Security Notes

- Session key stored in UserDefaults (not encrypted)
- No data sent to third parties
- Only communicates with claude.ai API
- Custom `User-Agent` header sent with all requests to reduce Cloudflare challenges
- `setup.sh` uses masked input (`read -s`) — session key never echoed or logged
- For production: Consider using Keychain for session key storage

## Future Enhancement Ideas

- Keychain integration for secure session key storage
- macOS notifications when approaching limits
- Usage history tracking and charts
- Multiple organization support
- Configurable refresh interval in UI
- Export usage data to CSV/JSON

## Building for Distribution

```bash
# Code signing (requires Apple Developer account)
codesign --force --deep --sign "Developer ID Application: Your Name" \
  build/ClaudeUsage.app

# Create DMG for distribution
hdiutil create -volname "Claude Usage" -srcfolder build/ClaudeUsage.app \
  -ov -format UDZO ClaudeUsage.dmg
```

## Contributing

When making changes:
1. Test all metric types (5-hour, 7-day, Sonnet)
2. Verify settings persistence (quit and relaunch)
3. Check widget updates correctly with live data
4. Test with invalid/missing session keys (should show "Setup Needed")
5. Test with expired session key (should show "Session Expired" with red border, polling should pause)
6. Test that saving new credentials in Settings resumes polling after session expiry
7. Test right-click context menu (Settings, Refresh, Quit)
8. Test widget drag and position persistence
9. Verify Cloudflare 403s are retried (not treated as session expiry) — check logs for "Cloudflare challenge detected"
10. Update this documentation if adding features
