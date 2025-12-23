import AppKit

// MARK: - Session Card View Delegate

protocol SessionCardViewDelegate: AnyObject {
    func sessionCardDidClick(_ session: SessionInfo)
    func sessionCardDidRequestJump(_ session: SessionInfo)
}

// MARK: - Session Card View

class SessionCardView: NSView {
    weak var delegate: SessionCardViewDelegate?
    private let session: SessionInfo
    private var progress: ProgressInfo?
    private var roundCount: Int = 0
    private var summaryMode: String?

    init(session: SessionInfo) {
        self.session = session
        super.init(frame: .zero)
        self.progress = DatabaseManager.shared.getProgress(sessionId: session.sessionId)
        self.roundCount = DatabaseManager.shared.getRoundCount(sessionId: session.sessionId)
        self.summaryMode = DatabaseManager.shared.getSummaryMode(sessionId: session.sessionId)
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

        // Line 1: Status emoji + Goal (y=90)
        let statusEmoji = getStatusEmoji()
        let goalText = String(session.originalGoal.prefix(35))
        let titleLabel = NSTextField(labelWithString: "\(statusEmoji) \(goalText)")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 12, y: 90, width: 320, height: 20)
        addSubview(titleLabel)

        // Line 2: Project path (y=72)
        let projectPath = shortenPath(session.project)
        let projectLabel = NSTextField(labelWithString: "📁 \(projectPath)")
        projectLabel.font = NSFont.systemFont(ofSize: 11)
        projectLabel.textColor = .secondaryLabelColor
        projectLabel.lineBreakMode = .byTruncatingMiddle
        projectLabel.frame = NSRect(x: 12, y: 72, width: 320, height: 16)
        addSubview(projectLabel)

        // Line 3: [mode][account][session_id] R{round} (y=54)
        let sessionPrefix = String(session.sessionId.prefix(4))
        let modeTag = summaryMode != nil ? "[\(summaryMode!.uppercased())]" : ""
        let accountTag = session.accountAlias != "default" ? "[\(session.accountAlias)]" : ""
        let roundTag = roundCount > 0 ? " R\(roundCount)" : ""
        let infoText = "\(modeTag)\(accountTag)[\(sessionPrefix)]\(roundTag)"
        let infoLabel = NSTextField(labelWithString: infoText)
        infoLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        infoLabel.textColor = .tertiaryLabelColor
        infoLabel.frame = NSRect(x: 12, y: 54, width: 200, height: 16)
        addSubview(infoLabel)

        // Line 4: Status text (y=36)
        let statusText = getStatusText()
        let statusLabel = NSTextField(labelWithString: statusText)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = getStatusColor()
        statusLabel.frame = NSRect(x: 12, y: 36, width: 320, height: 16)
        addSubview(statusLabel)

        // Line 5: Time + Jump button (y=12)
        let timeAgo = DatabaseManager.shared.relativeTime(from: session.lastActivity)
        let timeLabel = NSTextField(labelWithString: "⏱️ \(timeAgo)")
        timeLabel.font = NSFont.systemFont(ofSize: 11)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.frame = NSRect(x: 12, y: 12, width: 150, height: 16)
        addSubview(timeLabel)

        // Detail button
        let detailButton = NSButton(title: "详情", target: self, action: #selector(showDetail))
        detailButton.bezelStyle = .rounded
        detailButton.controlSize = .small
        detailButton.frame = NSRect(x: 280, y: 10, width: 52, height: 22)
        addSubview(detailButton)

        // Click gesture - use mouseDown override instead to avoid intercepting button clicks
    }

    private func shortenPath(_ path: String) -> String {
        // Shorten home directory to ~
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var result = path
        if result.hasPrefix(home) {
            result = "~" + result.dropFirst(home.count)
        }
        // Truncate if too long
        if result.count > 40 {
            let components = result.components(separatedBy: "/")
            if components.count > 3 {
                return "~/.../" + components.suffix(2).joined(separator: "/")
            }
        }
        return result
    }

    private func getStatusEmoji() -> String {
        switch session.currentStatus {
        case "waiting_for_user", "waiting_permission":
            return "🟠"  // 橙色，与 StatusBar 一致
        case "idle":
            return "⚪"  // 灰色，与 StatusBar 一致
        case "working", "executing_tool", "subagent_working":
            return "🟢"  // 绿色
        case "completed":
            return "⚪"  // 灰色
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
        case "executing_tool":
            return "🔧 执行工具"
        case "subagent_working":
            return "🤖 子代理"
        case "completed":
            return "✅ 已完成"
        default:
            return session.currentStatus
        }
    }

    private func getStatusColor() -> NSColor {
        switch session.currentStatus {
        case "waiting_for_user", "waiting_permission":
            return .systemOrange  // 橙色
        case "idle":
            return .systemGray    // 灰色，与 StatusBar 一致
        case "working", "executing_tool", "subagent_working":
            return .systemGreen
        case "completed":
            return .tertiaryLabelColor  // 更淡的灰色
        default:
            return .secondaryLabelColor
        }
    }

    // Handle card click via mouseDown to avoid intercepting button clicks
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        // Check if click is on a button (subview that handles its own clicks)
        for subview in subviews {
            if subview is NSButton && subview.frame.contains(location) {
                // Let the button handle it
                super.mouseDown(with: event)
                return
            }
        }

        // Otherwise, jump to terminal
        delegate?.sessionCardDidRequestJump(session)
    }

    @objc private func showDetail() {
        log("SESSIONCARD: showDetail clicked for session \(session.sessionId.prefix(8))")
        delegate?.sessionCardDidClick(session)
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
