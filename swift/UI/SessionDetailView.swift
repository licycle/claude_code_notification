import AppKit

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
// 1. 原始目标（可滚动的多行文本框）
// 2. 进度时间线（Raw模式显示用户输入，AI模式显示智能摘要）
// 3. 已完成/待完成的 Todo 列表

class SessionDetailViewController: NSViewController {

    // MARK: - Properties

    weak var delegate: SessionDetailViewControllerDelegate?

    /// 当前显示的会话信息
    private let session: SessionInfo

    /// 会话摘要数据（包含 timeline 和 progress）
    private var summary: SessionSummary?

    /// 主滚动视图
    private var scrollView: NSScrollView!

    /// 内容容器视图
    private var contentView: NSView!

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
        log("DETAIL: Loaded summary for session \(session.sessionId), timeline count: \(summary?.timeline.count ?? 0)")
    }

    // MARK: - UI Setup

    /// 设置整体 UI 布局
    /// 布局结构：Header (50px) + ScrollView (380px) + Footer (50px) = 480px
    private func setupUI() {
        // 顶部导航栏
        let headerView = createHeaderView()
        view.addSubview(headerView)

        // 中间滚动区域（包含所有内容）
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 50, width: 360, height: 380))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        view.addSubview(scrollView)

        // 底部操作栏
        let footerView = createFooterView()
        view.addSubview(footerView)

        // 设置各部分的位置
        headerView.frame = NSRect(x: 0, y: 430, width: 360, height: 50)
        scrollView.frame = NSRect(x: 0, y: 50, width: 360, height: 380)
        footerView.frame = NSRect(x: 0, y: 0, width: 360, height: 50)

        // 构建滚动区域内的内容
        buildContent()
    }

    /// 创建顶部导航栏
    /// 包含返回按钮和任务标题
    private func createHeaderView() -> NSView {
        let header = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 50))

        // 返回按钮
        let backButton = NSButton(title: "← 返回", target: self, action: #selector(backTapped))
        backButton.bezelStyle = .regularSquare
        backButton.isBordered = false
        backButton.frame = NSRect(x: 8, y: 12, width: 60, height: 28)
        header.addSubview(backButton)

        // 任务标题（截取前25个字符）
        let goalText = String(session.originalGoal.prefix(25))
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
        let jumpButton = NSButton(title: "跳转终端", target: self, action: #selector(jumpTapped))
        jumpButton.bezelStyle = .rounded
        jumpButton.frame = NSRect(x: 12, y: 10, width: 80, height: 30)
        footer.addSubview(jumpButton)

        // 复制摘要按钮
        let copyButton = NSButton(title: "复制摘要", target: self, action: #selector(copyTapped))
        copyButton.bezelStyle = .rounded
        copyButton.frame = NSRect(x: 100, y: 10, width: 80, height: 30)
        footer.addSubview(copyButton)

        return footer
    }

    /// 构建滚动区域内的内容
    /// 按顺序添加：原始目标 -> 进度时间线 -> Todo 列表
    private func buildContent() {
        var yOffset: CGFloat = 0
        let padding: CGFloat = 12
        let sectionSpacing: CGFloat = 16

        // Section 1: 原始目标（可滚动的多行文本框）
        let goalSection = createGoalSection()
        goalSection.frame.origin = CGPoint(x: padding, y: yOffset)
        contentView.addSubview(goalSection)
        yOffset += goalSection.frame.height + sectionSpacing

        // Section 2: 进度时间线
        // Raw模式：显示用户输入作为节点
        // AI模式：显示智能摘要节点
        let timelineSection = createTimelineSection()
        timelineSection.frame.origin = CGPoint(x: padding, y: yOffset)
        contentView.addSubview(timelineSection)
        yOffset += timelineSection.frame.height + sectionSpacing

        // Section 3: Todo 列表（已完成 + 待完成）
        let todosSection = createTodosSection()
        todosSection.frame.origin = CGPoint(x: padding, y: yOffset)
        contentView.addSubview(todosSection)
        yOffset += todosSection.frame.height + sectionSpacing

        // 设置内容视图的总高度
        let totalHeight = max(yOffset, scrollView.frame.height)
        contentView.frame = NSRect(x: 0, y: 0, width: 336, height: totalHeight)

        // 翻转坐标系（NSView 默认原点在左下角，需要翻转为左上角）
        flipContentCoordinates(totalHeight: totalHeight)
    }

    /// 翻转内容视图的坐标系
    /// NSView 默认原点在左下角，但我们按从上到下的顺序添加内容
    /// 需要翻转 Y 坐标使内容从顶部开始显示
    private func flipContentCoordinates(totalHeight: CGFloat) {
        for subview in contentView.subviews {
            subview.frame.origin.y = totalHeight - subview.frame.origin.y - subview.frame.height
        }
    }

    // MARK: - Section Builders

    /// 创建原始目标区域
    /// 使用可滚动的 NSTextView 显示完整的用户原始输入
    /// 支持长文本滚动查看
    private func createGoalSection() -> NSView {
        let section = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: 90))

        // 区域标题
        let titleLabel = NSTextField(labelWithString: "🎯 原始目标")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 0, y: 70, width: 336, height: 18)
        section.addSubview(titleLabel)

        // 可滚动的文本视图容器
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
    /// Raw模式：显示用户的每次输入作为节点（user_input 事件）
    /// AI模式：显示 AI 生成的智能摘要节点
    /// 节点类型：
    /// - start: 任务开始（goal_set 事件）
    /// - input: 用户输入（user_input 事件，Raw模式核心）
    /// - milestone: 阶段完成（连续完成3+个todo）
    /// - waiting: 等待决策（waiting_for_user 状态）
    /// - permission: 等待权限（waiting_permission 状态）
    /// - complete: 任务完成
    /// 使用滚动视图，固定显示5个事件的高度
    private func createTimelineSection() -> NSView {
        let timeline = summary?.timeline ?? []
        let nodeHeight: CGFloat = 50
        let maxVisibleNodes: CGFloat = 5
        let scrollViewHeight: CGFloat = maxVisibleNodes * nodeHeight
        let sectionHeight: CGFloat = 20 + scrollViewHeight  // 标题 + 滚动区域

        let section = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: sectionHeight))

        // 区域标题
        let titleLabel = NSTextField(labelWithString: "📊 进度时间线")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 0, y: sectionHeight - 20, width: 336, height: 18)
        section.addSubview(titleLabel)

        // 创建滚动视图容器
        let timelineScrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 336, height: scrollViewHeight))
        timelineScrollView.hasVerticalScroller = true
        timelineScrollView.hasHorizontalScroller = false
        timelineScrollView.autohidesScrollers = true
        timelineScrollView.drawsBackground = false
        timelineScrollView.borderType = .noBorder

        // 创建内容视图
        let contentHeight = CGFloat(max(timeline.count, 1)) * nodeHeight
        let timelineContentView = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: contentHeight))

        if timeline.isEmpty {
            // 无数据时显示提示
            let emptyLabel = NSTextField(labelWithString: "暂无时间线数据")
            emptyLabel.font = NSFont.systemFont(ofSize: 12)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.frame = NSRect(x: 0, y: contentHeight - 30, width: 336, height: 20)
            timelineContentView.addSubview(emptyLabel)
        } else {
            // 遍历时间线节点，从上到下显示
            var nodeY = contentHeight
            for node in timeline {
                nodeY -= nodeHeight
                let nodeView = createTimelineNode(node: node)
                nodeView.frame.origin = CGPoint(x: 0, y: nodeY)
                timelineContentView.addSubview(nodeView)
            }
        }

        timelineScrollView.documentView = timelineContentView
        // 滚动到顶部（显示最新的事件）
        if let documentView = timelineScrollView.documentView {
            documentView.scroll(NSPoint(x: 0, y: documentView.bounds.height))
        }

        section.addSubview(timelineScrollView)

        return section
    }

    /// 创建单个时间线节点视图
    /// 布局：[状态图标] [时间] [标题]
    ///                      [描述]
    /// - Parameter node: 时间线节点数据
    /// hover 时显示完整内容
    private func createTimelineNode(node: TimelineNode) -> NSView {
        let nodeView = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: 45))

        // 状态指示图标（根据节点类型和状态显示不同符号）
        let statusEmoji = getTimelineEmoji(type: node.type, status: node.status)
        let statusLabel = NSTextField(labelWithString: statusEmoji)
        statusLabel.font = NSFont.systemFont(ofSize: 14)
        statusLabel.frame = NSRect(x: 0, y: 15, width: 24, height: 20)
        nodeView.addSubview(statusLabel)

        // 时间标签（HH:mm 格式）
        let timeLabel = NSTextField(labelWithString: node.time)
        timeLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.frame = NSRect(x: 28, y: 25, width: 50, height: 16)
        nodeView.addSubview(timeLabel)

        // 节点标题
        let titleLabel = NSTextField(labelWithString: node.title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.frame = NSRect(x: 80, y: 25, width: 256, height: 16)
        titleLabel.toolTip = node.title  // hover 显示完整标题
        nodeView.addSubview(titleLabel)

        // 节点描述（Raw模式下显示用户原始输入内容）
        let descLabel = NSTextField(labelWithString: node.description)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.frame = NSRect(x: 80, y: 8, width: 256, height: 16)
        descLabel.toolTip = node.description  // hover 显示完整描述
        nodeView.addSubview(descLabel)

        // 整个节点也添加 tooltip，显示完整信息
        nodeView.toolTip = "\(node.title)\n\(node.description)"

        // 垂直连接线（连接相邻节点）
        let line = NSView(frame: NSRect(x: 10, y: 0, width: 2, height: 12))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        nodeView.addSubview(line)

        return nodeView
    }

    /// 根据节点类型和状态返回对应的图标符号
    /// - Parameters:
    ///   - type: 节点类型（start/input/milestone/waiting/permission/complete/idle/working/rate_limited/progress）
    ///   - status: 节点状态（completed/current/pending）
    /// - Returns: 对应的图标符号
    private func getTimelineEmoji(type: String, status: String) -> String {
        // 当前正在进行的节点显示半圆
        if status == "current" {
            return "◐"
        }

        // 根据节点类型返回不同图标
        switch type {
        case "start":
            return "●"      // 任务开始
        case "milestone":
            return "◆"      // 阶段完成
        case "waiting":
            return "◐"      // 等待决策
        case "permission":
            return "◐"      // 等待权限
        case "complete":
            return "✓"      // 任务完成
        case "input":
            return "▸"      // 用户输入（Raw模式核心）
        case "idle":
            return "💤"     // 空闲
        case "working":
            return "⚙️"     // 工作中
        case "rate_limited":
            return "⚠️"     // 限流
        case "progress":
            return "📝"     // 进度更新
        default:
            return "○"      // 默认空心圆
        }
    }

    /// 创建 Todo 列表区域
    /// 分为两部分：已完成项 + 待完成项
    /// 每部分最多显示5项，超出显示"...还有 N 项"
    private func createTodosSection() -> NSView {
        let todos = summary?.progress?.todos ?? []

        // 分离已完成和待完成的 Todo
        let completedTodos = todos.filter { $0.status == "completed" }
        let pendingTodos = todos.filter { $0.status != "completed" }

        // 计算区域高度
        let todoHeight: CGFloat = 22
        let completedHeight = CGFloat(max(completedTodos.count, 1)) * todoHeight + 25
        let pendingHeight = CGFloat(max(pendingTodos.count, 1)) * todoHeight + 25
        let sectionHeight = 20 + completedHeight + pendingHeight + 10

        let section = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: sectionHeight))

        var yOffset = sectionHeight

        // ===== 已完成部分 =====
        yOffset -= 20
        let completedTitle = NSTextField(labelWithString: "✅ 已完成 (\(completedTodos.count))")
        completedTitle.font = NSFont.boldSystemFont(ofSize: 12)
        completedTitle.frame = NSRect(x: 0, y: yOffset, width: 336, height: 18)
        section.addSubview(completedTitle)

        yOffset -= 5
        if completedTodos.isEmpty {
            // 无已完成项时显示提示
            yOffset -= todoHeight
            let emptyLabel = NSTextField(labelWithString: "暂无已完成项")
            emptyLabel.font = NSFont.systemFont(ofSize: 11)
            emptyLabel.textColor = .tertiaryLabelColor
            emptyLabel.frame = NSRect(x: 12, y: yOffset, width: 320, height: 18)
            section.addSubview(emptyLabel)
        } else {
            // 显示已完成的 Todo（最多5项）
            for todo in completedTodos.prefix(5) {
                yOffset -= todoHeight
                let todoLabel = NSTextField(labelWithString: "• \(todo.content)")
                todoLabel.font = NSFont.systemFont(ofSize: 11)
                todoLabel.textColor = .secondaryLabelColor
                todoLabel.lineBreakMode = .byTruncatingTail
                todoLabel.frame = NSRect(x: 12, y: yOffset, width: 320, height: 18)
                section.addSubview(todoLabel)
            }
            // 超过5项时显示剩余数量
            if completedTodos.count > 5 {
                yOffset -= todoHeight
                let moreLabel = NSTextField(labelWithString: "...还有 \(completedTodos.count - 5) 项")
                moreLabel.font = NSFont.systemFont(ofSize: 11)
                moreLabel.textColor = .tertiaryLabelColor
                moreLabel.frame = NSRect(x: 12, y: yOffset, width: 320, height: 18)
                section.addSubview(moreLabel)
            }
        }

        // ===== 待完成部分 =====
        yOffset -= 15
        let pendingTitle = NSTextField(labelWithString: "⏳ 待完成 (\(pendingTodos.count))")
        pendingTitle.font = NSFont.boldSystemFont(ofSize: 12)
        pendingTitle.frame = NSRect(x: 0, y: yOffset, width: 336, height: 18)
        section.addSubview(pendingTitle)

        yOffset -= 5
        if pendingTodos.isEmpty {
            // 无待完成项时显示提示
            yOffset -= todoHeight
            let emptyLabel = NSTextField(labelWithString: "暂无待完成项")
            emptyLabel.font = NSFont.systemFont(ofSize: 11)
            emptyLabel.textColor = .tertiaryLabelColor
            emptyLabel.frame = NSRect(x: 12, y: yOffset, width: 320, height: 18)
            section.addSubview(emptyLabel)
        } else {
            // 显示待完成的 Todo（最多5项）
            for todo in pendingTodos.prefix(5) {
                yOffset -= todoHeight
                let todoLabel = NSTextField(labelWithString: "• \(todo.content)")
                todoLabel.font = NSFont.systemFont(ofSize: 11)
                todoLabel.lineBreakMode = .byTruncatingTail
                todoLabel.frame = NSRect(x: 12, y: yOffset, width: 320, height: 18)
                section.addSubview(todoLabel)
            }
            // 超过5项时显示剩余数量
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

    /// 返回按钮点击事件
    @objc private func backTapped() {
        delegate?.sessionDetailDidRequestBack()
    }

    /// 跳转终端按钮点击事件
    @objc private func jumpTapped() {
        delegate?.sessionDetailDidRequestJump(session)
    }

    /// 复制摘要按钮点击事件
    /// 将任务信息格式化为文本并复制到剪贴板
    @objc private func copyTapped() {
        var text = "任务: \(session.originalGoal)\n"
        text += "状态: \(session.currentStatus)\n"
        text += "项目: \(session.project)\n"

        // 添加进度信息
        if let progress = summary?.progress {
            text += "进度: \(progress.completed)/\(progress.total)\n"
        }

        // 添加时间线信息
        if let timeline = summary?.timeline, !timeline.isEmpty {
            text += "\n时间线:\n"
            for node in timeline {
                text += "  \(node.time) \(node.title): \(node.description)\n"
            }
        }

        // 复制到剪贴板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        log("DETAIL: Copied summary to clipboard")
    }
}
