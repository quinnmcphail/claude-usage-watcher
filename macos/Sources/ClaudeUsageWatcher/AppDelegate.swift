import AppKit
import ServiceManagement
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let pollInterval: TimeInterval = 120

    private var settings = Settings.load()
    private lazy var service = UsageService(
        notifyWarnAt: settings.notifyWarnAt,
        notifyCriticalAt: settings.notifyCriticalAt)
    private let notifier = Notifier()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var panel: PanelViewController!

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var pollInProgress = false
    private var lastOutcome: FetchOutcome = .success

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only: keep us out of the Dock even under `swift run`.
        NSApp.setActivationPolicy(.accessory)

        if surrenderToExistingInstance() {
            return
        }

        setupStatusItem()
        setupPopover()

        renderFromCache()

        startTimers()
        poll()
    }

    // MARK: - Single instance

    /// When bundled, if another copy is already running, surface it and quit.
    private func surrenderToExistingInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        if let other = others.first {
            other.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return true
        }
        return false
    }

    // MARK: - UI setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = StatusItemRenderer.makeImage(fiveHour: nil, isStale: false, hasCredentials: true)
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupPopover() {
        panel = PanelViewController(
            settings: { [weak self] in self?.settings ?? Settings() },
            onToggleExpand: { [weak self] in self?.toggleExpand() })

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = panel
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
    }

    // MARK: - Status item interaction

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            panel.render(service: service, lastOutcome: lastOutcome)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(withTitle: "Refresh now", action: #selector(refreshNow), keyEquivalent: "").target = self

        let notifications = NSMenuItem(title: "Notifications", action: #selector(toggleNotifications), keyEquivalent: "")
        notifications.target = self
        notifications.state = settings.notificationsEnabled ? .on : .off
        menu.addItem(notifications)

        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = launchAtLoginEnabled() ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self

        // Present the menu under the status item, then clear it so left-clicks still
        // toggle the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshNow() { poll() }

    @objc private func toggleNotifications() {
        settings.notificationsEnabled.toggle()
        settings.save()
        if settings.notificationsEnabled {
            notifier.requestAuthorizationIfNeeded()
        }
    }

    private func toggleExpand() {
        settings.expanded.toggle()
        settings.save()
        renderFromCache()
    }

    @objc private func quit() {
        settings.save()
        NSApp.terminate(nil)
    }

    // MARK: - Launch at login (SMAppService)

    private func launchAtLoginEnabled() -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLaunchAtLogin() {
        // Guard against bare `swift run` (no bundle id): SMAppService.mainApp throws.
        guard Bundle.main.bundleIdentifier != nil, #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // best-effort; ignore failures
        }
    }

    // MARK: - Polling

    private func startTimers() {
        let poll = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.poll() }
        }
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll

        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.renderFromCache() }
        }
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick
    }

    private func poll() {
        guard !pollInProgress else { return } // single-flight
        pollInProgress = true

        Task { @MainActor in
            let result = await service.poll()
            lastOutcome = result.outcome
            renderFromCache()

            if let event = result.notification, settings.notificationsEnabled {
                notifier.post(event: event, snapshot: result.snapshot, now: Date())
            }
            pollInProgress = false
        }
    }

    private func renderFromCache() {
        let now = Date()
        let snap = service.lastGood

        if let button = statusItem?.button {
            button.image = StatusItemRenderer.makeImage(
                fiveHour: snap?.fiveHour?.utilization,
                isStale: service.isStale,
                hasCredentials: service.hasCredentials)
            button.toolTip = StatusItemRenderer.tooltip(
                snapshot: snap,
                hasCredentials: service.hasCredentials,
                isStale: service.isStale,
                now: now)
        }

        if popover?.isShown == true {
            panel.render(service: service, lastOutcome: lastOutcome, now: now)
        }
    }
}
