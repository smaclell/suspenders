import AppKit
import ServiceManagement
import SuspendersCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var config = Config.load()
    private let index = VaultIndex()
    private lazy var tracker = ActivityTracker(config: config)
    private lazy var signOff = SignOffController(config: config, tracker: tracker) { [weak self] kind, text in
        self?.appendLog(kind: kind, site: nil, text: text)
    }
    private var server: HTTPServer?
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var reindexTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !FileManager.default.fileExists(atPath: Config.fileURL.path) { try? config.save() }
        Notifier.requestPermission()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "moon.stars", accessibilityDescription: "Suspenders")
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        startServer()
        reindex()

        timer = Timer.scheduledTimer(withTimeInterval: ActivityTracker.tickSeconds, repeats: true) { [weak self] _ in self?.tick() }
        reindexTimer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) { [weak self] _ in self?.reindex() }
        tick()
    }

    // MARK: loop

    private func tick() {
        tracker.tick()
        signOff.tick()
        updateTitle()
    }

    private func updateTitle() {
        let now = Date()
        var title = ""
        if let past = signOff.minutesPastSignOff {
            title = past < 60 ? " +\(past)m" : " +\(past / 60)h \(past % 60)m"
        } else if let signOffMinutes = Schedule.minutes(config.signOffTime) {
            var until = signOffMinutes - Schedule.minutesOfDay(now)
            if until < 0 { until += 1440 }
            if until <= 120 { title = until < 60 ? " \(until)m" : " \(until / 60)h \(until % 60)m" }
        }
        statusItem.button?.title = title
        statusItem.button?.image = NSImage(systemSymbolName: signOff.minutesPastSignOff != nil ? "moon.zzz.fill" : "moon.stars",
                                           accessibilityDescription: "Suspenders")
    }

    // MARK: server

    private func startServer() {
        server?.stop()
        let server = HTTPServer(port: config.port) { [weak self] req in self?.handle(req) ?? .init(status: 500) }
        do { try server.start() } catch { NSLog("Suspenders: could not start server: \(error)") }
        self.server = server
    }

    private func handle(_ req: HTTPServer.Request) -> HTTPServer.Response {
        switch (req.method, req.path) {
        case ("GET", "/health"):
            return .init(json: ["ok": true])
        case ("GET", "/snippet"):
            guard let s = index.random(), let data = try? JSONEncoder().encode(s),
                  let json = try? JSONSerialization.jsonObject(with: data) else { return .init(status: 404, json: ["error": "no snippets"]) }
            return .init(json: json)
        case ("GET", "/status"):
            return .init(json: [
                "activeMinutesTonight": tracker.activeMinutesTonight,
                "idleSeconds": Int(tracker.idleSeconds),
                "minutesPastSignOff": signOff.minutesPastSignOff as Any? ?? NSNull(),
                "snoozed": signOff.isSnoozed,
                "snippetCount": index.snippetCount,
                "noteCount": index.noteCount,
                "vaultConfigured": config.vaultPath != nil,
            ])
        case ("POST", "/reasons"):
            guard let obj = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
                  let reason = obj["reason"] as? String, !reason.isEmpty else { return .init(status: 400, json: ["error": "reason required"]) }
            appendLog(kind: "Unlocked", site: obj["site"] as? String, text: String(reason.prefix(4000)))
            return .init(json: ["ok": true])
        default:
            return .init(status: 404, json: ["error": "not found"])
        }
    }

    // MARK: log

    private func appendLog(kind: String, site: String?, text: String) {
        let url = config.reasonsLogURL
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            let header = "# Late-night log\n\nWritten by Suspenders. Every late-night unlock, deferral and reflection.\n\n"
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }
        let f = DateFormatter()
        f.dateFormat = "EEE yyyy-MM-dd HH:mm"
        let body = text.replacingOccurrences(of: "\n", with: "\n  ")
        let line = "- **\(f.string(from: Date()))** · \(kind)\(site.map { " · \($0)" } ?? "") — \(body)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
    }

    // MARK: vault

    private func reindex() {
        let config = self.config
        DispatchQueue.global(qos: .utility).async { [index] in
            index.rebuild(config: config)
        }
    }

    @objc private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose your Obsidian vault folder"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        config.vaultPath = url.path
        saveConfig()
    }

    private func saveConfig() {
        try? config.save()
        tracker.update(config: config)
        signOff.update(config: config)
        reindex()
    }

    @objc private func reloadConfig() {
        let oldPort = config.port
        config = Config.load()
        saveConfig()
        if config.port != oldPort { startServer() }
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let mins = tracker.activeMinutesTonight
        menu.addItem(disabled("Tonight: \(mins / 60)h \(mins % 60)m on the laptop"))
        if let past = signOff.minutesPastSignOff { menu.addItem(disabled("\(past) min past sign-off (\(config.signOffTime))")) }
        if signOff.isSnoozed { menu.addItem(disabled("Nudges snoozed")) }
        menu.addItem(.separator())

        if let vault = config.vaultPath {
            menu.addItem(disabled("Vault: \((vault as NSString).lastPathComponent) · \(index.noteCount) notes, \(index.snippetCount) passages"))
            menu.addItem(item("Tags: " + config.tags.map { "#\($0)" }.joined(separator: " "), nil))
        } else {
            menu.addItem(disabled("No vault chosen yet"))
        }
        menu.addItem(item("Choose Vault Folder…", #selector(chooseVault)))
        menu.addItem(item("Reindex Notes", #selector(reindexAction)))
        menu.addItem(.separator())

        menu.addItem(item("Snooze Nudges for 30 Minutes", #selector(snooze)))
        menu.addItem(item("Preview Wind-down Card", #selector(previewWindDown)))
        menu.addItem(item("Open Late-night Log", #selector(openLog)))
        menu.addItem(item("Edit Settings (config.json)…", #selector(openConfig)))
        menu.addItem(item("Reload Settings", #selector(reloadConfig)))
        menu.addItem(.separator())

        let login = item("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Quit Suspenders", #selector(NSApplication.terminate(_:)), target: NSApp))
    }

    private func item(_ title: String, _ action: Selector?, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = action == nil ? nil : (target ?? self)
        return i
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    @objc private func reindexAction() { reindex() }
    @objc private func snooze() { signOff.snooze(minutes: 30) }
    @objc private func previewWindDown() { signOff.showWindDown() }

    @objc private func openLog() {
        let url = config.reasonsLogURL
        if !FileManager.default.fileExists(atPath: url.path) { appendLog(kind: "Started", site: nil, text: "Log created.") }
        NSWorkspace.shared.open(url)
    }

    @objc private func openConfig() {
        try? config.save()
        NSWorkspace.shared.open(Config.fileURL)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMove Suspenders Helper.app to /Applications and try again."
            alert.runModal()
        }
    }
}
