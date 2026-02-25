import Cocoa
import SwiftUI
import ServiceManagement

// MARK: - Metric Type Enum

enum MetricType: String, CaseIterable {
    case fiveHour = "5-hour Limit"
    case sevenDay = "7-day Limit (All Models)"
    case sevenDaySonnet = "7-day Limit (Sonnet)"

    var displayName: String { rawValue }

    var shortLabel: String {
        switch self {
        case .fiveHour: return "5h window"
        case .sevenDay: return "7d window"
        case .sevenDaySonnet: return "Sonnet 7d"
        }
    }
}

// MARK: - Display Style Enums

enum NumberDisplayStyle: String, CaseIterable {
    case none = "None"
    case percentage = "Percentage (42%)"
    case threshold = "Threshold (42|85)"

    var displayName: String { rawValue }
}

enum ProgressIconStyle: String, CaseIterable {
    case none = "None"
    case circle = "Circle (◕)"
    case braille = "Braille (⣇)"
    case barAscii = "Bar [===  ]"
    case barBlocks = "Bar ▓▓░░░"
    case barSquares = "Bar ■■□□□"
    case barCircles = "Bar ●●○○○"
    case barLines = "Bar ━━───"

    var displayName: String { rawValue }
}

// MARK: - Login Item Manager

class LoginItemManager {
    static let shared = LoginItemManager()

    /// Uses SMAppService (macOS 13+) — no AppleScript, no special permissions required.
    var isLoginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("LoginItemManager: failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    }
}

// MARK: - Update Checker

class UpdateChecker {
    static let shared = UpdateChecker()
    private let remoteVersionURL = "https://raw.githubusercontent.com/rishiatlan/Claude-Usage-Mac-Widget/main/VERSION"
    private let defaults = UserDefaults.standard
    private let lastCheckKey = "lastUpdateCheckDate"
    private let dismissedVersionKey = "dismissedUpdateVersion"

    /// True when a newer version is available on GitHub
    var updateAvailable: Bool = false
    /// The remote version string (e.g., "1.1")
    var remoteVersion: String?
    /// Whether an update is currently in progress
    var isUpdating: Bool = false

    var localVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    /// Derives the git repo root from the running app's bundle path.
    /// Expects: /path/to/repo/build/ClaudeUsage.app → /path/to/repo
    var repoRoot: String? {
        let bundlePath = Bundle.main.bundlePath // .../build/ClaudeUsage.app
        let buildDir = (bundlePath as NSString).deletingLastPathComponent // .../build
        let repoRoot = (buildDir as NSString).deletingLastPathComponent // .../repo
        // Validate: build.sh should exist at repo root
        if FileManager.default.fileExists(atPath: (repoRoot as NSString).appendingPathComponent("build.sh")) {
            return repoRoot
        }
        return nil
    }

    /// Check interval: 24 hours
    private let checkInterval: TimeInterval = 86400

    /// Whether enough time has passed since last check
    var shouldCheck: Bool {
        guard let lastCheck = defaults.object(forKey: lastCheckKey) as? Date else { return true }
        return Date().timeIntervalSince(lastCheck) >= checkInterval
    }

    /// Fetch remote VERSION and compare against local. Calls completion on main thread.
    func checkForUpdate(completion: (() -> Void)? = nil) {
        guard let url = URL(string: remoteVersionURL) else {
            print("UpdateChecker: invalid URL")
            completion?()
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        print("UpdateChecker: checking \(remoteVersionURL) (local: \(localVersion))")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            defer {
                DispatchQueue.main.async { completion?() }
            }

            if let error = error {
                print("UpdateChecker: network error: \(error.localizedDescription)")
                return
            }

            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse else {
                print("UpdateChecker: no data or response")
                return
            }

            guard httpResponse.statusCode == 200 else {
                print("UpdateChecker: HTTP \(httpResponse.statusCode)")
                return
            }

            guard let remote = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !remote.isEmpty else {
                print("UpdateChecker: empty or unreadable response")
                return
            }

            let newer = self.isNewer(remote: remote, local: self.localVersion)
            print("UpdateChecker: remote=\(remote) local=\(self.localVersion) newer=\(newer)")

            DispatchQueue.main.async {
                self.defaults.set(Date(), forKey: self.lastCheckKey)
                self.remoteVersion = remote
                self.updateAvailable = newer
            }
        }.resume()
    }

    /// Simple version comparison: "1.1" > "1.0", "2.0" > "1.9", etc.
    private func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    /// Perform self-update: git pull → build.sh → relaunch
    func performUpdate(log: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        guard let repoRoot = repoRoot else {
            completion(false, "Cannot locate git repo. Run from the cloned repo's build/ directory.")
            return
        }

        isUpdating = true
        log("Starting update...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Step 1: git pull
            log("Pulling latest from GitHub...")
            let (pullOk, pullOutput) = self?.runShell("cd \"\(repoRoot)\" && git pull origin main 2>&1") ?? (false, "")
            if !pullOk {
                DispatchQueue.main.async {
                    self?.isUpdating = false
                    completion(false, "git pull failed: \(pullOutput)")
                }
                return
            }
            log("Pull complete")

            // Step 2: build
            log("Building new version...")
            let (buildOk, buildOutput) = self?.runShell("cd \"\(repoRoot)\" && ./build.sh 2>&1") ?? (false, "")
            if !buildOk || !buildOutput.contains("Build successful") {
                DispatchQueue.main.async {
                    self?.isUpdating = false
                    completion(false, "Build failed: \(String(buildOutput.suffix(200)))")
                }
                return
            }
            log("Build complete — relaunching...")

            // Step 3: relaunch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let appPath = repoRoot + "/build/ClaudeUsage.app"
                let url = URL(fileURLWithPath: appPath)
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error = error {
                        self?.isUpdating = false
                        completion(false, "Relaunch failed: \(error.localizedDescription)")
                    } else {
                        // New instance launched — terminate this one
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                }
            }
        }
    }

