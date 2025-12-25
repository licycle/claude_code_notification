import AppKit

// MARK: - Task Center View Controller

class TaskCenterViewController: NSViewController {

    private var filterBar: TaskFilterBar!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var statusLabel: NSTextField!

    private var sessions: [SessionInfo] = []
    private var filteredSessions: [SessionInfo] = []

    private var currentSearchKeyword: String = ""
    private var currentStatusFilter: String?
    private var currentAccountFilter: String?

    // Table column identifiers
    private let colMode = NSUserInterfaceItemIdentifier("mode")
    private let colSessionId = NSUserInterfaceItemIdentifier("sessionId")
    private let colGoal = NSUserInterfaceItemIdentifier("goal")
    private let colStatus = NSUserInterfaceItemIdentifier("status")
    private let colProject = NSUserInterfaceItemIdentifier("project")
    private let colTime = NSUserInterfaceItemIdentifier("time")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 600))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadData()
    }

    private func setupUI() {
        // Filter bar (44px height)
        filterBar = TaskFilterBar(frame: .zero)
        filterBar.delegate = self
        filterBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterBar)

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // Table view
        setupTableView()

        // Layout
        NSLayoutConstraint.activate([
            filterBar.topAnchor.constraint(equalTo: view.topAnchor),
            filterBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterBar.heightAnchor.constraint(equalToConstant: 44),

            scrollView.topAnchor.constraint(equalTo: filterBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
    }

    private func setupTableView() {
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        view.addSubview(scrollView)

        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 36
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.doubleAction = #selector(tableDoubleClicked(_:))
        tableView.target = self

        // Add columns
        addColumn(id: colMode, title: "模式", width: 50)
        addColumn(id: colSessionId, title: "Session ID", width: 80)
        addColumn(id: colGoal, title: "目标", width: 200)
        addColumn(id: colStatus, title: "状态", width: 80)
        addColumn(id: colProject, title: "项目", width: 150)
        addColumn(id: colTime, title: "更新时间", width: 100)

        scrollView.documentView = tableView

        // Context menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "跳转终端", action: #selector(jumpToTerminal(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "标记完成", action: #selector(markCompleted(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "删除", action: #selector(deleteSession(_:)), keyEquivalent: ""))
        tableView.menu = menu
    }

    private func addColumn(id: NSUserInterfaceItemIdentifier, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: id)
        column.title = title
        column.width = width
        column.minWidth = 40
        tableView.addTableColumn(column)
    }

    // MARK: - Data Loading

    func loadData() {
        sessions = DatabaseManager.shared.getAllSessions(limit: 200)
        applyFilters()
    }

    func refresh() {
        loadData()
        filterBar.reloadAccounts()
    }

    private func applyFilters() {
        filteredSessions = sessions

        // Apply status filter
        if let status = currentStatusFilter {
            filteredSessions = filteredSessions.filter { session in
                switch status {
                case "working":
                    return ["working", "executing_tool", "subagent_working"].contains(session.currentStatus)
                case "waiting_for_user":
                    return ["waiting_for_user", "waiting_permission"].contains(session.currentStatus)
                default:
                    return session.currentStatus == status
                }
            }
        }

        // Apply account filter
        if let account = currentAccountFilter {
            filteredSessions = filteredSessions.filter { $0.accountAlias == account }
        }

        // Apply search
        if !currentSearchKeyword.isEmpty {
            let keyword = currentSearchKeyword.lowercased()
            filteredSessions = filteredSessions.filter {
                $0.sessionId.lowercased().contains(keyword) ||
                $0.originalGoal.lowercased().contains(keyword) ||
                $0.project.lowercased().contains(keyword)
            }
        }

        tableView.reloadData()
        updateStatusLabel()
    }

    private func updateStatusLabel() {
        statusLabel.stringValue = "共 \(filteredSessions.count) 个会话（总计 \(sessions.count) 个）"
    }

    // MARK: - Actions

    @objc private func tableDoubleClicked(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0 && row < filteredSessions.count else { return }
        jumpToTerminalForSession(filteredSessions[row])
    }

    @objc private func jumpToTerminal(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0 && row < filteredSessions.count else { return }
        jumpToTerminalForSession(filteredSessions[row])
    }

    private func jumpToTerminalForSession(_ session: SessionInfo) {
        NotificationCenter.default.post(
            name: .jumpToTerminal,
            object: nil,
            userInfo: [
                "bundleId": session.bundleId ?? "com.apple.Terminal",
                "terminalPid": session.terminalPid ?? 0,
                "windowId": session.windowId ?? 0
            ]
        )
    }

    @objc private func markCompleted(_ sender: Any) {
        let rows = tableView.selectedRowIndexes
        for row in rows {
            guard row < filteredSessions.count else { continue }
            let session = filteredSessions[row]
            _ = DatabaseManager.shared.updateSessionStatus(sessionId: session.sessionId, newStatus: "completed")
        }
        refresh()
    }

    @objc private func deleteSession(_ sender: Any) {
        let rows = tableView.selectedRowIndexes
        guard !rows.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "确认删除"
        alert.informativeText = "确定要删除选中的 \(rows.count) 个会话吗？此操作不可撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            for row in rows.reversed() {
                guard row < filteredSessions.count else { continue }
                let session = filteredSessions[row]
                _ = DatabaseManager.shared.deleteSession(sessionId: session.sessionId)
            }
            refresh()
        }
    }
}

