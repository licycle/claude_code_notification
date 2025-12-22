import AppKit

// MARK: - Status Bar Controller

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var sessionListViewController: SessionListViewController!
    private var refreshTimer: Timer?
    private var eventMonitor: Any?

    override init() {
        super.init()
        setupStatusItem()
        setupPopover()
        startRefreshTimer()
        setupEventMonitor()
        log("STATUSBAR: Initialized")
    }

    deinit {
        refreshTimer?.invalidate()
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
        // Could show detail view or jump to terminal
        log("STATUSBAR: Selected session \(session.sessionId)")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showSettingsWindow = Notification.Name("showSettingsWindow")
}

// MARK: - Session List View Controller

protocol SessionListViewControllerDelegate: AnyObject {
    func sessionListDidRequestSettings()
    func sessionListDidSelectSession(_ session: SessionInfo)
}

class SessionListViewController: NSViewController {
    weak var delegate: SessionListViewControllerDelegate?

    private var scrollView: NSScrollView!
    private var contentView: NSView!
    private var sessions: [SessionInfo] = []

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 480))
        setupUI()
    }

    private func setupUI() {
        // Header
        let headerView = createHeaderView()
        view.addSubview(headerView)

        // Scroll view for session list
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 50, width: 360, height: 380))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        view.addSubview(scrollView)

        // Footer
        let footerView = createFooterView()
        view.addSubview(footerView)

        // Layout
        headerView.frame = NSRect(x: 0, y: 430, width: 360, height: 50)
        scrollView.frame = NSRect(x: 0, y: 50, width: 360, height: 380)
        footerView.frame = NSRect(x: 0, y: 0, width: 360, height: 50)
    }

    private func createHeaderView() -> NSView {
        let header = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 50))

        let titleLabel = NSTextField(labelWithString: "Claude Monitor")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.frame = NSRect(x: 16, y: 15, width: 200, height: 20)
        header.addSubview(titleLabel)

        let settingsButton = NSButton(frame: NSRect(x: 320, y: 12, width: 28, height: 28))
        settingsButton.bezelStyle = .regularSquare
        settingsButton.isBordered = false
        if #available(macOS 11.0, *) {
            settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        } else {
            settingsButton.title = "⚙️"
        }
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        header.addSubview(settingsButton)

        // Separator
        let separator = NSBox(frame: NSRect(x: 0, y: 0, width: 360, height: 1))
        separator.boxType = .separator
        header.addSubview(separator)

        return header
    }

    private func createFooterView() -> NSView {
        let footer = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 50))

        // Separator at top
        let separator = NSBox(frame: NSRect(x: 0, y: 49, width: 360, height: 1))
        separator.boxType = .separator
        footer.addSubview(separator)

        let clearButton = NSButton(title: "清除已完成", target: self, action: #selector(clearCompleted))
        clearButton.bezelStyle = .rounded
        clearButton.frame = NSRect(x: 20, y: 10, width: 100, height: 30)
        footer.addSubview(clearButton)

        let refreshButton = NSButton(title: "刷新", target: self, action: #selector(refreshTapped))
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: 240, y: 10, width: 100, height: 30)
        footer.addSubview(refreshButton)

        return footer
    }

    // MARK: - Actions

    @objc func openSettings() {
        delegate?.sessionListDidRequestSettings()
    }

    @objc func clearCompleted() {
        // TODO: Implement clear completed sessions
        log("STATUSBAR: Clear completed requested")
    }

    @objc func refreshTapped() {
        refresh()
    }

    // MARK: - Data

    func refresh() {
        // 确保视图已加载（触发 loadView）
        if !isViewLoaded {
            _ = view  // 触发 loadView
        }
        sessions = DatabaseManager.shared.getActiveSessions()
        updateSessionList()
    }

    private func updateSessionList() {
        // Clear existing views
        contentView.subviews.forEach { $0.removeFromSuperview() }

        if sessions.isEmpty {
            showEmptyState()
            return
        }

        var yOffset: CGFloat = 0
        let cardHeight: CGFloat = 100
        let cardSpacing: CGFloat = 8
        let cardWidth: CGFloat = 344

        for session in sessions {
            let cardView = createSessionCard(session: session, yOffset: yOffset)
            contentView.addSubview(cardView)
            yOffset += cardHeight + cardSpacing
        }

        // Set content view size
        let totalHeight = max(yOffset, scrollView.frame.height)
        contentView.frame = NSRect(x: 0, y: 0, width: 360, height: totalHeight)

        // Flip coordinates (NSScrollView uses flipped coordinates)
        for (index, subview) in contentView.subviews.enumerated() {
            let y = totalHeight - CGFloat(index + 1) * (cardHeight + cardSpacing)
            subview.frame.origin.y = max(0, y)
        }
    }

    private func showEmptyState() {
        let emptyLabel = NSTextField(labelWithString: "暂无活跃任务")
        emptyLabel.font = NSFont.systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.frame = NSRect(x: 0, y: 170, width: 360, height: 40)
        contentView.addSubview(emptyLabel)

        contentView.frame = NSRect(x: 0, y: 0, width: 360, height: 380)
    }

    private func createSessionCard(session: SessionInfo, yOffset: CGFloat) -> NSView {
        let card = SessionCardView(session: session)
        card.frame = NSRect(x: 8, y: yOffset, width: 344, height: 100)
        card.delegate = self
        return card
    }
}

// MARK: - Session Card Delegate

