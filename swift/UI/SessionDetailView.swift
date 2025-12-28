import AppKit

// MARK: - Timeline Node View with Mouse Tracking
// 支持鼠标追踪的时间线节点视图
// 当鼠标悬停 0.5 秒后触发 hover 回调

class TimelineNodeView: NSView {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var hoverTimer: Timer?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // 移除现有的追踪区域
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        // 创建新的追踪区域
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        // 延迟 0.5 秒显示 popover
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.onHover?(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        // 取消定时器并立即隐藏
        hoverTimer?.invalidate()
        hoverTimer = nil
        onHover?(false)
    }

    deinit {
        // 清理定时器
        hoverTimer?.invalidate()
    }
}

// MARK: - Session Detail View Controller Delegate
// 会话详情视图控制器代理协议
// 用于处理返回和跳转终端的回调

protocol SessionDetailViewControllerDelegate: AnyObject {
    /// 用户点击返回按钮时调用
    func sessionDetailDidRequestBack()
    /// 用户点击跳转终端按钮时调用
    func sessionDetailDidRequestJump(_ session: SessionInfo)
}

// MARK: - Session Detail View Controller
// 会话详情视图控制器
// 显示单个会话的详细信息，包括：
// 1. 原始目标（固定高度，内部可滚动）
// 2. 进度时间线（固定高度，内部可滚动）
// 3. 已完成/待完成的 Todo 列表（固定高度，内部可滚动）

class SessionDetailViewController: NSViewController {

    // MARK: - Properties

    weak var delegate: SessionDetailViewControllerDelegate?

    /// 当前显示的会话信息
    private let session: SessionInfo

    /// 会话摘要数据（包含 timeline 和 progress）
    private var summary: SessionSummary?

    /// 会话模式（ai/raw）
    private var summaryMode: String?

    /// 当前显示的 popover（用于显示节点详情）
    private var currentPopover: NSPopover?

    // MARK: - Initialization

