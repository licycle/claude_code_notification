import AppKit

// MARK: - Daily Report View

class DailyReportView: NSView {

    private var titleLabel: NSTextField!
    private var statsView: NSView!
    private var sessionListView: NSScrollView!

    private var sessions: [SessionInfo] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true

        // Title
        titleLabel = NSTextField(labelWithString: "今日报告")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // Stats view
        statsView = NSView()
        statsView.translatesAutoresizingMaskIntoConstraints = false
        statsView.wantsLayer = true
        statsView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        statsView.layer?.cornerRadius = 8
        addSubview(statsView)

        // Session list
        sessionListView = NSScrollView()
        sessionListView.translatesAutoresizingMaskIntoConstraints = false
        sessionListView.hasVerticalScroller = true
        sessionListView.autohidesScrollers = true
        addSubview(sessionListView)

        // Layout
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            statsView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            statsView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            statsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            statsView.heightAnchor.constraint(equalToConstant: 100),

            sessionListView.topAnchor.constraint(equalTo: statsView.bottomAnchor, constant: 16),
            sessionListView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            sessionListView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            sessionListView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }

    func refresh() {
        sessions = DatabaseManager.shared.getTodaySessions()
        updateStats()
        updateSessionList()
    }

    private func updateStats() {
        // Clear existing stats
        statsView.subviews.forEach { $0.removeFromSuperview() }

        let total = sessions.count
        let completed = sessions.filter { $0.currentStatus == "completed" }.count
        let working = sessions.filter { ["working", "executing_tool", "subagent_working"].contains($0.currentStatus) }.count
        let waiting = sessions.filter { ["waiting_for_user", "waiting_permission"].contains($0.currentStatus) }.count

        // Create stat labels
        let stats = [
            ("总会话", "\(total)", NSColor.labelColor),
            ("已完成", "\(completed)", NSColor.systemGreen),
            ("工作中", "\(working)", NSColor.systemBlue),
            ("等待中", "\(waiting)", NSColor.systemOrange)
        ]

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for (label, value, color) in stats {
            let statView = createStatItem(label: label, value: value, color: color)
            stackView.addArrangedSubview(statView)
        }

        statsView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: statsView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: statsView.trailingAnchor, constant: -16),
            stackView.centerYAnchor.constraint(equalTo: statsView.centerYAnchor)
        ])
    }

    private func createStatItem(label: String, value: String, color: NSColor) -> NSView {
        let container = NSView()

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.boldSystemFont(ofSize: 28)
        valueLabel.textColor = color
        valueLabel.alignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = NSFont.systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(valueLabel)
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            valueLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            valueLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 4)
        ])

        return container
    }

    private func updateSessionList() {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        var yOffset: CGFloat = 8
        for session in sessions {
            let row = createSessionRow(session: session)
            row.frame = NSRect(x: 0, y: 0, width: 600, height: 32)
            row.frame.origin.y = yOffset
            contentView.addSubview(row)
            yOffset += 36
        }

        contentView.frame = NSRect(x: 0, y: 0, width: 600, height: max(yOffset, 100))
        sessionListView.documentView = contentView
    }

    private func createSessionRow(session: SessionInfo) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 32))

        let statusEmoji = getStatusEmoji(session.currentStatus)
        let goalText = String(session.originalGoal.prefix(50))

        let label = NSTextField(labelWithString: "\(statusEmoji) \(goalText)")
        label.font = NSFont.systemFont(ofSize: 12)
        label.frame = NSRect(x: 8, y: 6, width: 500, height: 20)
        row.addSubview(label)

        return row
    }

    private func getStatusEmoji(_ status: String) -> String {
        switch status {
        case "working", "executing_tool", "subagent_working": return "🟢"
        case "idle": return "🟡"
        case "waiting_for_user": return "🔴"
        case "waiting_permission": return "🔐"
        case "completed": return "✅"
        default: return "⚪"
        }
    }
}