// MARK: - NSTableViewDataSource

extension TaskCenterViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredSessions.count
    }
}

// MARK: - NSTableViewDelegate

extension TaskCenterViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredSessions.count, let column = tableColumn else { return nil }

        let session = filteredSessions[row]
        let cellId = NSUserInterfaceItemIdentifier("Cell")

        let cell = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField
            ?? NSTextField(labelWithString: "")
        cell.identifier = cellId
        cell.lineBreakMode = .byTruncatingTail

        switch column.identifier {
        case colMode:
            let mode = DatabaseManager.shared.getSummaryMode(sessionId: session.sessionId)
            cell.stringValue = mode == "ai" ? "🤖" : "📝"
            cell.alignment = .center

        case colSessionId:
            cell.stringValue = String(session.sessionId.prefix(8))
            cell.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        case colGoal:
            cell.stringValue = session.originalGoal
            cell.toolTip = session.originalGoal

        case colStatus:
            cell.stringValue = statusText(for: session.currentStatus)
            cell.textColor = statusColor(for: session.currentStatus)

        case colProject:
            cell.stringValue = shortenPath(session.project)
            cell.toolTip = session.project

        case colTime:
            cell.stringValue = relativeTime(from: session.lastActivity)
            cell.textColor = .secondaryLabelColor

        default:
            break
        }

        return cell
    }

    private func statusText(for status: String) -> String {
        switch status {
        case "working", "executing_tool", "subagent_working": return "🟢 工作中"
        case "idle": return "🟡 空闲"
        case "waiting_for_user": return "🔴 等待决策"
        case "waiting_permission": return "🔐 等待权限"
        case "completed": return "✅ 已完成"
        default: return status
        }
    }

    private func statusColor(for status: String) -> NSColor {
        switch status {
        case "working", "executing_tool", "subagent_working": return .systemGreen
        case "idle": return .systemYellow
        case "waiting_for_user", "waiting_permission": return .systemRed
        case "completed": return .systemGray
        default: return .labelColor
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var shortened = path.replacingOccurrences(of: home, with: "~")
        if shortened.count > 30 {
            let components = shortened.split(separator: "/")
            if components.count > 3 {
                shortened = "~/.../" + components.suffix(2).joined(separator: "/")
            }
        }
        return shortened
    }

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        return "\(Int(interval / 86400))天前"
    }
}

// MARK: - TaskFilterBarDelegate

extension TaskCenterViewController: TaskFilterBarDelegate {
    func filterBarDidChangeSearch(_ keyword: String) {
        currentSearchKeyword = keyword
        applyFilters()
    }

    func filterBarDidChangeStatus(_ status: String?) {
        currentStatusFilter = status
        applyFilters()
    }

    func filterBarDidChangeAccount(_ account: String?) {
        currentAccountFilter = account
        applyFilters()
    }

    func filterBarDidRequestRefresh() {
        refresh()
    }
}