    private func runShell(_ command: String) -> (Bool, String) {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.launchPath = "/bin/zsh"
        process.arguments = ["-c", command]
        process.launch()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus == 0, output)
    }
}

// MARK: - Preferences Manager

class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    private let sessionKeyKey = "claudeSessionKey"
    private let organizationIdKey = "claudeOrganizationId"
    private let metricTypeKey = "selectedMetricType"
    private let numberDisplayStyleKey = "numberDisplayStyle"
    private let progressIconStyleKey = "progressIconStyle"
    private let showStatusEmojiKey = "showStatusEmoji"
    private let launchAtLoginConfiguredKey = "launchAtLoginConfigured"

    var sessionKey: String? {
        get { defaults.string(forKey: sessionKeyKey) }
        set { defaults.set(newValue, forKey: sessionKeyKey) }
    }

    var organizationId: String? {
        get { defaults.string(forKey: organizationIdKey) }
        set { defaults.set(newValue, forKey: organizationIdKey) }
    }

    var selectedMetric: MetricType {
        get {
            if let rawValue = defaults.string(forKey: metricTypeKey),
               let metric = MetricType(rawValue: rawValue) {
                return metric
            }
            return .sevenDay
        }
        set {
            defaults.set(newValue.rawValue, forKey: metricTypeKey)
        }
    }

    var numberDisplayStyle: NumberDisplayStyle {
        get {
            if let rawValue = defaults.string(forKey: numberDisplayStyleKey),
               let style = NumberDisplayStyle(rawValue: rawValue) {
                return style
            }
            return .percentage // default to showing percentage
        }
        set {
            defaults.set(newValue.rawValue, forKey: numberDisplayStyleKey)
        }
    }

    var progressIconStyle: ProgressIconStyle {
        get {
            if let rawValue = defaults.string(forKey: progressIconStyleKey),
               let style = ProgressIconStyle(rawValue: rawValue) {
                return style
            }
            return .none
        }
        set {
            defaults.set(newValue.rawValue, forKey: progressIconStyleKey)
        }
    }

    var showStatusEmoji: Bool {
        get {
            if defaults.object(forKey: showStatusEmojiKey) == nil {
                return true // default to showing emoji
            }
            return defaults.bool(forKey: showStatusEmojiKey)
        }
        set {
            defaults.set(newValue, forKey: showStatusEmojiKey)
        }
    }

    /// Tracks whether Launch at Login has been configured for this install.
    /// False on first run → app auto-enables it. User can toggle it off in Settings afterwards.
    var launchAtLoginConfigured: Bool {
        get { defaults.bool(forKey: launchAtLoginConfiguredKey) }
        set { defaults.set(newValue, forKey: launchAtLoginConfiguredKey) }
    }
}

// MARK: - Settings Window Controller

class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()

        self.init(window: window)

        let settingsView = SettingsView { [weak self] in
            self?.close()
        }
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView
    }
}

struct SettingsView: View {
    let onClose: () -> Void

