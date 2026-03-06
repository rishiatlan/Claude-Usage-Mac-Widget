# Changelog

All notable changes to Claude Usage Mac Widget are documented here.

---

## [1.3] — 2026-03-06

### Fixed
- **Keychain prompt on every refresh** — session key now saved with `SecAccessCreate` open ACL so any process (including after rebuilds) can read it without a macOS password dialog. "Always Allow" is no longer needed.
- **False "Update Available" banner** — `Info.plist` version was hardcoded and drifted from `VERSION`. `build.sh` now injects the version from `VERSION` via `PlistBuddy` at build time. `Info.plist` is a template (`0.0`) and is never manually edited.

### Security
- **Ad-hoc code signing** — `build.sh` now runs `codesign --force --sign -` after every build, giving the binary a stable identity so keychain ACL entries survive rebuilds.
- **Log file rotation** — `app.log` now rotates at 1 MB (moved to `app.log.1`) to prevent unbounded disk usage.
- **Manual refresh throttle** — Refresh button now enforces a 5-second minimum between API calls to avoid hammering the server.
- **Cloudflare cooldown safety** — cooldown expiry is now capped at 24 hours to prevent permanent polling freeze if system clock regresses.
- **NotificationCenter observer cleanup** — `WidgetPanelController` stores the `moveObserver` token and removes it in `deinit`, preventing observer accumulation on panel recreation.

### Docs
- `SECURITY.md` added — GitHub Security Advisories for private disclosure, no email.
- `CHANGELOG.md` added — this file.
- `CLAUDE.md` updated to reflect open ACL, build pipeline, updated line count.
- `README.md` — corrected 3 stale `rishiatlan` URLs to `rishi-banerjee1`; updated Keychain security row.

---

## [1.2] — 2026-02-26

### Added
- **Compact mode** — double-click or right-click → Compact to shrink to a frameless 76×76 ring. Background fades in on hover. State persists across relaunches.
- Improved install documentation — three clear paths (curl one-liner, Releases download, build from source).

---

## [1.1] — 2026-02-26

### Added
- Widget-only mode — no dock icon, no menubar icon. Floats on desktop across all Spaces.
- Session expiry detection — red border alert when credentials expire.
- Cloudflare-aware — distinguishes Cloudflare 403 challenge pages from real auth errors.
- Multi-limit display — shows all limits simultaneously (5h, 7d, Sonnet).
- Self-update — checks GitHub every 24h, one-click update via Settings.

### Security
- Session key migrated from `UserDefaults` to macOS Keychain (`SecItemAdd`).
- `setup.sh` input masked (`read -s`), credentials never logged.

---

## [1.0] — Initial Release

- Floating macOS desktop widget showing Claude API usage.
- Live progress ring with usage %, pace tracking, reset countdown.
- 30-second auto-refresh with exponential backoff retry.
- Settings panel with session key + org ID entry.
- Launch at Login via `SMAppService` (enabled by default).
