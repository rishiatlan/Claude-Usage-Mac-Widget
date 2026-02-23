# Claude Usage Menubar App

> 🤖 Built by Claude, for Claude

A simple macOS menubar application that displays your Claude API usage limits in real-time.

## Features

- **Smart Usage Indicators**: Shows usage with intelligent status icons that compare your actual usage to expected usage based on time elapsed:
  - ✳️ On track (more than 5% under expected)
  - 🚀 Borderline (within ±5% of expected)
  - ⚠️ Exceeding (more than 5% over expected)
- **Configurable Display**: Mix and match display elements:
  - Number: Percentage (`42%`), Threshold (`42|85` showing current|expected), or None
  - Progress Icon: Circle (`◕`), Braille (`⣇`), or multiple bar styles:
    - `[===  ]` ASCII
    - `▓▓░░░` Blocks
    - `■■□□□` Squares
    - `●●○○○` Circles
    - `━━───` Lines
  - Status Emoji: toggle ✳️ 🚀 ⚠️ on/off
- **Multiple Metrics**: Switch between different usage limits in the dropdown menu:
  - 5-hour Limit
  - 7-day Limit (All Models)
  - 7-day Limit (Sonnet)
- **Launch at Login**: Option to automatically start the app when you log in
- **Relative Time Display**: Shows "Resets in 4h 23m" instead of absolute timestamps
- **Settings Window**: Configure your Claude session key, display preferences, and startup behavior
- **Auto-refresh**: Updates every 5 minutes
- **Persistent Settings**: Session key and preferences saved securely in macOS UserDefaults

## Quick Start

### Option 1: Download Pre-built App (Recommended)

1. Download the latest release from the [Releases](../../releases) page
2. Download `ClaudeUsage.dmg`
3. Open the DMG and drag `ClaudeUsage.app` to your Applications folder
4. Launch from Applications
5. Click the menubar icon and select "Settings..."
6. Enter your Claude session key (see below)

### Option 2: Build from Source

```bash
# Make scripts executable and build
chmod +x build.sh run.sh create-dmg.sh generate-icon.sh
./build.sh

# Launch the app
open build/ClaudeUsage.app

# Configure settings
# 1. Click the menubar icon
# 2. Select "Settings..."
# 3. Enter your Claude session key
# 4. Choose which metric to display in the menubar
# 5. Click "Save"
```

## Getting Your Session Key

1. Open [claude.ai](https://claude.ai) in your browser
2. Open Developer Tools (Cmd+Option+I or F12)
3. Go to **Application** > **Cookies** > `https://claude.ai`
4. Find and copy the value of the `sessionKey` cookie
5. Paste it into the Settings window

## Usage

**Menubar Icon**: Shows your selected metric's usage with configurable display:
- Examples: `✳️ 19%`, `🚀 ◑`, `⚠️ ⣧`, `|███░░|`
- The status icon compares your actual usage to expected usage for time elapsed

**Dropdown Menu**:
- Lists all available metrics with usage percentages and reset times
- Click any metric to switch to displaying it in the menubar
- The currently displayed metric shows a checkmark
- Access Settings, Refresh data manually, or Quit the app

**Settings Window**:
- Session Key & Organization ID for authentication
- Display Metric selection
- Show Percentage toggle
- Progress Icon: None, Circle, Braille, or Bar
- Show Status Emoji toggle
- Launch at Login toggle

**Keyboard Shortcuts**:
- `Cmd+,` - Open Settings
- `Cmd+R` - Refresh data
- `Cmd+Q` - Quit app

## How Smart Usage Indicators Work

The app doesn't just show your raw usage percentage. It's smarter than that:

**Example**: If you're 3 hours into a 5-hour limit:
- Expected usage: ~60% (3/5 hours elapsed)
- If you're at 45% actual usage: ✳️ (more than 5% under pace, you're good!)
- If you're at 62% actual usage: 🚀 (within ±5% of expected, borderline)
- If you're at 80% actual usage: ⚠️ (more than 5% over pace, slow down!)

This helps you understand not just "how much have I used" but "am I on track for the rest of this period?"

## Settings Storage

Settings are stored in macOS UserDefaults:
- Session key & Organization ID: Stored in your user preferences
- Selected metric: Persists between app launches
- Display preferences: Show percentage, progress icon style, show status emoji
- Launch at Login: Managed via macOS Login Items
- Falls back to `CLAUDE_SESSION_KEY` and `CLAUDE_ORGANIZATION_ID` environment variables if not set in Settings

## Requirements

- macOS 13.0 or later
- Xcode Command Line Tools (for building from source)

## Building from Source

```bash
# Build
./build.sh

# Run
open build/ClaudeUsage.app

# Or use the run script (checks for environment variable fallback)
./run.sh
```

## Creating a DMG for Distribution

```bash
# Build the app first
./build.sh

# Create DMG
./create-dmg.sh
```

The DMG will be created at `build/ClaudeUsage.dmg`.

## Manual Build

```bash
swiftc ClaudeUsageApp.swift \
  -o build/ClaudeUsage.app/Contents/MacOS/ClaudeUsage \
  -framework Cocoa \
  -framework SwiftUI \
  -parse-as-library
```

## Automated Builds

### Continuous Integration

Every commit to the `main` branch automatically:
- Builds the app
- Creates a DMG file
- Uploads it as a workflow artifact (available for 30 days)

Download the artifact from: **Actions tab → Click the workflow run → Artifacts section**

### Creating a Release

To publish an official release to GitHub:

1. Commit your changes and push to main:
   ```bash
   git add .
   git commit -m "Your changes"
   git push origin main
   ```

2. Create and push a version tag:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

3. GitHub Actions will automatically:
   - Build the app
   - Create a DMG file
   - Publish a new GitHub Release with the DMG attached

You can also trigger builds manually from the **Actions** tab → **Build and Release** → **Run workflow**

## Troubleshooting

**App shows ❌ icon**:
- Session key not configured or invalid
- Open Settings and enter a valid session key

**No data shown**:
- Check network connectivity
- Verify session key is current (they expire periodically)
- Check Console.app for error messages

**Settings not saving**:
- Make sure you click the "Save" button
- Check file permissions for ~/Library/Preferences/

## Privacy

- Session key is stored locally in macOS UserDefaults
- No data is sent anywhere except to claude.ai API
- App only requests usage data from your Claude organization