    @State private var selectedTab = 0
    @State private var sessionKey: String = Preferences.shared.sessionKey ?? ""
    @State private var organizationId: String = Preferences.shared.organizationId ?? ""
    @State private var selectedMetric: MetricType = Preferences.shared.selectedMetric
    @State private var numberDisplayStyle: NumberDisplayStyle = Preferences.shared.numberDisplayStyle
    @State private var progressIconStyle: ProgressIconStyle = Preferences.shared.progressIconStyle
    @State private var showStatusEmoji: Bool = Preferences.shared.showStatusEmoji
    @State private var launchAtLogin: Bool = LoginItemManager.shared.isLoginItemEnabled
    @State private var logText: String = ""
    @State private var updateStatus: String = ""
    @State private var isUpdating: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            settingsTab
                .tabItem { Text("Settings") }
                .tag(0)
            logTab
                .tabItem { Text("Log") }
                .tag(1)
        }
        .frame(width: 520, height: 580)
    }

    var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if UpdateChecker.shared.updateAvailable, let remote = UpdateChecker.shared.remoteVersion {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update available: v\(remote)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            if !updateStatus.isEmpty {
                                Text(updateStatus)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        Spacer()
                        if isUpdating {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(.circular)
                        } else {
                            Button("Update Now") {
                                isUpdating = true
                                updateStatus = "Starting..."
                                UpdateChecker.shared.performUpdate(
                                    log: { msg in
                                        DispatchQueue.main.async { updateStatus = msg }
                                    },
                                    completion: { success, message in
                                        DispatchQueue.main.async {
                                            isUpdating = false
                                            updateStatus = success ? "Done!" : message
                                        }
                                    }
                                )
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue))
                    .padding(.bottom, 4)
                }

                Text("Claude Usage Settings")
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Session Key:")
                        .font(.headline)

                    TextField("Enter your Claude session key", text: $sessionKey)
                        .textFieldStyle(.roundedBorder)

                    Text("Browser → DevTools (Cmd+Opt+I) → Application → Cookies → claude.ai → sessionKey")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("⚠️ Session keys expire periodically. Re-extract from cookies if the widget stops updating.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Organization ID:")
                        .font(.headline)

                    TextField("Enter your organization ID", text: $organizationId)
                        .textFieldStyle(.roundedBorder)

                    Text("DevTools → Network → send any message → find URL containing /organizations/ → copy the UUID")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("✓ Org ID never expires. You only need to grab it once.")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Metric:")
                        .font(.headline)

                    Picker("", selection: $selectedMetric) {
                        ForEach(MetricType.allCases, id: \.self) { metric in
                            Text(metric.displayName).tag(metric)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Menu Bar Display")
                        .font(.headline)

                    HStack(alignment: .top, spacing: 30) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Number:")
                                .font(.subheadline)
                            Picker("", selection: $numberDisplayStyle) {
                                ForEach(NumberDisplayStyle.allCases, id: \.self) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Progress Icon:")
                                .font(.subheadline)
                            Picker("", selection: $progressIconStyle) {
                                ForEach(ProgressIconStyle.allCases, id: \.self) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                        }
                    }

                    Toggle("Show Status Emoji", isOn: $showStatusEmoji)
                        .toggleStyle(.checkbox)

                    Text("Status: ✳️ on track, 🚀 borderline, ⚠️ exceeding")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)

                Spacer()

                HStack {
                    Spacer()
                    Button("Save") {
                        Preferences.shared.sessionKey = sessionKey
                        Preferences.shared.organizationId = organizationId
                        Preferences.shared.selectedMetric = selectedMetric
                        Preferences.shared.numberDisplayStyle = numberDisplayStyle
                        Preferences.shared.progressIconStyle = progressIconStyle
                        Preferences.shared.showStatusEmoji = showStatusEmoji
                        LoginItemManager.shared.setLoginItemEnabled(launchAtLogin)

                        NotificationCenter.default.post(name: .settingsChanged, object: nil)

                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
    }

    var logTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Application Log")
                    .font(.headline)
                Spacer()
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }
                Button("Refresh") {
                    loadLog()
                }
            }

            TextEditor(text: .constant(logText))
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Log file: ~/.claude-usage/app.log")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .onAppear { loadLog() }
    }

    private func loadLog() {
        let path = AppDelegate.logFile
        if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
            logText = contents
        } else {
            logText = "(no log file found)"
        }
    }
}

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
}

// MARK: - Floating Widget Panel

class FloatingWidgetPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Widget View Data

struct WidgetViewData {
    let utilization: Double
    let expectedUsage: Double?
    let resetTimeString: String
    let metricName: String
    let metricShortLabel: String
    let status: AppDelegate.UsageStatus
    /// When selected metric is at 100%, shows other limits that still have capacity (e.g., "7d: 34%")
    let otherLimitsNote: String?
    /// True only when ALL metrics are at or near 100% — the user is actually blocked
    let allLimitsExhausted: Bool
}

enum WidgetState {
    case ok
    case needsSetup
    case sessionExpired
    case loading
}

// MARK: - Widget View

struct WidgetView: View {
    let data: WidgetViewData?
    let state: WidgetState
    var updateAvailable: Bool = false
    var onSettings: (() -> Void)? = nil
    var onRefresh: (() -> Void)? = nil
    var onQuit: (() -> Void)? = nil

    var body: some View {
        Group {
            switch state {
            case .needsSetup:
                setupView
            case .sessionExpired:
                sessionExpiredView
            case .ok:
                if let data = data {
                    dataView(data)
                } else {
                    loadingView
                }
            case .loading:
                loadingView
            }
        }
        .contextMenu {
            Button("Settings...") { onSettings?() }
            Button("Refresh") { onRefresh?() }
            Divider()
            Button("Quit") { onQuit?() }
        }
    }

    /// The ring color accounts for multi-limit context:
    /// - Red only when ALL limits are exhausted (user is actually blocked)
    /// - Orange when selected metric is full but others have room (still usable)
    /// - Otherwise uses the normal status color (green/orange/red based on pace)
    func ringColor(_ data: WidgetViewData) -> Color {
        if data.utilization >= 100 && !data.allLimitsExhausted {
            return .orange // "Caution" not "Blocked"
        }
        return statusColor(data.status)
    }

    func dataView(_ data: WidgetViewData) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(data.utilization / 100.0, 1.0))
                    .stroke(ringColor(data), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: data.utilization)

                VStack(spacing: 1) {
                    Text("\(Int(data.utilization))%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(data.metricName)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 76, height: 76)

            // When one window is full but Claude still works — show green "Still usable" badge
            if data.utilization >= 95 && !data.allLimitsExhausted && data.otherLimitsNote != nil {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                    Text("Still usable")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.green)

                if let note = data.otherLimitsNote {
                    Text(note)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text("\(data.metricShortLabel) resets \(data.resetTimeString)")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            } else {
                // Normal state — show reset time, status, and pace
                Text("\(data.metricShortLabel) resets \(data.resetTimeString)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(statusMessage(data))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(ringColor(data))

                if let expected = data.expectedUsage, data.utilization < 95 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor(data.status))
                            .frame(width: 6, height: 6)
                        Text("pace: \(Int(expected))%")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 140, height: 170)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            if updateAvailable {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .help("Update available — right-click → Settings to update")
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var setupView: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 24))
                .foregroundColor(.orange)
            Text("Setup Needed")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            Text("Right-click to\nopen Settings")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(width: 140, height: 170)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var sessionExpiredView: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.arrow.circlepath")
                .font(.system(size: 24))
                .foregroundColor(.red)
            Text("Session Expired")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            Text("Re-extract sessionKey\nfrom browser cookies")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Text("Right-click → Settings")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.orange)
        }
        .padding(12)
        .frame(width: 140, height: 170)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(width: 140, height: 170)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    func statusMessage(_ data: WidgetViewData) -> String {
        if data.utilization >= 100 {
            if data.allLimitsExhausted {
                return "All limits reached — wait for reset"
            }
            // Widget shows "Still usable" badge separately — keep this short
            return "This window recovering"
        }
        switch data.status {
        case .onTrack:
            if data.utilization < 30 {
                return "Plenty of room"
            }
            return "On track — you're good"
        case .borderline:
            return "On pace — be mindful"
        case .exceeding:
            if data.utilization >= 90 {
                return "Almost out — slow down"
            }
            return "Above pace — slow down"
        }
    }

    func statusColor(_ status: AppDelegate.UsageStatus) -> Color {
        switch status {
        case .onTrack: return .green
        case .borderline: return .orange
        case .exceeding: return .red
        }
    }
}