extension SessionListViewController: SessionCardViewDelegate {
    func sessionCardDidClick(_ session: SessionInfo) {
        delegate?.sessionListDidSelectSession(session)
    }

    func sessionCardDidRequestJump(_ session: SessionInfo) {
        // Jump to terminal - reuse existing logic from AppDelegate
        log("STATUSBAR: Jump to terminal for session \(session.sessionId)")
        // TODO: Implement jump to terminal
    }
}

// MARK: - Session Card View

protocol SessionCardViewDelegate: AnyObject {
    func sessionCardDidClick(_ session: SessionInfo)
    func sessionCardDidRequestJump(_ session: SessionInfo)
}

class SessionCardView: NSView {
    weak var delegate: SessionCardViewDelegate?
    private let session: SessionInfo
    private var progress: ProgressInfo?

    init(session: SessionInfo) {
        self.session = session
        super.init(frame: .zero)
        self.progress = DatabaseManager.shared.getProgress(sessionId: session.sessionId)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        // Status indicator + Goal
        let statusEmoji = getStatusEmoji()
        let goalText = String(session.originalGoal.prefix(30))
        let titleLabel = NSTextField(labelWithString: "\(statusEmoji) \(goalText)")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 12, y: 70, width: 260, height: 20)
        addSubview(titleLabel)

        // Project badge
        let projectLabel = NSTextField(labelWithString: session.project)
        projectLabel.font = NSFont.systemFont(ofSize: 11)
        projectLabel.textColor = .secondaryLabelColor
        projectLabel.alignment = .right
        projectLabel.frame = NSRect(x: 260, y: 70, width: 76, height: 20)
        addSubview(projectLabel)

        // Progress bar
        if let progress = progress, progress.total > 0 {
            let progressView = createProgressBar(completed: progress.completed, total: progress.total)
            progressView.frame = NSRect(x: 12, y: 48, width: 320, height: 16)
            addSubview(progressView)
        }

        // Status text
        let statusText = getStatusText()
        let statusLabel = NSTextField(labelWithString: statusText)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = getStatusColor()
        statusLabel.frame = NSRect(x: 12, y: 26, width: 200, height: 16)
        addSubview(statusLabel)

        // Time ago
        let timeAgo = DatabaseManager.shared.relativeTime(from: session.lastActivity)
        let timeLabel = NSTextField(labelWithString: "⏱️ \(timeAgo)")
        timeLabel.font = NSFont.systemFont(ofSize: 11)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.frame = NSRect(x: 12, y: 8, width: 150, height: 16)
        addSubview(timeLabel)

        // Jump button
        let jumpButton = NSButton(title: "跳转", target: self, action: #selector(jumpToTerminal))
        jumpButton.bezelStyle = .rounded
        jumpButton.controlSize = .small
        jumpButton.frame = NSRect(x: 280, y: 8, width: 52, height: 22)
        addSubview(jumpButton)

        // Click gesture
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(cardClicked))
        addGestureRecognizer(clickGesture)
    }

    private func createProgressBar(completed: Int, total: Int) -> NSView {
        let container = NSView()

        let percentage = total > 0 ? CGFloat(completed) / CGFloat(total) : 0
        let barWidth: CGFloat = 280
        let barHeight: CGFloat = 4

        // Background
        let bgBar = NSView(frame: NSRect(x: 0, y: 6, width: barWidth, height: barHeight))
        bgBar.wantsLayer = true
        bgBar.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.3).cgColor
        bgBar.layer?.cornerRadius = 2
        container.addSubview(bgBar)

        // Progress
        let progressBar = NSView(frame: NSRect(x: 0, y: 6, width: barWidth * percentage, height: barHeight))
        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = NSColor.systemGreen.cgColor
        progressBar.layer?.cornerRadius = 2
        container.addSubview(progressBar)

        // Percentage label
        let percentLabel = NSTextField(labelWithString: "\(Int(percentage * 100))%")
        percentLabel.font = NSFont.systemFont(ofSize: 10)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.frame = NSRect(x: 290, y: 2, width: 30, height: 12)
        container.addSubview(percentLabel)

        return container
    }

    private func getStatusEmoji() -> String {
        switch session.currentStatus {
        case "waiting_for_user", "waiting_permission":
            return "🔴"
        case "idle":
            return "🟡"
        case "working":
            return "🟢"
        case "completed":
            return "✅"
        default:
            return "⚪"
        }
    }

    private func getStatusText() -> String {
        switch session.currentStatus {
        case "waiting_for_user":
            return "⚠️ 等待决策"
        case "waiting_permission":
            return "🔐 等待权限"
        case "idle":
            return "💤 空闲中"
        case "working":
            return "🔄 运行中"
        case "completed":
            return "✅ 已完成"
        default:
            return session.currentStatus
        }
    }

    private func getStatusColor() -> NSColor {
        switch session.currentStatus {
        case "waiting_for_user", "waiting_permission":
            return .systemOrange
        case "idle":
            return .systemYellow
        case "working":
            return .systemGreen
        case "completed":
            return .systemGray
        default:
            return .secondaryLabelColor
        }
    }

    @objc private func cardClicked() {
        delegate?.sessionCardDidClick(session)
    }

    @objc private func jumpToTerminal() {
        delegate?.sessionCardDidRequestJump(session)
    }

    // Hover effect
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlBackgroundColor.highlight(withLevel: 0.1)?.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }
}
