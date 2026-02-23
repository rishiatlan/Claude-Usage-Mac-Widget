import Cocoa
import SwiftUI

// MARK: - Metric Type Enum

enum MetricType: String, CaseIterable {
    case fiveHour = "5-hour Limit"
    case sevenDay = "7-day Limit (All Models)"
    case sevenDaySonnet = "7-day Limit (Sonnet)"

    var displayName: String { rawValue }
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
    private let appPath = "/Applications/ClaudeUsage.app"

    var isLoginItemEnabled: Bool {
        let script = """
            tell application "System Events"
                get the name of every login item
            end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if let items = result.coerce(toDescriptorType: typeAEList) {
            for i in 1...items.numberOfItems {
                if let item = items.atIndex(i)?.stringValue, item == "ClaudeUsage" {
                    return true
                }
            }
        }
        return false
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        if enabled {
            addLoginItem()
        } else {
            removeLoginItem()
        }
    }

    private func addLoginItem() {
        let script = """
            tell application "System Events"
                make login item at end with properties {path:"\(appPath)", hidden:false}
            end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    private func removeLoginItem() {
        let script = """
            tell application "System Events"
                delete login item "ClaudeUsage"
            end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
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
                Text("Claude Usage Settings")
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Session Key:")
                        .font(.headline)

                    TextField("Enter your Claude session key", text: $sessionKey)
                        .textFieldStyle(.roundedBorder)

                    Text("Find this in your browser's cookies at claude.ai")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Organization ID:")
                        .font(.headline)

                    TextField("Enter your organization ID", text: $organizationId)
                        .textFieldStyle(.roundedBorder)

                    Text("Find this in any claude.ai API request URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
    let status: AppDelegate.UsageStatus
}

// MARK: - Widget View

struct WidgetView: View {
    let data: WidgetViewData?

    var body: some View {
        if let data = data {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: min(data.utilization / 100.0, 1.0))
                        .stroke(statusColor(data.status), style: StrokeStyle(lineWidth: 6, lineCap: .round))
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

                Text("Resets \(data.resetTimeString)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                if let expected = data.expectedUsage {
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
            .padding(14)
            .frame(width: 130, height: 150)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .frame(width: 130, height: 150)
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

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show(with data: WidgetViewData?) {
        if panel == nil {
            createPanel()
        }
        updateContent(with: data)
        panel?.orderFront(nil)
        UserDefaults.standard.set(true, forKey: widgetVisibleKey)
    }

    func hide() {
        panel?.orderOut(nil)
        UserDefaults.standard.set(false, forKey: widgetVisibleKey)
    }

    func toggle(with data: WidgetViewData?) {
        if isVisible {
            hide()
        } else {
            show(with: data)
        }
    }

    func updateContent(with data: WidgetViewData?) {
        guard let hostingView = hostingView else { return }
        hostingView.rootView = WidgetView(data: data)
    }

    var shouldRestoreOnLaunch: Bool {
        UserDefaults.standard.bool(forKey: widgetVisibleKey)
    }

    private func createPanel() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let defaultX = screen.maxX - 150
        let defaultY = screen.minY + 20

        let savedX = UserDefaults.standard.object(forKey: posXKey) as? CGFloat
        let savedY = UserDefaults.standard.object(forKey: posYKey) as? CGFloat
        let x = savedX ?? defaultX
        let y = savedY ?? defaultY

        let rect = NSRect(x: x, y: y, width: 130, height: 150)
        panel = FloatingWidgetPanel(contentRect: rect)

        let widgetView = WidgetView(data: nil)
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
    let maxRetries = 3
    let maxLogEntries = 50

    func applicationDidFinishLaunching(_ notification: Notification) {
        addLog("App launched")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "⏱️"
            button.action = #selector(showMenu)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        menu = NSMenu()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .settingsChanged,
            object: nil
        )

        fetchUsageData()

        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.fetchUsageData()
        }

        // Restore desktop widget if it was visible
        if widgetController.shouldRestoreOnLaunch {
            widgetController.show(with: currentWidgetData())
        }
    }

    @objc func handleSettingsChanged() {
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

        return WidgetViewData(
            utilization: utilization,
            expectedUsage: expectedUsage,
            resetTimeString: resetTimeString,
            metricName: name,
            status: status
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
            }
            return
        }

        guard let organizationId = organizationId, !organizationId.isEmpty else {
            let msg = "No organization ID configured"
            addLog(msg)
            DispatchQueue.main.async {
                self.consecutiveFailures += 1
                self.statusItem.button?.title = "❌"
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
        request.addValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

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

                DispatchQueue.main.async {
                    self.consecutiveFailures = 0
                    self.usageData = usageData
                    self.updateMenuBarIcon()
                    self.addLog("Fetch OK")
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

        // Update desktop widget if visible
        if widgetController.isVisible {
            widgetController.updateContent(with: currentWidgetData())
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