    init(session: SessionInfo) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override func loadView() {
        // 创建主视图，尺寸与 Popover 一致
        view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 480))

        // 从数据库加载会话摘要数据
        loadData()

        // 构建 UI
        setupUI()
    }

    // MARK: - Data Loading

    /// 从数据库加载会话摘要数据
    /// 包括 timeline（时间线事件）和 progress（Todo 进度）
    private func loadData() {
        summary = DatabaseManager.shared.getSessionSummary(sessionId: session.sessionId)
        summaryMode = DatabaseManager.shared.getSummaryMode(sessionId: session.sessionId)
        log("DETAIL: Loaded summary for session \(session.sessionId), timeline count: \(summary?.timeline.count ?? 0), mode: \(summaryMode ?? "nil")")
    }

    // MARK: - UI Setup

    /// 设置整体 UI 布局
    /// 布局结构（从下往上，NSView 坐标系原点在左下角）：
    /// - Footer: y=0, height=50
    /// - Todo: y=50, height=110
    /// - Timeline: y=160, height=180
    /// - Goal: y=340, height=90
    /// - Header: y=430, height=50
    /// 总高度: 50 + 110 + 180 + 90 + 50 = 480px
    private func setupUI() {
        let padding: CGFloat = 12
        let contentWidth: CGFloat = 336  // 360 - 2*12

        // Footer: y=0, height=45
        let footerView = createFooterView()
        footerView.frame = NSRect(x: 0, y: -5, width: 360, height: 45)
        view.addSubview(footerView)

        // Todo: y=50, height=110
        let todosSection = createTodosSection()
        todosSection.frame = NSRect(x: padding, y: 50, width: contentWidth, height: 110)
        view.addSubview(todosSection)

        // Timeline: y=160, height=180
        let timelineSection = createTimelineSection()
        timelineSection.frame = NSRect(x: padding, y: 160, width: contentWidth, height: 180)
        view.addSubview(timelineSection)

        // Goal: y=340, height=90
        let goalSection = createGoalSection()
        goalSection.frame = NSRect(x: padding, y: 340, width: contentWidth, height: 90)
        view.addSubview(goalSection)

        // Header: y=430, height=45
        let headerView = createHeaderView()
        headerView.frame = NSRect(x: 0, y: 430, width: 360, height: 45)
        view.addSubview(headerView)
    }

    /// 创建顶部导航栏
    /// 包含返回按钮和任务标题
    private func createHeaderView() -> NSView {
        let header = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 50))

        // 返回按钮
        let backButton = NSButton(title: L(.detail_back), target: self, action: #selector(backTapped))
        backButton.bezelStyle = .regularSquare
        backButton.isBordered = false
        backButton.frame = NSRect(x: 8, y: 12, width: 60, height: 28)
        header.addSubview(backButton)

        // 任务标题（包含模式标记 + 截取目标）
        let modeTag = summaryMode != nil ? "[\(summaryMode!.uppercased())] " : ""
        let goalText = "\(modeTag)\(String(session.originalGoal.prefix(22)))"
        let titleLabel = NSTextField(labelWithString: goalText)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 70, y: 15, width: 280, height: 20)
        header.addSubview(titleLabel)

        // 底部分隔线
        let separator = NSBox(frame: NSRect(x: 0, y: 0, width: 360, height: 1))
        separator.boxType = .separator
        header.addSubview(separator)

        return header
    }

    /// 创建底部操作栏
    /// 包含跳转终端和复制摘要按钮
    private func createFooterView() -> NSView {
        let footer = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 50))

        // 顶部分隔线
        let separator = NSBox(frame: NSRect(x: 0, y: 49, width: 360, height: 1))
        separator.boxType = .separator
        footer.addSubview(separator)

        // 跳转终端按钮
        let jumpButton = NSButton(title: L(.detail_jump_terminal), target: self, action: #selector(jumpTapped))
        jumpButton.bezelStyle = .rounded
        jumpButton.frame = NSRect(x: 12, y: 10, width: 80, height: 30)
        footer.addSubview(jumpButton)

        // 复制摘要按钮
        let copyButton = NSButton(title: L(.detail_copy_summary), target: self, action: #selector(copyTapped))
        copyButton.bezelStyle = .rounded
        copyButton.frame = NSRect(x: 100, y: 10, width: 80, height: 30)
        footer.addSubview(copyButton)

        return footer
    }

    // MARK: - Section Builders

    /// 创建原始目标区域
    /// 固定高度 90px，内部可滚动
    private func createGoalSection() -> NSView {
        let section = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: 90))

        // 区域标题（在顶部）
        let titleLabel = NSTextField(labelWithString: L(.detail_original_goal))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 0, y: 70, width: 336, height: 18)
        section.addSubview(titleLabel)

        // 可滚动的文本视图容器（在标题下方）
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 336, height: 65))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .lineBorder
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 6

        // 文本视图（只读、可选择）
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 65))
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor.controlBackgroundColor
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.string = session.originalGoal

        scrollView.documentView = textView
        section.addSubview(scrollView)

        return section
    }

    /// 创建进度时间线区域
    /// 固定高度 180px（标题 20px + 滚动区域 160px）
    private func createTimelineSection() -> NSView {
        let section = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: 180))
        let timeline = summary?.timeline ?? []

        // 区域标题（在顶部）
        let titleLabel = NSTextField(labelWithString: L(.detail_timeline) + " (\(timeline.count))")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 0, y: 160, width: 336, height: 18)
        section.addSubview(titleLabel)

        // 创建滚动视图容器（固定高度 155px）
        let scrollViewHeight: CGFloat = 155
        let timelineScrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 336, height: scrollViewHeight))
        timelineScrollView.hasVerticalScroller = true
        timelineScrollView.hasHorizontalScroller = false
        timelineScrollView.autohidesScrollers = true
        timelineScrollView.drawsBackground = false
        timelineScrollView.borderType = .lineBorder
        timelineScrollView.wantsLayer = true
        timelineScrollView.layer?.cornerRadius = 6

        // 创建内容视图
        let nodeHeight: CGFloat = 45
        let contentHeight = max(CGFloat(timeline.count) * nodeHeight, scrollViewHeight)
        let timelineContentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: contentHeight))

        if timeline.isEmpty {
            // 无数据时显示提示
            let emptyLabel = NSTextField(labelWithString: L(.detail_timeline_empty))
            emptyLabel.font = NSFont.systemFont(ofSize: 12)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.frame = NSRect(x: 10, y: contentHeight - 30, width: 300, height: 20)
            timelineContentView.addSubview(emptyLabel)
        } else {
            // 遍历时间线节点，从上到下显示（最新的在顶部）
            var nodeY = contentHeight
            for node in timeline {
                nodeY -= nodeHeight
                let nodeView = createTimelineNode(node: node)
                nodeView.frame.origin = CGPoint(x: 5, y: nodeY)
                timelineContentView.addSubview(nodeView)
            }
        }

        timelineScrollView.documentView = timelineContentView

        // 滚动到顶部（显示最新的事件）
        if contentHeight > scrollViewHeight {
            let topY = contentHeight - scrollViewHeight
            timelineScrollView.contentView.scroll(to: NSPoint(x: 0, y: topY))
            timelineScrollView.reflectScrolledClipView(timelineScrollView.contentView)
        }

        section.addSubview(timelineScrollView)

        return section
    }

    /// 显示节点详情 popover
    private func showNodeDetail(relativeTo view: NSView, title: String, description: String) {
        // 关闭现有 popover
        currentPopover?.close()

        let popover = NSPopover()
        popover.contentViewController = TimelineNodeDetailPopover(title: title, description: description)
        popover.behavior = .semitransient  // 移开鼠标时自动关闭
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxX)
        currentPopover = popover
    }

    /// 隐藏节点详情 popover
    private func hideNodeDetail() {
        currentPopover?.close()
        currentPopover = nil
    }

    /// 创建单个时间线节点视图
    private func createTimelineNode(node: TimelineNode) -> NSView {
        let nodeView = TimelineNodeView(frame: NSRect(x: 0, y: 0, width: 320, height: 42))

        // 状态指示图标
        let statusEmoji = getTimelineEmoji(type: node.type, status: node.status)
        let statusLabel = NSTextField(labelWithString: statusEmoji)
        statusLabel.font = NSFont.systemFont(ofSize: 14)
        statusLabel.frame = NSRect(x: 0, y: 12, width: 24, height: 20)
        nodeView.addSubview(statusLabel)

        // 时间标签（HH:mm 格式）
        let timeLabel = NSTextField(labelWithString: node.time)
        timeLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.frame = NSRect(x: 26, y: 22, width: 45, height: 16)
        nodeView.addSubview(timeLabel)

        // 节点标题
        let titleLabel = NSTextField(labelWithString: node.title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 75, y: 22, width: 240, height: 16)
        nodeView.addSubview(titleLabel)

        // 节点描述
        let descLabel = NSTextField(labelWithString: node.description)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.frame = NSRect(x: 75, y: 5, width: 240, height: 16)
        nodeView.addSubview(descLabel)

        // 垂直连接线
        let line = NSView(frame: NSRect(x: 10, y: 0, width: 2, height: 8))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        nodeView.addSubview(line)

        // 设置 hover 回调
        nodeView.onHover = { [weak self, weak nodeView] isHovering in
            guard let self = self, let nodeView = nodeView else { return }

            if isHovering {
                // 显示 popover（使用 fullDescription 显示完整内容）
                self.showNodeDetail(
                    relativeTo: nodeView,
                    title: node.title,
                    description: node.fullDescription
                )
            } else {
                // 隐藏 popover
                self.hideNodeDetail()
            }
        }

        return nodeView
    }

    /// 根据节点类型和状态返回对应的图标符号
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
        case "permission", "permission_request":
            return "🔐"
        case "complete":
            return "✓"
        case "input":
            return "▸"
        case "idle":
            return "💤"
        case "working":
            return "⚙️"
        case "rate_limited":
            return "⚠️"
        case "progress":
            return "📝"
        case "ai_summary":
            return "🤖"
        case "subagent_start", "subagent_working":
            return "🤖"
        case "subagent_stop":
            return "✅"
        default:
            return "○"
        }
    }

    /// 创建 Todo 列表区域
    /// 固定高度 110px，内部可滚动
    private func createTodosSection() -> NSView {
        let section = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: 110))
        let todos = summary?.progress?.todos ?? []

        // 分离已完成和待完成的 Todo
        let completedTodos = todos.filter { $0.status == "completed" }
        let pendingTodos = todos.filter { $0.status != "completed" }

        // 区域标题（在顶部）
        let titleLabel = NSTextField(labelWithString: L(.detail_todo) + " (\(completedTodos.count)/\(todos.count))")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 0, y: 90, width: 336, height: 18)
        section.addSubview(titleLabel)

        // 创建滚动视图容器（固定高度 85px）
        let scrollViewHeight: CGFloat = 85
        let todosScrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 336, height: scrollViewHeight))
        todosScrollView.hasVerticalScroller = true
        todosScrollView.hasHorizontalScroller = false
        todosScrollView.autohidesScrollers = true
        todosScrollView.drawsBackground = false
        todosScrollView.borderType = .lineBorder
        todosScrollView.wantsLayer = true
        todosScrollView.layer?.cornerRadius = 6

        // 计算内容高度
        let todoItemHeight: CGFloat = 20
        let sectionTitleHeight: CGFloat = 22
        let spacing: CGFloat = 8

        let completedContentHeight = completedTodos.isEmpty ? todoItemHeight : CGFloat(completedTodos.count) * todoItemHeight
        let pendingContentHeight = pendingTodos.isEmpty ? todoItemHeight : CGFloat(pendingTodos.count) * todoItemHeight
        let totalContentHeight = sectionTitleHeight + completedContentHeight + spacing + sectionTitleHeight + pendingContentHeight + spacing

        let contentHeight = max(totalContentHeight, scrollViewHeight)
        let todosContentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: contentHeight))

        var yOffset = contentHeight

        // ===== 待完成部分（先显示）=====
        yOffset -= sectionTitleHeight
        let pendingTitle = NSTextField(labelWithString: "⏳ " + L(.detail_todo_pending) + " (\(pendingTodos.count))")
        pendingTitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        pendingTitle.frame = NSRect(x: 5, y: yOffset, width: 310, height: 18)
        todosContentView.addSubview(pendingTitle)

        if pendingTodos.isEmpty {
            yOffset -= todoItemHeight
            let emptyLabel = NSTextField(labelWithString: L(.detail_todo_none))
            emptyLabel.font = NSFont.systemFont(ofSize: 11)
            emptyLabel.textColor = .tertiaryLabelColor
            emptyLabel.frame = NSRect(x: 15, y: yOffset, width: 300, height: 16)
            todosContentView.addSubview(emptyLabel)
        } else {
            for todo in pendingTodos {
                yOffset -= todoItemHeight
                let todoLabel = NSTextField(labelWithString: "• \(todo.content)")
                todoLabel.font = NSFont.systemFont(ofSize: 11)
                todoLabel.lineBreakMode = .byTruncatingTail
                todoLabel.frame = NSRect(x: 15, y: yOffset, width: 300, height: 16)
                todoLabel.toolTip = todo.content
                todosContentView.addSubview(todoLabel)
            }
        }

        // ===== 已完成部分（后显示）=====
        yOffset -= spacing + sectionTitleHeight
        let completedTitle = NSTextField(labelWithString: "✅ " + L(.detail_todo_completed) + " (\(completedTodos.count))")
        completedTitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        completedTitle.frame = NSRect(x: 5, y: yOffset, width: 310, height: 18)
        todosContentView.addSubview(completedTitle)

        if completedTodos.isEmpty {
            yOffset -= todoItemHeight
            let emptyLabel = NSTextField(labelWithString: L(.detail_todo_none))
            emptyLabel.font = NSFont.systemFont(ofSize: 11)
            emptyLabel.textColor = .tertiaryLabelColor
            emptyLabel.frame = NSRect(x: 15, y: yOffset, width: 300, height: 16)
            todosContentView.addSubview(emptyLabel)
        } else {
            for todo in completedTodos {
                yOffset -= todoItemHeight
                let todoLabel = NSTextField(labelWithString: "• \(todo.content)")
                todoLabel.font = NSFont.systemFont(ofSize: 11)
                todoLabel.textColor = .secondaryLabelColor
                todoLabel.lineBreakMode = .byTruncatingTail
                todoLabel.frame = NSRect(x: 15, y: yOffset, width: 300, height: 16)
                todoLabel.toolTip = todo.content
                todosContentView.addSubview(todoLabel)
            }
        }

        todosScrollView.documentView = todosContentView

        // 滚动到顶部
        if contentHeight > scrollViewHeight {
            let topY = contentHeight - scrollViewHeight
            todosScrollView.contentView.scroll(to: NSPoint(x: 0, y: topY))
            todosScrollView.reflectScrolledClipView(todosScrollView.contentView)
        }

        section.addSubview(todosScrollView)

        return section
    }

    // MARK: - Actions

    /// 返回按钮点击事件
    @objc private func backTapped() {
        delegate?.sessionDetailDidRequestBack()
    }

    /// 跳转终端按钮点击事件
    @objc private func jumpTapped() {
        delegate?.sessionDetailDidRequestJump(session)
    }

    /// 复制摘要按钮点击事件
    @objc private func copyTapped() {
        var text = L(.copy_task) + " \(session.originalGoal)\n"
        text += L(.copy_status) + " \(session.currentStatus)\n"
        text += L(.copy_project) + " \(session.project)\n"

        if let progress = summary?.progress {
            text += L(.copy_progress) + " \(progress.completed)/\(progress.total)\n"
        }

        if let timeline = summary?.timeline, !timeline.isEmpty {
            text += "\n" + L(.copy_timeline) + "\n"
            for node in timeline {
                text += "  \(node.time) \(node.title): \(node.fullDescription)\n"
            }
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        log("DETAIL: Copied summary to clipboard")
    }
}
