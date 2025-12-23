import AppKit

// MARK: - Session Detail View Controller Delegate

protocol SessionDetailViewControllerDelegate: AnyObject {
    func sessionDetailDidRequestBack()
    func sessionDetailDidRequestJump(_ session: SessionInfo)
}

// MARK: - Session Detail View Controller

class SessionDetailViewController: NSViewController {
    weak var delegate: SessionDetailViewControllerDelegate?
    private let session: SessionInfo
    private var summary: SessionSummary?

    private var scrollView: NSScrollView!
    private var contentView: NSView!

    init(session: SessionInfo) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 480))
        loadData()
        setupUI()
    }

    private func loadData() {
        summary = DatabaseManager.shared.getSessionSummary(sessionId: session.sessionId)
    }

    private func setupUI() {
        // Header
        let headerView = createHeaderView()
        view.addSubview(headerView)

        // Scroll view for content
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

        // Build content
        buildContent()
    }

    private func createHeaderView() -> NSView {
        let header = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 50))

        // Back button
        let backButton = NSButton(title: "← 返回", target: self, action: #selector(backTapped))
        backButton.bezelStyle = .regularSquare
        backButton.isBordered = false
        backButton.frame = NSRect(x: 8, y: 12, width: 60, height: 28)
        header.addSubview(backButton)

        // Title
        let goalText = String(session.originalGoal.prefix(25))
        let titleLabel = NSTextField(labelWithString: goalText)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 70, y: 15, width: 280, height: 20)
        header.addSubview(titleLabel)

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

        // Jump button
        let jumpButton = NSButton(title: "跳转终端", target: self, action: #selector(jumpTapped))
        jumpButton.bezelStyle = .rounded
        jumpButton.frame = NSRect(x: 12, y: 10, width: 80, height: 30)
        footer.addSubview(jumpButton)

        // Copy button
        let copyButton = NSButton(title: "复制摘要", target: self, action: #selector(copyTapped))
        copyButton.bezelStyle = .rounded
        copyButton.frame = NSRect(x: 100, y: 10, width: 80, height: 30)
        footer.addSubview(copyButton)

        return footer
    }

    private func buildContent() {
        var yOffset: CGFloat = 0
        let padding: CGFloat = 12
        let sectionSpacing: CGFloat = 16

        // Section 1: Original Goal
        let goalSection = createGoalSection()
        goalSection.frame.origin = CGPoint(x: padding, y: yOffset)
        contentView.addSubview(goalSection)
        yOffset += goalSection.frame.height + sectionSpacing

        // Section 2: Timeline
        let timelineSection = createTimelineSection()
        timelineSection.frame.origin = CGPoint(x: padding, y: yOffset)
        contentView.addSubview(timelineSection)
        yOffset += timelineSection.frame.height + sectionSpacing

        // Section 3: Todos
        let todosSection = createTodosSection()
        todosSection.frame.origin = CGPoint(x: padding, y: yOffset)
        contentView.addSubview(todosSection)
        yOffset += todosSection.frame.height + sectionSpacing

        // Set content view size
        let totalHeight = max(yOffset, scrollView.frame.height)
        contentView.frame = NSRect(x: 0, y: 0, width: 336, height: totalHeight)

        // Flip coordinates for scroll view
        flipContentCoordinates(totalHeight: totalHeight)
    }

    private func flipContentCoordinates(totalHeight: CGFloat) {
        for subview in contentView.subviews {
            subview.frame.origin.y = totalHeight - subview.frame.origin.y - subview.frame.height
        }
    }

    private func createGoalSection() -> NSView {
        let section = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: 80))

        // Section title
        let titleLabel = NSTextField(labelWithString: "🎯 原始目标")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 0, y: 60, width: 336, height: 18)
        section.addSubview(titleLabel)

        // Goal text box
        let goalBox = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: 55))
        goalBox.wantsLayer = true
        goalBox.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        goalBox.layer?.cornerRadius = 6
        goalBox.layer?.borderWidth = 1
        goalBox.layer?.borderColor = NSColor.separatorColor.cgColor

        let goalLabel = NSTextField(wrappingLabelWithString: session.originalGoal)
        goalLabel.font = NSFont.systemFont(ofSize: 12)
        goalLabel.frame = NSRect(x: 8, y: 8, width: 320, height: 40)
        goalLabel.maximumNumberOfLines = 2
        goalLabel.lineBreakMode = .byTruncatingTail
        goalBox.addSubview(goalLabel)

        section.addSubview(goalBox)
        return section
    }

    private func createTimelineSection() -> NSView {
        let timeline = summary?.timeline ?? []
        let nodeHeight: CGFloat = 50
        let sectionHeight = 20 + CGFloat(max(timeline.count, 1)) * nodeHeight

        let section = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: sectionHeight))

        // Section title
        let titleLabel = NSTextField(labelWithString: "📊 进度时间线")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 0, y: sectionHeight - 20, width: 336, height: 18)
        section.addSubview(titleLabel)

        if timeline.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "暂无时间线数据")
            emptyLabel.font = NSFont.systemFont(ofSize: 12)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.frame = NSRect(x: 0, y: sectionHeight - 50, width: 336, height: 20)
            section.addSubview(emptyLabel)
        } else {
            var nodeY = sectionHeight - 25
            for node in timeline {
                let nodeView = createTimelineNode(node: node)
                nodeView.frame.origin = CGPoint(x: 0, y: nodeY - nodeHeight)
                section.addSubview(nodeView)
                nodeY -= nodeHeight
            }
        }

        return section
    }

    private func createTimelineNode(node: TimelineNode) -> NSView {
        let nodeView = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: 45))

        // Status indicator
        let statusEmoji = getTimelineEmoji(type: node.type, status: node.status)
        let statusLabel = NSTextField(labelWithString: statusEmoji)
        statusLabel.font = NSFont.systemFont(ofSize: 14)
        statusLabel.frame = NSRect(x: 0, y: 15, width: 24, height: 20)
        nodeView.addSubview(statusLabel)

        // Time
        let timeLabel = NSTextField(labelWithString: node.time)
        timeLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.frame = NSRect(x: 28, y: 25, width: 50, height: 16)
        nodeView.addSubview(timeLabel)

        // Title
        let titleLabel = NSTextField(labelWithString: node.title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.frame = NSRect(x: 80, y: 25, width: 256, height: 16)
        nodeView.addSubview(titleLabel)

        // Description
        let descLabel = NSTextField(labelWithString: node.description)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.frame = NSRect(x: 80, y: 8, width: 256, height: 16)
        nodeView.addSubview(descLabel)

        // Vertical line (connector)
        let line = NSView(frame: NSRect(x: 10, y: 0, width: 2, height: 12))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        nodeView.addSubview(line)

        return nodeView
    }

    private func getTimelineEmoji(type: String, status: String) -> String {
        if status == "current" {
            return "◐"
        }
        switch type {
        case "start":
            return "●"
        case "milestone":
            return "◆"
        case "waiting":
            return "◐"
        case "permission":
            return "◐"
        case "complete":
            return "✓"
        case "input":
            return "▸"
        default:
            return "○"
        }
    }

    private func createTodosSection() -> NSView {
        let todos = summary?.progress?.todos ?? []
        let completedTodos = todos.filter { $0.status == "completed" }
        let pendingTodos = todos.filter { $0.status != "completed" }

        let todoHeight: CGFloat = 22
        let completedHeight = CGFloat(max(completedTodos.count, 1)) * todoHeight + 25
        let pendingHeight = CGFloat(max(pendingTodos.count, 1)) * todoHeight + 25
        let sectionHeight = 20 + completedHeight + pendingHeight + 10

        let section = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: sectionHeight))

        var yOffset = sectionHeight

        // Completed section
        yOffset -= 20
        let completedTitle = NSTextField(labelWithString: "✅ 已完成 (\(completedTodos.count))")
        completedTitle.font = NSFont.boldSystemFont(ofSize: 12)
        completedTitle.frame = NSRect(x: 0, y: yOffset, width: 336, height: 18)
        section.addSubview(completedTitle)

        yOffset -= 5
        if completedTodos.isEmpty {
            yOffset -= todoHeight
            let emptyLabel = NSTextField(labelWithString: "暂无已完成项")
            emptyLabel.font = NSFont.systemFont(ofSize: 11)
            emptyLabel.textColor = .tertiaryLabelColor
            emptyLabel.frame = NSRect(x: 12, y: yOffset, width: 320, height: 18)
            section.addSubview(emptyLabel)
        } else {
            for todo in completedTodos.prefix(5) {
                yOffset -= todoHeight
                let todoLabel = NSTextField(labelWithString: "• \(todo.content)")
                todoLabel.font = NSFont.systemFont(ofSize: 11)
                todoLabel.textColor = .secondaryLabelColor
                todoLabel.lineBreakMode = .byTruncatingTail
                todoLabel.frame = NSRect(x: 12, y: yOffset, width: 320, height: 18)
                section.addSubview(todoLabel)
            }
            if completedTodos.count > 5 {
                yOffset -= todoHeight
                let moreLabel = NSTextField(labelWithString: "...还有 \(completedTodos.count - 5) 项")
                moreLabel.font = NSFont.systemFont(ofSize: 11)
                moreLabel.textColor = .tertiaryLabelColor
                moreLabel.frame = NSRect(x: 12, y: yOffset, width: 320, height: 18)
                section.addSubview(moreLabel)
            }
        }

        // Pending section
        yOffset -= 15
        let pendingTitle = NSTextField(labelWithString: "⏳ 待完成 (\(pendingTodos.count))")
        pendingTitle.font = NSFont.boldSystemFont(ofSize: 12)
        pendingTitle.frame = NSRect(x: 0, y: yOffset, width: 336, height: 18)
        section.addSubview(pendingTitle)

        yOffset -= 5
        if pendingTodos.isEmpty {
            yOffset -= todoHeight
            let emptyLabel = NSTextField(labelWithString: "暂无待完成项")
            emptyLabel.font = NSFont.systemFont(ofSize: 11)
            emptyLabel.textColor = .tertiaryLabelColor
            emptyLabel.frame = NSRect(x: 12, y: yOffset, width: 320, height: 18)
            section.addSubview(emptyLabel)
        } else {
            for todo in pendingTodos.prefix(5) {
                yOffset -= todoHeight
                let todoLabel = NSTextField(labelWithString: "• \(todo.content)")
                todoLabel.font = NSFont.systemFont(ofSize: 11)
                todoLabel.lineBreakMode = .byTruncatingTail
                todoLabel.frame = NSRect(x: 12, y: yOffset, width: 320, height: 18)
                section.addSubview(todoLabel)
            }
            if pendingTodos.count > 5 {
                yOffset -= todoHeight
                let moreLabel = NSTextField(labelWithString: "...还有 \(pendingTodos.count - 5) 项")
                moreLabel.font = NSFont.systemFont(ofSize: 11)
                moreLabel.textColor = .tertiaryLabelColor
                moreLabel.frame = NSRect(x: 12, y: yOffset, width: 320, height: 18)
                section.addSubview(moreLabel)
            }
        }

        return section
    }

    // MARK: - Actions

    @objc private func backTapped() {
        delegate?.sessionDetailDidRequestBack()
    }

    @objc private func jumpTapped() {
        delegate?.sessionDetailDidRequestJump(session)
    }

    @objc private func copyTapped() {
        var text = "任务: \(session.originalGoal)\n"
        text += "状态: \(session.currentStatus)\n"
        text += "项目: \(session.project)\n"

        if let progress = summary?.progress {
            text += "进度: \(progress.completed)/\(progress.total)\n"
        }

        if let timeline = summary?.timeline, !timeline.isEmpty {
            text += "\n时间线:\n"
            for node in timeline {
                text += "  \(node.time) \(node.title): \(node.description)\n"
            }
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        log("DETAIL: Copied summary to clipboard")
    }
}
