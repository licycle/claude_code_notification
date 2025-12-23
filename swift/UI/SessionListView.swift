import AppKit

// MARK: - Session List View Controller Delegate

protocol SessionListViewControllerDelegate: AnyObject {
    func sessionListDidRequestSettings()
    func sessionListDidSelectSession(_ session: SessionInfo)
}

// MARK: - Session List View Controller

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

        let cleanupButton = NSButton(title: "清理无效", target: self, action: #selector(forceCleanup))
        cleanupButton.bezelStyle = .rounded
        cleanupButton.frame = NSRect(x: 12, y: 10, width: 80, height: 30)
        footer.addSubview(cleanupButton)

        let refreshButton = NSButton(title: "刷新", target: self, action: #selector(refreshTapped))
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: 260, y: 10, width: 80, height: 30)
        footer.addSubview(refreshButton)

        return footer
    }

    // MARK: - Actions

    @objc func openSettings() {
        delegate?.sessionListDidRequestSettings()
    }

    @objc func forceCleanup() {
        log("STATUSBAR: Force cleanup requested")
        let count = DatabaseManager.shared.cleanupDeadSessions()
        log("STATUSBAR: Force cleanup completed, cleaned \(count) sessions")
        refresh()
    }

    @objc func refreshTapped() {
        refresh()
    }

    // MARK: - Data

    func refresh() {
        // Ensure view is loaded (trigger loadView)
        if !isViewLoaded {
            _ = view  // Trigger loadView
        }
        log("SESSIONLIST: refresh() called")
        sessions = DatabaseManager.shared.getActiveSessions()
        log("SESSIONLIST: Got \(sessions.count) sessions from database")
        for (index, session) in sessions.enumerated() {
            log("SESSIONLIST: [\(index)] id=\(session.sessionId.prefix(8)) status=\(session.currentStatus)")
        }
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
        let cardHeight: CGFloat = 120
        let cardSpacing: CGFloat = 8

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
        card.frame = NSRect(x: 8, y: yOffset, width: 344, height: 120)
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
        // Jump to terminal - post notification for AppDelegate to handle
        log("STATUSBAR: Jump to terminal for session \(session.sessionId)")

        // Post notification with session info
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