// MARK: - Widget Panel Controller

class WidgetPanelController {
    private var panel: FloatingWidgetPanel?
    private var hostingView: NSHostingView<WidgetView>?

    private let posXKey = "widgetPositionX"
    private let posYKey = "widgetPositionY"
    private let widgetVisibleKey = "widgetVisible"
    private let hasLaunchedKey = "hasLaunchedBefore"

    var onSettings: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show(with data: WidgetViewData?, state: WidgetState = .ok) {
        if panel == nil {
            createPanel()
        }
        updateContent(with: data, state: state)
        panel?.orderFront(nil)
        UserDefaults.standard.set(true, forKey: widgetVisibleKey)
    }

    func hide() {
        panel?.orderOut(nil)
        UserDefaults.standard.set(false, forKey: widgetVisibleKey)
    }

    func toggle(with data: WidgetViewData?, state: WidgetState = .ok) {
        if isVisible {
            hide()
        } else {
            show(with: data, state: state)
        }
    }

    func updateContent(with data: WidgetViewData?, state: WidgetState = .ok) {
        guard let hostingView = hostingView else { return }
        hostingView.rootView = WidgetView(
            data: data,
            state: state,
            updateAvailable: UpdateChecker.shared.updateAvailable,
            onSettings: onSettings,
            onRefresh: onRefresh,
            onQuit: onQuit
        )
    }

    var shouldRestoreOnLaunch: Bool {
        UserDefaults.standard.bool(forKey: widgetVisibleKey)
    }

