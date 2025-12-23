import AppKit

// MARK: - Status Bar Controller

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var sessionListViewController: SessionListViewController!
    private var sessionDetailViewController: SessionDetailViewController?
    private var refreshTimer: Timer?
    private var cleanupTimer: Timer?
    private var eventMonitor: Any?

    override init() {
        super.init()
        setupStatusItem()
        setupPopover()
        startRefreshTimer()
        startCleanupTimer()
        setupEventMonitor()
        log("STATUSBAR: Initialized")
    }

    deinit {
        refreshTimer?.invalidate()
        cleanupTimer?.invalidate()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            updateIcon()
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        sessionListViewController = SessionListViewController()
        sessionListViewController.delegate = self
        popover.contentViewController = sessionListViewController
        popover.contentSize = NSSize(width: 360, height: 480)
    }

    private func setupEventMonitor() {
        // Close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self = self, self.popover.isShown {
                self.popover.performClose(nil)
            }
        }
    }

    private func startRefreshTimer() {
        // Refresh every 5 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func startCleanupTimer() {
        // Cleanup dead sessions every 5 minutes
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            self?.cleanupDeadSessions()
        }
        // Run immediately at startup to recover/cleanup sessions
        cleanupDeadSessions()
    }

    private func cleanupDeadSessions() {
        let count = DatabaseManager.shared.cleanupDeadSessions()
        if count > 0 {
            log("STATUSBAR: Cleaned up \(count) dead sessions")
            refresh()
        }
    }

    // MARK: - Actions

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }

        sessionListViewController.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Activate app to ensure popover gets focus
        NSApp.activate(ignoringOtherApps: true)
    }

    func hidePopover() {
        popover.performClose(nil)
    }

    // MARK: - Update

    func refresh() {
        updateIcon()
        if popover.isShown {
            sessionListViewController.refresh()
        }
    }

    func updateIcon() {
        let (status, count) = DatabaseManager.shared.getOverallStatus()

        if let button = statusItem.button {
            // Use SF Symbols if available, fallback to emoji
            if #available(macOS 11.0, *) {
                let symbolName: String
                let color: NSColor

                switch status {
                case .needsDecision:
                    symbolName = "exclamationmark.circle.fill"
                    color = .systemRed
                case .idle:
                    symbolName = "pause.circle.fill"
                    color = .systemYellow
                case .working:
                    symbolName = "play.circle.fill"
                    color = .systemGreen
                case .completed:
                    symbolName = "checkmark.circle.fill"
                    color = .systemGray
                case .none:
                    symbolName = "circle"
                    color = .systemGray
                }

                if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Claude Monitor") {
                    let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                    let coloredImage = image.withSymbolConfiguration(config)
                    button.image = coloredImage
                    button.contentTintColor = color
                }

                // Show count badge
                if count > 0 && status != .none {
                    button.title = " \(count)"
                } else {
                    button.title = ""
                }
            } else {
                // Fallback for older macOS
                button.title = "\(status.emoji) \(count > 0 ? "\(count)" : "")"
            }
        }
    }
}

// MARK: - Session List Delegate

extension StatusBarController: SessionListViewControllerDelegate {
    func sessionListDidRequestSettings() {
        hidePopover()
        // Notify AppDelegate to show settings
        NotificationCenter.default.post(name: .showSettingsWindow, object: nil)
    }

    func sessionListDidSelectSession(_ session: SessionInfo) {
        log("STATUSBAR: Selected session \(session.sessionId)")
        showSessionDetail(session)
    }

    private func showSessionDetail(_ session: SessionInfo) {
        sessionDetailViewController = SessionDetailViewController(session: session)
        sessionDetailViewController?.delegate = self
        popover.contentViewController = sessionDetailViewController
    }
}

// MARK: - Session Detail Delegate

extension StatusBarController: SessionDetailViewControllerDelegate {
    func sessionDetailDidRequestBack() {
        popover.contentViewController = sessionListViewController
        sessionDetailViewController = nil
        sessionListViewController.refresh()
    }

    func sessionDetailDidRequestJump(_ session: SessionInfo) {
        log("STATUSBAR: Jump to terminal from detail for session \(session.sessionId)")
        NotificationCenter.default.post(
            name: .jumpToTerminal,
            object: nil,
            userInfo: [
                "bundleId": session.bundleId ?? "com.apple.Terminal",
                "terminalPid": session.terminalPid ?? Int32(0),
                "windowId": session.windowId ?? UInt32(0)
            ]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showSettingsWindow = Notification.Name("showSettingsWindow")
    static let jumpToTerminal = Notification.Name("jumpToTerminal")
}
