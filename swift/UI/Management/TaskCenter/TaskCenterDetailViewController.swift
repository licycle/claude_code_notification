import AppKit

// MARK: - Flipped View for Top-to-Bottom Layout

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Task Center Detail View Controller Delegate

protocol TaskCenterDetailViewControllerDelegate: AnyObject {
    func taskCenterDetailDidRequestBack()
    func taskCenterDetailDidRequestJump(_ session: SessionInfo)
}

// MARK: - Task Center Detail View Controller

class TaskCenterDetailViewController: NSViewController {

    weak var delegate: TaskCenterDetailViewControllerDelegate?

    private let session: SessionInfo
    private var summary: SessionSummary?
    private var summaryMode: String?
    private var sessionUsage: SessionUsage?
    private var timelineDuration: (start: Date, end: Date)?
    private var currentPopover: NSPopover?

    init(session: SessionInfo) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 870, height: 600))
        view.wantsLayer = true
        loadData()
        setupUI()
    }

    private func loadData() {
        summary = DatabaseManager.shared.getSessionSummary(sessionId: session.sessionId)
        summaryMode = DatabaseManager.shared.getSummaryMode(sessionId: session.sessionId)
        sessionUsage = DatabaseManager.shared.getSessionUsage(sessionId: session.sessionId)
        timelineDuration = DatabaseManager.shared.getTimelineDuration(sessionId: session.sessionId)
    }

    private func setupUI() {
        let padding: CGFloat = 20

        // Header: 顶部导航栏 (使用 Auto Layout)
        let headerView = createHeaderView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        // Footer: 底部操作栏 (使用 Auto Layout)
        let footerView = createFooterView()
        footerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footerView)

        // 左侧区域：目标 + 时间线
        let leftColumn = createLeftColumn()
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(leftColumn)

        // 右侧区域：Todo + 会话信息
        let rightColumn = createRightColumn()
        rightColumn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rightColumn)

        // Auto Layout 约束
        NSLayoutConstraint.activate([
            // Header 固定在顶部
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50),

            // Footer 固定在底部
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 60),

            // 左侧列
            leftColumn.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            leftColumn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            leftColumn.bottomAnchor.constraint(equalTo: footerView.topAnchor),
            leftColumn.widthAnchor.constraint(equalToConstant: 400),

            // 右侧列
            rightColumn.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            rightColumn.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: padding),
            rightColumn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            rightColumn.bottomAnchor.constraint(equalTo: footerView.topAnchor)
        ])
    }

    // MARK: - Header

    private func createHeaderView() -> NSView {
        let header = NSView(frame: NSRect(x: 0, y: 0, width: 870, height: 50))

        let backButton = NSButton(title: L(.detail_back_list), target: self, action: #selector(backTapped))
        backButton.bezelStyle = .rounded
        backButton.frame = NSRect(x: 20, y: 10, width: 100, height: 30)
        header.addSubview(backButton)

        let modeTag = summaryMode != nil ? "[\(summaryMode!.uppercased())] " : ""
        let goalText = "\(modeTag)\(String(session.originalGoal.prefix(50)))"
        let titleLabel = NSTextField(labelWithString: goalText)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 130, y: 15, width: 720, height: 24)
        header.addSubview(titleLabel)

        let separator = NSBox(frame: NSRect(x: 0, y: 0, width: 870, height: 1))
        separator.boxType = .separator
        header.addSubview(separator)

        return header
    }

    // MARK: - Footer

    private func createFooterView() -> NSView {
        let footer = NSView(frame: NSRect(x: 0, y: 0, width: 870, height: 60))

        let separator = NSBox(frame: NSRect(x: 0, y: 59, width: 870, height: 1))
        separator.boxType = .separator
        footer.addSubview(separator)

        let jumpButton = NSButton(title: L(.detail_jump_terminal), target: self, action: #selector(jumpTapped))
        jumpButton.bezelStyle = .rounded
        jumpButton.frame = NSRect(x: 20, y: 15, width: 100, height: 30)
        footer.addSubview(jumpButton)

        let copyButton = NSButton(title: L(.detail_copy_summary), target: self, action: #selector(copyTapped))
        copyButton.bezelStyle = .rounded
        copyButton.frame = NSRect(x: 130, y: 15, width: 100, height: 30)
        footer.addSubview(copyButton)

        return footer
    }

    // MARK: - Left Column (Goal + Timeline)

    private func createLeftColumn() -> NSView {
        let column = NSView()

        // Goal section (固定高度 120)
        let goalSection = createGoalSection()
        goalSection.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(goalSection)

        // Timeline section (填充剩余空间)
        let timelineSection = createTimelineSection()
        timelineSection.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(timelineSection)

        NSLayoutConstraint.activate([
            goalSection.topAnchor.constraint(equalTo: column.topAnchor, constant: 10),
            goalSection.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            goalSection.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            goalSection.heightAnchor.constraint(equalToConstant: 120),

            timelineSection.topAnchor.constraint(equalTo: goalSection.bottomAnchor, constant: 10),
            timelineSection.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            timelineSection.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            timelineSection.bottomAnchor.constraint(equalTo: column.bottomAnchor, constant: -10)
        ])

        return column
    }

    // MARK: - Right Column (Todo + Info)

    private func createRightColumn() -> NSView {
        let column = NSView()

        // Session info section (固定高度 120)
        let infoSection = createInfoSection()
        infoSection.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(infoSection)

        // Todo section (填充剩余空间)
        let todoSection = createTodosSection()
        todoSection.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(todoSection)

        NSLayoutConstraint.activate([
            infoSection.topAnchor.constraint(equalTo: column.topAnchor, constant: 10),
            infoSection.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            infoSection.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            infoSection.heightAnchor.constraint(equalToConstant: 160),

            todoSection.topAnchor.constraint(equalTo: infoSection.bottomAnchor, constant: 10),
            todoSection.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            todoSection.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            todoSection.bottomAnchor.constraint(equalTo: column.bottomAnchor, constant: -10)
        ])

        return column
    }

    // MARK: - Goal Section

    private func createGoalSection() -> NSView {
        let section = NSView()

        let titleLabel = NSTextField(labelWithString: L(.detail_original_goal))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(titleLabel)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .lineBorder
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 6
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(scrollView)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 95))
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor.controlBackgroundColor
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = session.originalGoal
        scrollView.documentView = textView

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: section.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: 18),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: section.bottomAnchor)
        ])

        return section
    }

    // MARK: - Info Section

    private func createInfoSection() -> NSView {
        let section = NSView()

        let titleLabel = NSTextField(labelWithString: L(.detail_session_info))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(titleLabel)

        let infoBox = NSView()
        infoBox.wantsLayer = true
        infoBox.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        infoBox.layer?.cornerRadius = 6
        infoBox.layer?.borderWidth = 1
        infoBox.layer?.borderColor = NSColor.separatorColor.cgColor
        infoBox.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(infoBox)

        // 内部标签使用固定位置（相对于 infoBox）
        let lineHeight: CGFloat = 22
        var yOffset: CGFloat = 114

        let idLabel = NSTextField(labelWithString: "Session ID: \(session.sessionId.prefix(16))...")
        idLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        idLabel.frame = NSRect(x: 10, y: yOffset, width: 390, height: lineHeight)
        infoBox.addSubview(idLabel)
        yOffset -= lineHeight

        let statusLabel = NSTextField(labelWithString: "\(L(.detail_status)) \(statusText(for: session.currentStatus))")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.frame = NSRect(x: 10, y: yOffset, width: 390, height: lineHeight)
        infoBox.addSubview(statusLabel)
        yOffset -= lineHeight

        let projectLabel = NSTextField(labelWithString: "\(L(.detail_project)) \(shortenPath(session.project))")
        projectLabel.font = NSFont.systemFont(ofSize: 12)
        projectLabel.toolTip = session.project
        projectLabel.frame = NSRect(x: 10, y: yOffset, width: 390, height: lineHeight)
        infoBox.addSubview(projectLabel)
        yOffset -= lineHeight

        // 工作时长（从 timeline 首尾节点计算）
        let durationText: String
        if let duration = timelineDuration {
            durationText = formatDuration(from: duration.start, to: duration.end)
        } else {
            durationText = "-"
        }
        let durationLabel = NSTextField(labelWithString: "\(L(.detail_work_duration)) \(durationText)")
        durationLabel.font = NSFont.systemFont(ofSize: 12)
        durationLabel.frame = NSRect(x: 10, y: yOffset, width: 390, height: lineHeight)
        infoBox.addSubview(durationLabel)
        yOffset -= lineHeight

        // Token 用量
        if let usage = sessionUsage {
            let tokenText = "↓\(usage.formattedInputTokens) ↑\(usage.formattedOutputTokens) (\(usage.formattedTotalTokens) total)"
            let tokenLabel = NSTextField(labelWithString: "\(L(.detail_token_usage)) \(tokenText)")
            tokenLabel.font = NSFont.systemFont(ofSize: 12)
            tokenLabel.frame = NSRect(x: 10, y: yOffset, width: 390, height: lineHeight)
            tokenLabel.toolTip = "\(L(.usage_input_tokens)): \(usage.estimatedInputTokens)\n\(L(.usage_output_tokens)): \(usage.estimatedOutputTokens)\n\(L(.usage_total_estimated)): \(usage.totalEstimatedTokens)"
            infoBox.addSubview(tokenLabel)
        } else {
            let tokenLabel = NSTextField(labelWithString: "\(L(.detail_token_usage)) -")
            tokenLabel.font = NSFont.systemFont(ofSize: 12)
            tokenLabel.textColor = .tertiaryLabelColor
            tokenLabel.frame = NSRect(x: 10, y: yOffset, width: 390, height: lineHeight)
            infoBox.addSubview(tokenLabel)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: section.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: 18),

            infoBox.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            infoBox.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            infoBox.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            infoBox.bottomAnchor.constraint(equalTo: section.bottomAnchor)
        ])

        return section
    }

    /// 格式化时长
    private func formatDuration(from start: Date, to end: Date) -> String {
        let duration = end.timeIntervalSince(start)
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    // MARK: - Timeline Section

    private func createTimelineSection() -> NSView {
        let section = NSView()
        let timeline = summary?.timeline ?? []

        let titleLabel = NSTextField(labelWithString: "\(L(.detail_timeline)) (\(timeline.count))")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(titleLabel)

        let timelineScrollView = NSScrollView()
        timelineScrollView.hasVerticalScroller = true
        timelineScrollView.autohidesScrollers = true
        timelineScrollView.drawsBackground = false
        timelineScrollView.borderType = .lineBorder
        timelineScrollView.wantsLayer = true
        timelineScrollView.layer?.cornerRadius = 6
        timelineScrollView.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(timelineScrollView)

        let nodeHeight: CGFloat = 50
        let contentHeight = max(CGFloat(timeline.count) * nodeHeight, nodeHeight)
        let timelineContentView = FlippedView(frame: NSRect(x: 0, y: 0, width: 380, height: contentHeight))

        if timeline.isEmpty {
            let emptyLabel = NSTextField(labelWithString: L(.detail_timeline_empty))
            emptyLabel.font = NSFont.systemFont(ofSize: 13)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.frame = NSRect(x: 10, y: 10, width: 360, height: 20)
            timelineContentView.addSubview(emptyLabel)
        } else {
            var nodeY: CGFloat = 0
            for node in timeline {
                let nodeView = createTimelineNode(node: node)
                nodeView.frame.origin = CGPoint(x: 5, y: nodeY)
                timelineContentView.addSubview(nodeView)
                nodeY += nodeHeight
            }
        }

        timelineScrollView.documentView = timelineContentView

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: section.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: 18),

            timelineScrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            timelineScrollView.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            timelineScrollView.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            timelineScrollView.bottomAnchor.constraint(equalTo: section.bottomAnchor)
        ])

        return section
    }

    private func createTimelineNode(node: TimelineNode) -> NSView {
        let nodeView = TimelineNodeView(frame: NSRect(x: 0, y: 0, width: 380, height: 48))

        let statusEmoji = getTimelineEmoji(type: node.type, status: node.status)
        let statusLabel = NSTextField(labelWithString: statusEmoji)
        statusLabel.font = NSFont.systemFont(ofSize: 16)
        statusLabel.frame = NSRect(x: 0, y: 14, width: 28, height: 22)
        nodeView.addSubview(statusLabel)

        let timeLabel = NSTextField(labelWithString: node.time)
        timeLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.frame = NSRect(x: 30, y: 26, width: 50, height: 18)
        nodeView.addSubview(timeLabel)

        let titleLabel = NSTextField(labelWithString: node.title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 85, y: 26, width: 290, height: 18)
        nodeView.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: node.description)
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.frame = NSRect(x: 85, y: 6, width: 290, height: 18)
        nodeView.addSubview(descLabel)

        let line = NSView(frame: NSRect(x: 12, y: 0, width: 2, height: 10))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        nodeView.addSubview(line)

        // 设置 hover 回调显示完整内容
        nodeView.onHover = { [weak self, weak nodeView] isHovering in
            guard let self = self, let nodeView = nodeView else { return }
            if isHovering {
                self.showNodeDetail(relativeTo: nodeView, title: node.title, description: node.fullDescription)
            } else {
                self.hideNodeDetail()
            }
        }

        return nodeView
    }

    // MARK: - Todos Section

    private func createTodosSection() -> NSView {
        let section = NSView()
        let todos = summary?.progress?.todos ?? []

        let completedTodos = todos.filter { $0.status == "completed" }
        let pendingTodos = todos.filter { $0.status != "completed" }

        let titleLabel = NSTextField(labelWithString: "\(L(.detail_todo)) (\(completedTodos.count)/\(todos.count))")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(titleLabel)

        let todosScrollView = NSScrollView()
        todosScrollView.hasVerticalScroller = true
        todosScrollView.autohidesScrollers = true
        todosScrollView.drawsBackground = false
        todosScrollView.borderType = .lineBorder
        todosScrollView.wantsLayer = true
        todosScrollView.layer?.cornerRadius = 6
        todosScrollView.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(todosScrollView)

        let todoItemHeight: CGFloat = 24
        let sectionTitleHeight: CGFloat = 28
        let spacing: CGFloat = 12

        let completedContentHeight = completedTodos.isEmpty ? todoItemHeight : CGFloat(completedTodos.count) * todoItemHeight
        let pendingContentHeight = pendingTodos.isEmpty ? todoItemHeight : CGFloat(pendingTodos.count) * todoItemHeight
        let contentHeight = sectionTitleHeight + pendingContentHeight + spacing + sectionTitleHeight + completedContentHeight + spacing

        let todosContentView = FlippedView(frame: NSRect(x: 0, y: 0, width: 390, height: contentHeight))

        var yOffset: CGFloat = 3

        // Pending section
        let pendingTitle = NSTextField(labelWithString: "⏳ \(L(.detail_todo_pending)) (\(pendingTodos.count))")
        pendingTitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        pendingTitle.frame = NSRect(x: 10, y: yOffset, width: 370, height: 22)
        todosContentView.addSubview(pendingTitle)
        yOffset += sectionTitleHeight

        if pendingTodos.isEmpty {
            let emptyLabel = NSTextField(labelWithString: L(.detail_todo_none))
            emptyLabel.font = NSFont.systemFont(ofSize: 12)
            emptyLabel.textColor = .tertiaryLabelColor
            emptyLabel.frame = NSRect(x: 20, y: yOffset, width: 360, height: 20)
            todosContentView.addSubview(emptyLabel)
            yOffset += todoItemHeight
        } else {
            for todo in pendingTodos {
                let todoLabel = NSTextField(labelWithString: "• \(todo.content)")
                todoLabel.font = NSFont.systemFont(ofSize: 12)
                todoLabel.lineBreakMode = .byTruncatingTail
                todoLabel.frame = NSRect(x: 20, y: yOffset, width: 360, height: 20)
                todoLabel.toolTip = todo.content
                todosContentView.addSubview(todoLabel)
                yOffset += todoItemHeight
            }
        }

        // Completed section
        yOffset += spacing
        let completedTitle = NSTextField(labelWithString: "✅ \(L(.detail_todo_completed)) (\(completedTodos.count))")
        completedTitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        completedTitle.frame = NSRect(x: 10, y: yOffset, width: 370, height: 22)
        todosContentView.addSubview(completedTitle)
        yOffset += sectionTitleHeight

        if completedTodos.isEmpty {
            let emptyLabel = NSTextField(labelWithString: L(.detail_todo_none))
            emptyLabel.font = NSFont.systemFont(ofSize: 12)
            emptyLabel.textColor = .tertiaryLabelColor
            emptyLabel.frame = NSRect(x: 20, y: yOffset, width: 360, height: 20)
            todosContentView.addSubview(emptyLabel)
        } else {
            for todo in completedTodos {
                let todoLabel = NSTextField(labelWithString: "• \(todo.content)")
                todoLabel.font = NSFont.systemFont(ofSize: 12)
                todoLabel.textColor = .secondaryLabelColor
                todoLabel.lineBreakMode = .byTruncatingTail
                todoLabel.frame = NSRect(x: 20, y: yOffset, width: 360, height: 20)
                todoLabel.toolTip = todo.content
                todosContentView.addSubview(todoLabel)
                yOffset += todoItemHeight
            }
        }

        todosScrollView.documentView = todosContentView

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: section.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: 18),

            todosScrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            todosScrollView.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            todosScrollView.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            todosScrollView.bottomAnchor.constraint(equalTo: section.bottomAnchor)
        ])

        return section
    }

    // MARK: - Helper Methods

    private func getTimelineEmoji(type: String, status: String) -> String {
        if status == "current" { return "◐" }
        switch type {
        case "start": return "●"
        case "milestone": return "◆"
        case "waiting": return "◐"
        case "permission", "permission_request": return "🔐"
        case "complete": return "✓"
        case "input": return "▸"
        case "idle": return "💤"
        case "working": return "⚙️"
        case "rate_limited": return "⚠️"
        case "progress": return "📝"
        case "ai_summary": return "🤖"
        case "subagent_start", "subagent_working": return "🤖"
        case "subagent_stop": return "✅"
        default: return "○"
        }
    }

    private func statusText(for status: String) -> String {
        switch status {
        case "working", "executing_tool", "subagent_working": return "🟢 " + L(.task_status_working)
        case "idle": return "🟡 " + L(.task_status_idle)
        case "waiting_for_user": return "🔴 " + L(.task_status_waiting)
        case "waiting_permission": return "🔐 " + L(.task_status_permission)
        case "completed": return "✅ " + L(.task_status_completed)
        default: return status
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var shortened = path.replacingOccurrences(of: home, with: "~")
        if shortened.count > 40 {
            let components = shortened.split(separator: "/")
            if components.count > 3 {
                shortened = "~/.../" + components.suffix(2).joined(separator: "/")
            }
        }
        return shortened
    }

    // MARK: - Node Detail Popover

    private func showNodeDetail(relativeTo view: NSView, title: String, description: String) {
        currentPopover?.close()

        let popover = NSPopover()
        popover.contentViewController = TimelineNodeDetailPopover(title: title, description: description)
        popover.behavior = .semitransient
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxX)
        currentPopover = popover
    }

    private func hideNodeDetail() {
        currentPopover?.close()
        currentPopover = nil
    }

    // MARK: - Actions

    @objc private func backTapped() {
        delegate?.taskCenterDetailDidRequestBack()
    }

    @objc private func jumpTapped() {
        delegate?.taskCenterDetailDidRequestJump(session)
    }

    @objc private func copyTapped() {
        var text = "\(L(.copy_task)) \(session.originalGoal)\n"
        text += "\(L(.copy_status)) \(session.currentStatus)\n"
        text += "\(L(.copy_project)) \(session.project)\n"

        if let progress = summary?.progress {
            text += "\(L(.copy_progress)) \(progress.completed)/\(progress.total)\n"
        }

        if let timeline = summary?.timeline, !timeline.isEmpty {
            text += "\n\(L(.copy_timeline))\n"
            for node in timeline {
                text += "  \(node.time) \(node.title): \(node.fullDescription)\n"
            }
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
