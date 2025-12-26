import AppKit

// MARK: - Task Center View Controller Delegate

protocol TaskCenterViewControllerDelegate: AnyObject {
    func taskCenterDidRequestShowDetail(_ session: SessionInfo)
}

// MARK: - Task Center View Controller

class TaskCenterViewController: NSViewController {

    weak var delegate: TaskCenterViewControllerDelegate?

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
    private let colAction = NSUserInterfaceItemIdentifier("action")

    // Hover popover
    private var currentPopover: NSPopover?
    private var hoverRow: Int = -1

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 920, height: 650))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupHoverTracking()
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

        // Add columns - Goal/Project 150px, others 80px
        addColumn(id: colMode, title: "Account", width: 80)
        addColumn(id: colSessionId, title: "Session ID", width: 80)
        addColumn(id: colGoal, title: "Goal", width: 150)
        addColumn(id: colStatus, title: "Status", width: 100)
        addColumn(id: colProject, title: "Project", width: 150)
        addColumn(id: colTime, title: "Updated", width: 80)
        addColumn(id: colAction, title: "Action", width: 80)

        scrollView.documentView = tableView

        // Context menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "View Details", action: #selector(showDetail(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Jump to Terminal", action: #selector(jumpToTerminal(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Mark Completed", action: #selector(markCompleted(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Delete", action: #selector(deleteSession(_:)), keyEquivalent: ""))
        tableView.menu = menu
    }

    private func addColumn(id: NSUserInterfaceItemIdentifier, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: id)
        column.title = title
        column.width = width
        column.minWidth = 50
        column.maxWidth = width
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
        statusLabel.stringValue = "\(filteredSessions.count) sessions (total \(sessions.count))"
    }

    // MARK: - Actions

    @objc private func tableDoubleClicked(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0 && row < filteredSessions.count else { return }
        let session = filteredSessions[row]
        // 只有非完成状态才能跳转
        if session.currentStatus != "completed" {
            jumpToTerminalForSession(session)
        }
    }

    @objc private func jumpToTerminal(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0 && row < filteredSessions.count else { return }
        let session = filteredSessions[row]
        // 只有非完成状态才能跳转
        if session.currentStatus != "completed" {
            jumpToTerminalForSession(session)
        }
    }

    @objc private func showDetail(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0 && row < filteredSessions.count else { return }
        let session = filteredSessions[row]
        NotificationCenter.default.post(
            name: .showSessionDetail,
            object: nil,
            userInfo: ["session": session]
        )
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
        alert.messageText = "Confirm Delete"
        alert.informativeText = "Are you sure you want to delete \(rows.count) session(s)? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

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
            let modeText = mode == "ai" ? "[AI]" : "[RAW]"
            let accountText = session.accountAlias.isEmpty ? "" : "[\(session.accountAlias)]"
            cell.stringValue = "\(accountText)\(modeText)"
            cell.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.toolTip = "Account: \(session.accountAlias.isEmpty ? "default" : session.accountAlias)\nMode: \(mode == "ai" ? "AI Summary" : "Raw")"

        case colSessionId:
            cell.stringValue = String(session.sessionId.prefix(8))
            cell.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.toolTip = session.sessionId

        case colGoal:
            cell.stringValue = session.originalGoal
            cell.toolTip = session.originalGoal

        case colStatus:
            cell.stringValue = statusText(for: session.currentStatus)
            cell.textColor = statusColor(for: session.currentStatus)
            cell.toolTip = "Status: \(session.currentStatus)"

        case colProject:
            cell.stringValue = shortenPath(session.project)
            cell.toolTip = session.project

        case colTime:
            cell.stringValue = relativeTime(from: session.lastActivity)
            cell.textColor = .secondaryLabelColor
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            cell.toolTip = formatter.string(from: session.lastActivity)

        case colAction:
            // 返回按钮而不是文本框
            let buttonId = NSUserInterfaceItemIdentifier("ActionButton")
            let button = tableView.makeView(withIdentifier: buttonId, owner: nil) as? NSButton
                ?? NSButton(title: "详情", target: self, action: #selector(detailButtonClicked(_:)))
            button.identifier = buttonId
            button.title = "详情"
            button.bezelStyle = .inline
            button.tag = row
            button.target = self
            button.action = #selector(detailButtonClicked(_:))
            return button

        default:
            break
        }

        return cell
    }

    @objc private func detailButtonClicked(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < filteredSessions.count else { return }
        let session = filteredSessions[row]
        delegate?.taskCenterDidRequestShowDetail(session)
    }

    private func statusText(for status: String) -> String {
        switch status {
        case "working", "executing_tool", "subagent_working": return "🟢 Working"
        case "idle": return "🟡 Idle"
        case "waiting_for_user": return "🔴 Waiting"
        case "waiting_permission": return "🔐 Permission"
        case "completed": return "✅ Completed"
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
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
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

// MARK: - Hover Popover

extension TaskCenterViewController {
    func setupHoverTracking() {
        let trackingArea = NSTrackingArea(
            rect: tableView.bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        tableView.addTrackingArea(trackingArea)
    }

    override func mouseMoved(with event: NSEvent) {
        let locationInWindow = event.locationInWindow
        let locationInTable = tableView.convert(locationInWindow, from: nil)
        let row = tableView.row(at: locationInTable)
        let column = tableView.column(at: locationInTable)

        // Check if hovering over Goal or Project column
        guard row >= 0 && row < filteredSessions.count,
              column >= 0,
              (tableView.tableColumns[column].identifier == colGoal ||
               tableView.tableColumns[column].identifier == colProject) else {
            closePopover()
            hoverRow = -1
            return
        }

        // Don't show again for same row
        if row == hoverRow { return }
        hoverRow = row

        // Show popover with appropriate content
        let session = filteredSessions[row]
        let cellRect = tableView.frameOfCell(atColumn: column, row: row)
        let content = tableView.tableColumns[column].identifier == colGoal
            ? session.originalGoal
            : session.project
        showGoalPopover(goal: content, relativeTo: cellRect)
    }

    override func mouseExited(with event: NSEvent) {
        closePopover()
        hoverRow = -1
    }

    private func showGoalPopover(goal: String, relativeTo rect: NSRect) {
        closePopover()

        let popover = NSPopover()
        popover.behavior = .semitransient

        // 创建可滚动的文本视图
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 280, height: 130))
        textView.string = goal
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let vc = NSViewController()
        vc.view = scrollView
        popover.contentViewController = vc
        popover.show(relativeTo: rect, of: tableView, preferredEdge: .maxY)

        currentPopover = popover
    }

    private func closePopover() {
        currentPopover?.close()
        currentPopover = nil
    }
}