    var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: hasLaunchedKey)
    }

    func markLaunched() {
        UserDefaults.standard.set(true, forKey: hasLaunchedKey)
    }

    private func createPanel() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let defaultX = screen.maxX - 150
        let defaultY = screen.minY + 20

        let savedX = UserDefaults.standard.object(forKey: posXKey) as? CGFloat
        let savedY = UserDefaults.standard.object(forKey: posYKey) as? CGFloat
        let x = savedX ?? defaultX
        let y = savedY ?? defaultY

        let rect = NSRect(x: x, y: y, width: 140, height: 170)
        panel = FloatingWidgetPanel(contentRect: rect)

        let widgetView = WidgetView(
            data: nil,
            state: .loading,
            updateAvailable: UpdateChecker.shared.updateAvailable,
            onSettings: onSettings,
            onRefresh: onRefresh,
            onQuit: onQuit
        )
        let hosting = NSHostingView(rootView: widgetView)
        hostingView = hosting
        panel?.contentView = hosting

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let frame = self.panel?.frame else { return }
            UserDefaults.standard.set(frame.origin.x, forKey: self.posXKey)
            UserDefaults.standard.set(frame.origin.y, forKey: self.posYKey)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var usageData: UsageResponse?
    var timer: Timer?
    var settingsWindowController: SettingsWindowController?
    var widgetController = WidgetPanelController()

    // Fetch reliability tracking
    var logEntries: [(Date, String)] = []
    var consecutiveFailures: Int = 0
    var isSessionExpired: Bool = false
    let maxRetries = 3
    let maxLogEntries = 50
    var updateCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        addLog("App launched")

        // Set up menubar icon (may be hidden on macOS 26+ but keep as fallback)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "⏱️"
            button.action = #selector(showMenu)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menu = NSMenu()

        // Wire up widget callbacks
        widgetController.onSettings = { [weak self] in self?.openSettings() }
        widgetController.onRefresh = { [weak self] in self?.fetchUsageData() }
        widgetController.onQuit = { NSApplication.shared.terminate(nil) }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .settingsChanged,
            object: nil
        )

        fetchUsageData()

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.fetchUsageData()
        }

        // Always show widget on launch — it IS the app
        let launchState: WidgetState = ((Preferences.shared.sessionKey ?? "").isEmpty || (Preferences.shared.organizationId ?? "").isEmpty) ? .needsSetup : .ok
        widgetController.show(with: currentWidgetData(), state: launchState)

        // Auto-open settings on first launch
        if widgetController.isFirstLaunch {
            widgetController.markLaunched()
            if launchState == .needsSetup {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.openSettings()
                }
            }
        }

        // Enable Launch at Login by default on first run (or first run after upgrade).
        // launchAtLoginConfigured stays false until we set it, so existing users get this once.
        // After that, whatever the user sets in Settings is respected — we never override it.
        if !Preferences.shared.launchAtLoginConfigured {
            LoginItemManager.shared.setLoginItemEnabled(true)
            Preferences.shared.launchAtLoginConfigured = true
            addLog("Launch at Login enabled by default")
        }

        // Check for updates on launch (if 24h since last check) and every 24 hours
        if UpdateChecker.shared.shouldCheck {
            UpdateChecker.shared.checkForUpdate { [weak self] in
                if UpdateChecker.shared.updateAvailable {
                    self?.addLog("Update available: v\(UpdateChecker.shared.remoteVersion ?? "?")")
                    self?.widgetController.updateContent(with: self?.currentWidgetData())
                }
            }
        }
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            UpdateChecker.shared.checkForUpdate {
                if UpdateChecker.shared.updateAvailable {
                    self?.addLog("Update available: v\(UpdateChecker.shared.remoteVersion ?? "?")")
                    self?.widgetController.updateContent(with: self?.currentWidgetData())
                }
            }
        }
    }

    @objc func handleSettingsChanged() {
        isSessionExpired = false  // Reset — user may have entered a new key
        consecutiveFailures = 0
        fetchUsageData()
    }

    @objc func showMenu() {
        menu.removeAllItems()

        let currentMetric = Preferences.shared.selectedMetric

        if let data = usageData {
            // 5-hour limit
            if let fiveHour = data.five_hour {
                let item = NSMenuItem(
                    title: "\(formatUtilization(fiveHour.utilization))% 5-hour Limit",
                    action: currentMetric == .fiveHour ? nil : #selector(switchToFiveHour),
                    keyEquivalent: ""
                )
                if currentMetric == .fiveHour {
                    item.state = .on
                }
                menu.addItem(item)
                menu.addItem(NSMenuItem(title: "  t: \(metricDetailString(limit: fiveHour, metric: .fiveHour))", action: nil, keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
            }

            // 7-day limit (all models)
            if let sevenDay = data.seven_day {
                let item = NSMenuItem(
                    title: "\(formatUtilization(sevenDay.utilization))% 7-day Limit (All Models)",
                    action: currentMetric == .sevenDay ? nil : #selector(switchToSevenDay),
                    keyEquivalent: ""
                )
                if currentMetric == .sevenDay {
                    item.state = .on
                }
                menu.addItem(item)
                menu.addItem(NSMenuItem(title: "  t: \(metricDetailString(limit: sevenDay, metric: .sevenDay))", action: nil, keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
            }

            // 7-day Sonnet
            if let sevenDaySonnet = data.seven_day_sonnet {
                let item = NSMenuItem(
                    title: "\(formatUtilization(sevenDaySonnet.utilization))% 7-day Limit (Sonnet)",
                    action: currentMetric == .sevenDaySonnet ? nil : #selector(switchToSevenDaySonnet),
                    keyEquivalent: ""
                )
                if currentMetric == .sevenDaySonnet {
                    item.state = .on
                }
                menu.addItem(item)
                menu.addItem(NSMenuItem(title: "  t: \(metricDetailString(limit: sevenDaySonnet, metric: .sevenDaySonnet))", action: nil, keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
            }

            // 7-day Opus (if available)
            if let sevenDayOpus = data.seven_day_opus {
                menu.addItem(NSMenuItem(title: "\(formatUtilization(sevenDayOpus.utilization))% 7-day Limit (Opus)", action: nil, keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "  t: \(metricDetailString(limit: sevenDayOpus, metric: .sevenDay))", action: nil, keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
            }
        } else {
            menu.addItem(NSMenuItem(title: "Loading...", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
        }

        // Log section
        let logItem = NSMenuItem(title: "Log", action: nil, keyEquivalent: "")
        let logSubmenu = NSMenu()
        if logEntries.isEmpty {
            logSubmenu.addItem(NSMenuItem(title: "No entries", action: nil, keyEquivalent: ""))
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let recentLogs = logEntries.suffix(15)
            for (date, message) in recentLogs {
                let title = "\(formatter.string(from: date)) \(message)"
                logSubmenu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
            }
        }
        logItem.submenu = logSubmenu
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())
        let widgetTitle = widgetController.isVisible ? "Hide Desktop Widget" : "Show Desktop Widget"
        menu.addItem(NSMenuItem(title: widgetTitle, action: #selector(toggleWidget), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshClicked), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func switchToFiveHour() {
        Preferences.shared.selectedMetric = .fiveHour
        updateMenuBarIcon()
    }

    func metricDetailString(limit: UsageLimit, metric: MetricType) -> String {
        guard let resetDate = limit.resets_at else {
            return "?%, —"
        }
        let expected = calculateExpectedUsage(resetDateString: resetDate, metric: metric)
        let expectedStr = expected != nil ? formatUtilization(expected!) : "?"
        return "\(expectedStr)%, \(formatResetTime(resetDate))"
    }

    @objc func switchToSevenDay() {
        Preferences.shared.selectedMetric = .sevenDay
        updateMenuBarIcon()
    }

    @objc func switchToSevenDaySonnet() {
        Preferences.shared.selectedMetric = .sevenDaySonnet
        updateMenuBarIcon()
    }

    @objc func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func refreshClicked() {
        fetchUsageData()
    }

    @objc func quitClicked() {
        NSApplication.shared.terminate(self)
    }

    @objc func toggleWidget() {
        widgetController.toggle(with: currentWidgetData())
    }

    func currentWidgetData() -> WidgetViewData? {
        guard let data = usageData else { return nil }
        let metric = Preferences.shared.selectedMetric
        guard let (utilization, resetDateString, name) = getSelectedMetricData(from: data, metric: metric) else { return nil }

        let status: UsageStatus
        let expectedUsage: Double?
        let resetTimeString: String

        if let resetDate = resetDateString {
            status = calculateStatus(utilization: utilization, resetDateString: resetDate, metric: metric)
            expectedUsage = calculateExpectedUsage(resetDateString: resetDate, metric: metric)
            resetTimeString = formatResetTime(resetDate)
        } else {
            status = utilization >= 80 ? .exceeding : (utilization >= 50 ? .borderline : .onTrack)
            expectedUsage = nil
            resetTimeString = "unknown"
        }

        // When selected metric is at/near 100%, check if other limits still have capacity
        var otherLimitsNote: String? = nil
        var allLimitsExhausted = false
        if utilization >= 95 {
            var otherParts: [String] = []
            var allHigh = true
            let limits: [(String, UsageLimit?)] = [
                ("5h", data.five_hour),
                ("7d", data.seven_day),
                ("sonnet", data.seven_day_sonnet),
                ("opus", data.seven_day_opus),
            ]
            for (label, limit) in limits {
                guard let l = limit else { continue }
                // Skip the metric we're already showing
                if (metric == .fiveHour && label == "5h") ||
                   (metric == .sevenDay && label == "7d") ||
                   (metric == .sevenDaySonnet && label == "sonnet") { continue }
                if l.utilization < 90 {
                    otherParts.append("\(label): \(Int(l.utilization))%")
                    allHigh = false
                }
            }
            if !otherParts.isEmpty {
                otherLimitsNote = otherParts.joined(separator: "  ")
            }
            allLimitsExhausted = allHigh && otherParts.isEmpty
        }

        return WidgetViewData(
            utilization: utilization,
            expectedUsage: expectedUsage,
            resetTimeString: resetTimeString,
            metricName: name,
            metricShortLabel: metric.shortLabel,
            status: status,
            otherLimitsNote: otherLimitsNote,
            allLimitsExhausted: allLimitsExhausted
        )
    }

    static let logDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/.claude-usage"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }()
    static let logFile: String = "\(logDir)/app.log"

    func addLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        DispatchQueue.main.async {
            let entry = (Date(), message)
            self.logEntries.append(entry)
            if self.logEntries.count > self.maxLogEntries {
                self.logEntries.removeFirst(self.logEntries.count - self.maxLogEntries)
            }
        }

        // Write to file
        let path = AppDelegate.logFile
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path) {
                if let handle = FileHandle(forWritingAtPath: path) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: path, contents: data, attributes: nil)
            }
        }
    }

    func fetchUsageData() {
        fetchUsageData(retryCount: 0)
    }

    private func fetchUsageData(retryCount: Int) {
        // Skip polling if session is expired — wait for user to update credentials via Settings
        if isSessionExpired && retryCount == 0 {
            return
        }

        var sessionKey = Preferences.shared.sessionKey
        var organizationId = Preferences.shared.organizationId

        if sessionKey == nil || sessionKey?.isEmpty == true {
            sessionKey = ProcessInfo.processInfo.environment["CLAUDE_SESSION_KEY"]
        }

        if organizationId == nil || organizationId?.isEmpty == true {
            organizationId = ProcessInfo.processInfo.environment["CLAUDE_ORGANIZATION_ID"]
        }

        guard let sessionKey = sessionKey, !sessionKey.isEmpty else {
            let msg = "No session key configured"
            addLog(msg)
            DispatchQueue.main.async {
                self.consecutiveFailures += 1
                self.statusItem.button?.title = "❌"
                if self.widgetController.isVisible {
                    self.widgetController.updateContent(with: nil, state: .needsSetup)
                }
            }
            return
        }

        guard let organizationId = organizationId, !organizationId.isEmpty else {
            let msg = "No organization ID configured"
            addLog(msg)
            DispatchQueue.main.async {
                self.consecutiveFailures += 1
                self.statusItem.button?.title = "❌"
                if self.widgetController.isVisible {
                    self.widgetController.updateContent(with: nil, state: .needsSetup)
                }
            }
            return
        }

        let urlString = "https://claude.ai/api/organizations/\(organizationId)/usage"
        guard let url = URL(string: urlString) else {
            addLog("Invalid URL: \(urlString)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.addValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ClaudeUsageWidget/1.0", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // Network error
            if let error = error {
                let msg = "Network error: \(error.localizedDescription)"
                self.addLog(msg)
                self.handleFetchFailure(retryCount: retryCount)
                return
            }

            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let msg = "HTTP \(httpResponse.statusCode) from API"
                self.addLog(msg)

                // 401/403 could be session expired OR a Cloudflare challenge
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    // Check if this is a Cloudflare challenge (HTML response) vs real auth error (JSON)
                    let isCloudflareChallenge: Bool
                    if let responseData = data,
                       let bodyStr = String(data: responseData, encoding: .utf8) {
                        // Cloudflare challenges return HTML with distinctive markers
                        isCloudflareChallenge = bodyStr.contains("Just a moment") ||
                                                bodyStr.contains("cf-browser-verification") ||
                                                bodyStr.contains("challenge-platform") ||
                                                bodyStr.contains("_cf_chl_opt")
                    } else {
                        isCloudflareChallenge = false
                    }

                    if isCloudflareChallenge {
                        // Cloudflare is blocking the request — treat as transient network error
                        self.addLog("Cloudflare challenge detected (HTTP \(httpResponse.statusCode)) — retrying")
                        self.handleFetchFailure(retryCount: retryCount)
                    } else {
                        // Real auth error — session expired
                        self.addLog("Session expired (HTTP \(httpResponse.statusCode))")
                        DispatchQueue.main.async {
                            self.consecutiveFailures += 1
                            self.isSessionExpired = true
                            self.statusItem.button?.title = "🔑"
                            if self.widgetController.isVisible {
                                self.widgetController.updateContent(with: nil, state: .sessionExpired)
                            }
                        }
                    }
                    return
                }

                self.handleFetchFailure(retryCount: retryCount)
                return
            }

            guard let data = data else {
                self.addLog("Empty response body")
                self.handleFetchFailure(retryCount: retryCount)
                return
            }

            do {
                let decoder = JSONDecoder()
                let usageData = try decoder.decode(UsageResponse.self, from: data)

                // Build diagnostic string with all limit values
                var parts: [String] = []
                if let h = usageData.five_hour {
                    parts.append("5h:\(String(format: "%.1f", h.utilization))%")
                }
                if let d = usageData.seven_day {
                    parts.append("7d:\(String(format: "%.1f", d.utilization))%")
                }
                if let s = usageData.seven_day_sonnet {
                    parts.append("sonnet:\(String(format: "%.1f", s.utilization))%")
                }
                if let o = usageData.seven_day_opus {
                    parts.append("opus:\(String(format: "%.1f", o.utilization))%")
                }
                if let e = usageData.extra_usage {
                    parts.append("extra:\(String(format: "%.1f", e.utilization))%")
                }
                let summary = parts.isEmpty ? "no limits" : parts.joined(separator: " | ")

                DispatchQueue.main.async {
                    self.consecutiveFailures = 0
                    self.isSessionExpired = false
                    self.usageData = usageData
                    self.updateMenuBarIcon()
                    self.addLog("Fetch OK — \(summary)")
                }
            } catch {
                let body = String(data: data, encoding: .utf8) ?? "<binary>"
                let preview = String(body.prefix(200))
                self.addLog("JSON decode error: \(error) | body: \(preview)")
                self.handleFetchFailure(retryCount: retryCount)
            }
        }

        task.resume()
    }

    private func handleFetchFailure(retryCount: Int) {
        if retryCount < maxRetries {
            let delay = pow(2.0, Double(retryCount)) // 1s, 2s, 4s
            addLog("Retrying in \(Int(delay))s (attempt \(retryCount + 1)/\(maxRetries))")
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.fetchUsageData(retryCount: retryCount + 1)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.consecutiveFailures += 1
                self.addLog("Failed after \(self.maxRetries) retries (consecutive: \(self.consecutiveFailures))")
                if self.consecutiveFailures >= 3 {
                    self.statusItem.button?.title = "❌"
                }
            }
        }
    }

    func getSelectedMetricData(from data: UsageResponse, metric: MetricType) -> (Double, String?, String)? {
        switch metric {
        case .fiveHour:
            guard let limit = data.five_hour else { return nil }
            return (limit.utilization, limit.resets_at, "5-hour Limit")
        case .sevenDay:
            guard let limit = data.seven_day else { return nil }
            return (limit.utilization, limit.resets_at, "7-day Limit")
        case .sevenDaySonnet:
            guard let limit = data.seven_day_sonnet else { return nil }
            return (limit.utilization, limit.resets_at, "7-day Sonnet")
        }
    }

    func updateMenuBarIcon() {
        guard let data = usageData,
              let button = statusItem.button else { return }

        let metric = Preferences.shared.selectedMetric
        let numberDisplayStyle = Preferences.shared.numberDisplayStyle
        let progressIconStyle = Preferences.shared.progressIconStyle
        let showStatusEmoji = Preferences.shared.showStatusEmoji

        guard let (utilization, resetDateString, _) = getSelectedMetricData(from: data, metric: metric) else {
            button.title = "❌"
            return
        }

        // Calculate status and expected usage
        let status: UsageStatus
        let expectedUsage: Double?
        if let resetDate = resetDateString {
            status = calculateStatus(utilization: utilization, resetDateString: resetDate, metric: metric)
            expectedUsage = calculateExpectedUsage(resetDateString: resetDate, metric: metric)
        } else {
            status = utilization >= 80 ? .exceeding : (utilization >= 50 ? .borderline : .onTrack)
            expectedUsage = nil
        }

        // Build the display string
        var displayParts: [String] = []

        // Add status emoji if enabled
        if showStatusEmoji {
            displayParts.append(getStatusIcon(for: status))
        }

        // Add number display based on style
        switch numberDisplayStyle {
        case .none:
            break
        case .percentage:
            displayParts.append("\(formatUtilization(utilization))%")
        case .threshold:
            let expectedStr = expectedUsage != nil ? formatUtilization(expectedUsage!) : "?"
            displayParts.append("\(formatUtilization(utilization))|\(expectedStr)")
        }

        // Add progress icon based on style
        switch progressIconStyle {
        case .none:
            break
        case .circle:
            displayParts.append(getCircleIcon(for: utilization))
        case .braille:
            displayParts.append(getBrailleIcon(for: utilization))
        case .barAscii:
            displayParts.append(getProgressBar(for: utilization, filled: "=", empty: " ", prefix: "[", suffix: "]"))
        case .barBlocks:
            displayParts.append(getProgressBar(for: utilization, filled: "▓", empty: "░", prefix: "", suffix: ""))
        case .barSquares:
            displayParts.append(getProgressBar(for: utilization, filled: "■", empty: "□", prefix: "", suffix: ""))
        case .barCircles:
            displayParts.append(getProgressBar(for: utilization, filled: "●", empty: "○", prefix: "", suffix: ""))
        case .barLines:
            displayParts.append(getProgressBar(for: utilization, filled: "━", empty: "─", prefix: "", suffix: ""))
        }

        // Fallback if nothing is selected
        if displayParts.isEmpty {
            displayParts.append("\(formatUtilization(utilization))%")
        }

        button.title = displayParts.joined(separator: " ")

        // Update desktop widget
        if widgetController.isVisible {
            widgetController.updateContent(with: currentWidgetData(), state: .ok)
        }
    }

    enum UsageStatus {
        case onTrack
        case borderline
        case exceeding
    }

    func calculateStatus(utilization: Double, resetDateString: String, metric: MetricType) -> UsageStatus {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let resetDate = formatter.date(from: resetDateString) else {
            // Fallback to simple threshold-based status
            if utilization >= 80 { return .exceeding }
            else if utilization >= 50 { return .borderline }
            else { return .onTrack }
        }

        let windowDuration: TimeInterval
        switch metric {
        case .fiveHour:
            windowDuration = 5 * 3600
        case .sevenDay, .sevenDaySonnet:
            windowDuration = 7 * 24 * 3600
        }

        let now = Date()
        let timeRemaining = resetDate.timeIntervalSince(now)

        guard timeRemaining > 0 && timeRemaining <= windowDuration else {
            if utilization >= 80 { return .exceeding }
            else if utilization >= 50 { return .borderline }
            else { return .onTrack }
        }

        let timeElapsed = windowDuration - timeRemaining
        let expectedConsumption = (timeElapsed / windowDuration) * 100.0

        if utilization < expectedConsumption - 5 {
            return .onTrack
        } else if utilization <= expectedConsumption + 5 {
            return .borderline
        } else {
            return .exceeding
        }
    }

    func getStatusIcon(for status: UsageStatus) -> String {
        switch status {
        case .onTrack: return "✳️"
        case .borderline: return "🚀"
        case .exceeding: return "⚠️"
        }
    }

    func getCircleIcon(for utilization: Double) -> String {
        // ○ ◔ ◑ ◕ ●
        if utilization < 12.5 { return "○" }
        else if utilization < 37.5 { return "◔" }
        else if utilization < 62.5 { return "◑" }
        else if utilization < 87.5 { return "◕" }
        else { return "●" }
    }

    func getBrailleIcon(for utilization: Double) -> String {
        // ⠀ ⠁ ⠃ ⠇ ⡇ ⣇ ⣧ ⣿
        if utilization < 12.5 { return "⠀" }
        else if utilization < 25 { return "⠁" }
        else if utilization < 37.5 { return "⠃" }
        else if utilization < 50 { return "⠇" }
        else if utilization < 62.5 { return "⡇" }
        else if utilization < 75 { return "⣇" }
        else if utilization < 87.5 { return "⣧" }
        else { return "⣿" }
    }

    func getProgressBar(for utilization: Double, filled: String, empty: String, prefix: String, suffix: String) -> String {
        let totalBlocks = 5
        let filledBlocks = Int((utilization / 100.0) * Double(totalBlocks) + 0.5)
        let emptyBlocks = totalBlocks - filledBlocks
        let filledStr = String(repeating: filled, count: filledBlocks)
        let emptyStr = String(repeating: empty, count: emptyBlocks)
        return "\(prefix)\(filledStr)\(emptyStr)\(suffix)"
    }

    func getIconForUtilization(_ utilization: Double) -> String {
        if utilization >= 80 {
            return "⚠️"
        } else if utilization >= 50 {
            return "🚀"
        } else {
            return "✳️"
        }
    }

    func formatUtilization(_ value: Double) -> String {
        return String(format: "%.0f", value)
    }

    func formatResetTime(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: dateString) else {
            return dateString
        }

        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval < 0 {
            return "soon"
        }

        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours >= 24 {
            let days = hours / 24
            return "\(days) day\(days == 1 ? "" : "s")"
        } else if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "< 1m"
        }
    }

    func calculateExpectedUsage(resetDateString: String, metric: MetricType) -> Double? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let resetDate = formatter.date(from: resetDateString) else {
            return nil
        }

        let windowDuration: TimeInterval
        switch metric {
        case .fiveHour:
            windowDuration = 5 * 3600
        case .sevenDay, .sevenDaySonnet:
            windowDuration = 7 * 24 * 3600
        }

        let now = Date()
        let timeRemaining = resetDate.timeIntervalSince(now)

        guard timeRemaining > 0 && timeRemaining <= windowDuration else {
            return nil
        }

        let timeElapsed = windowDuration - timeRemaining
        return (timeElapsed / windowDuration) * 100.0
    }
}

// MARK: - Data Models

struct UsageResponse: Codable {
    let five_hour: UsageLimit?
    let seven_day: UsageLimit?
    let seven_day_oauth_apps: UsageLimit?
    let seven_day_opus: UsageLimit?
    let seven_day_sonnet: UsageLimit?
    let iguana_necktie: UsageLimit?
    let extra_usage: UsageLimit?
}

struct UsageLimit: Codable {
    let utilization: Double
    let resets_at: String?
}

// MARK: - Main Entry Point

@main
struct ClaudeUsageApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
