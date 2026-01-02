import Cocoa

/// Todo List View - displays todos grouped by project with filtering
class TodoListView: NSView {
    // MARK: - Properties

    private var todos: [ProjectTodoItem] = []
    private var globalTasks: [GlobalTaskInfo] = []
    private var selectedFilter: TodoFilter = .all
    private var selectedProjectPath: String?

    private let todoDbManager = TodoDatabaseManager.shared

    // MARK: - UI Components

    private lazy var scrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.drawsBackground = false
        return sv
    }()

    private lazy var tableView: NSTableView = {
        let tv = NSTableView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = .clear
        tv.style = .plain
        tv.selectionHighlightStyle = .regular
        tv.allowsMultipleSelection = true
        tv.rowHeight = 44
        tv.intercellSpacing = NSSize(width: 0, height: 1)
        tv.headerView = nil
        tv.delegate = self
        tv.dataSource = self
        tv.menu = createContextMenu()
        tv.doubleAction = #selector(tableDoubleClicked)
        tv.target = self
        return tv
    }()

    private lazy var filterSegment: NSSegmentedControl = {
        let seg = NSSegmentedControl(labels: [
            L(.filter_all_status),
            "Pending",
            L(.filter_working),
            L(.filter_completed)
        ], trackingMode: .selectOne, target: self, action: #selector(filterChanged))
        seg.translatesAutoresizingMaskIntoConstraints = false
        seg.selectedSegment = 0
        return seg
    }()

    private lazy var statsLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }()

    private lazy var emptyLabel: NSTextField = {
        let label = NSTextField(labelWithString: L(.session_list_empty))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.isHidden = true
        return label
    }()

    private lazy var createButton: NSButton = {
        let button = NSButton(title: "＋ Create Task", target: self, action: #selector(createTaskClicked))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.toolTip = "Create new task"
        return button
    }()

    private lazy var refreshButton: NSButton = {
        let button = NSButton(title: "↻", target: self, action: #selector(refreshClicked))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 14)
        button.toolTip = "Refresh list"
        return button
    }()

    // MARK: - Batch Operation UI Components

    private lazy var batchToolbar: NSStackView = {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.isHidden = true
        return stack
    }()

    private lazy var selectedCountLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }()

    private lazy var batchCompleteButton: NSButton = {
        let button = NSButton(title: "✓ " + L(.todo_batch_complete), target: self, action: #selector(batchMarkCompleteClicked))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12)
        return button
    }()

    private lazy var batchPendingButton: NSButton = {
        let button = NSButton(title: "○ " + L(.todo_batch_pending), target: self, action: #selector(batchMarkPendingClicked))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12)
        return button
    }()

    private lazy var batchDeleteButton: NSButton = {
        let button = NSButton(title: "🗑 " + L(.todo_batch_delete), target: self, action: #selector(batchDeleteClicked))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12)
        button.contentTintColor = .systemRed
        return button
    }()

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        setupObservers()
        loadData()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupObservers()
        loadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupUI() {
        // Add column to table
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TodoColumn"))
        column.width = 400
        tableView.addTableColumn(column)

        scrollView.documentView = tableView

        // Setup batch toolbar
        batchToolbar.addArrangedSubview(selectedCountLabel)
        batchToolbar.addArrangedSubview(batchCompleteButton)
        batchToolbar.addArrangedSubview(batchPendingButton)
        batchToolbar.addArrangedSubview(batchDeleteButton)

        addSubview(filterSegment)
        addSubview(createButton)
        addSubview(refreshButton)
        addSubview(statsLabel)
        addSubview(batchToolbar)
        addSubview(scrollView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            // Create button at top left - more prominent
            createButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            createButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),

            // Refresh button next to create
            refreshButton.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),
            refreshButton.leadingAnchor.constraint(equalTo: createButton.trailingAnchor, constant: 8),
            refreshButton.widthAnchor.constraint(equalToConstant: 30),

            // Filter segment after buttons
            filterSegment.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),
            filterSegment.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 12),

            statsLabel.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),
            statsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            // Batch toolbar below filter row
            batchToolbar.topAnchor.constraint(equalTo: createButton.bottomAnchor, constant: 8),
            batchToolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            batchToolbar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            batchToolbar.heightAnchor.constraint(equalToConstant: 28),

            scrollView.topAnchor.constraint(equalTo: batchToolbar.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @objc private func createTaskClicked() {
        // Find the window to present sheet
        guard let window = self.window else { return }

        let sheet = CreateTaskSheet()
        sheet.onTaskCreated = { [weak self] taskId, shouldDecompose, apiProfile, accountAlias, projects in
            log("TodoListView: onTaskCreated callback - taskId=\(taskId), shouldDecompose=\(shouldDecompose), account=\(accountAlias ?? "default"), projects=\(projects)")
            if shouldDecompose && !projects.isEmpty {
                log("TodoListView: Starting decomposition...")
                // Run decomposition in background with user-provided projects
                BackgroundTaskRunner.shared.runDecompose(
                    taskId: taskId,
                    projects: projects,
                    apiProfile: apiProfile,
                    accountAlias: accountAlias
                ) { success, message in
                    if success {
                        log("Task \(taskId) decomposed successfully")
                    } else {
                        log("Task \(taskId) decomposition failed: \(message ?? "unknown error")")
                    }
                    self?.loadData()
                }
            } else {
                self?.loadData()
            }
        }

        window.contentViewController?.presentAsSheet(sheet)
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: LocalizationManager.languageChangedNotification,
            object: nil
        )
    }

    @objc private func languageDidChange() {
        filterSegment.setLabel(L(.filter_all_status), forSegment: 0)
        filterSegment.setLabel("Pending", forSegment: 1)
        filterSegment.setLabel(L(.filter_working), forSegment: 2)
        filterSegment.setLabel(L(.filter_completed), forSegment: 3)
        emptyLabel.stringValue = L(.session_list_empty)
        // Update batch toolbar buttons
        batchCompleteButton.title = "✓ " + L(.todo_batch_complete)
        batchPendingButton.title = "○ " + L(.todo_batch_pending)
        batchDeleteButton.title = "🗑 " + L(.todo_batch_delete)
        updateStatsLabel()
        updateBatchToolbar()
    }

    // MARK: - Data Loading

    func loadData() {
        var status: String?
        switch selectedFilter {
        case .pending:
            status = "pending"
        case .inProgress:
            status = "in_progress"
        case .completed:
            status = "completed"
        default:
            status = nil
        }

        todos = todoDbManager.listTodos(
            projectPath: selectedProjectPath,
            status: status,
            includeChildren: true,
            limit: 100
        )

        globalTasks = todoDbManager.listGlobalTasks(status: "active", limit: 20)

        tableView.reloadData()
        emptyLabel.isHidden = !todos.isEmpty
        updateStatsLabel()
    }

    func refresh() {
        loadData()
    }

    private func updateStatsLabel() {
        let pending = todos.filter { $0.isPending }.count
        let inProgress = todos.filter { $0.isInProgress }.count
        let completed = todos.filter { $0.isCompleted }.count

        statsLabel.stringValue = "\(pending) pending · \(inProgress) active · \(completed) done"
    }

    // MARK: - Batch Toolbar

    private func updateBatchToolbar() {
        let selectedCount = tableView.selectedRowIndexes.count
        if selectedCount > 1 {
            batchToolbar.isHidden = false
            let format = L(.todo_selected_count)
            selectedCountLabel.stringValue = String(format: format, selectedCount)
        } else {
            batchToolbar.isHidden = true
        }
    }

    private func getSelectedTodoIds() -> [Int] {
        return tableView.selectedRowIndexes.compactMap { row in
            guard row < todos.count else { return nil }
            return todos[row].id
        }
    }

    // MARK: - Context Menu

    private func createContextMenu() -> NSMenu {
        let menu = NSMenu()

        let editItem = NSMenuItem(title: L(.todo_edit), action: #selector(editTodoClicked), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        menu.addItem(NSMenuItem.separator())

        let completeItem = NSMenuItem(title: L(.todo_mark_complete), action: #selector(markCompleteClicked), keyEquivalent: "")
        completeItem.target = self
        menu.addItem(completeItem)

        let pendingItem = NSMenuItem(title: L(.todo_mark_pending), action: #selector(markPendingClicked), keyEquivalent: "")
        pendingItem.target = self
        menu.addItem(pendingItem)

        menu.addItem(NSMenuItem.separator())

        let deleteItem = NSMenuItem(title: L(.todo_delete), action: #selector(deleteTodoClicked), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)

        return menu
    }

    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 && row < todos.count else { return }
        showEditSheet(for: todos[row])
    }

    @objc private func editTodoClicked() {
        let row = tableView.clickedRow
        guard row >= 0 && row < todos.count else { return }
        showEditSheet(for: todos[row])
    }

    @objc private func markCompleteClicked() {
        let row = tableView.clickedRow
        guard row >= 0 && row < todos.count else { return }
        let todo = todos[row]
        if todoDbManager.updateTodo(id: todo.id, status: "completed") {
            loadData()
        }
    }

    @objc private func markPendingClicked() {
        let row = tableView.clickedRow
        guard row >= 0 && row < todos.count else { return }
        let todo = todos[row]
        if todoDbManager.updateTodo(id: todo.id, status: "pending") {
            loadData()
        }
    }

    @objc private func deleteTodoClicked() {
        let row = tableView.clickedRow
        guard row >= 0 && row < todos.count else { return }
        let todo = todos[row]

        // Show confirmation alert
        let alert = NSAlert()
        alert.messageText = L(.todo_delete_confirm_title)
        alert.informativeText = L(.todo_delete_confirm_message)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L(.todo_delete))
        alert.addButton(withTitle: L(.cancel))

        if alert.runModal() == .alertFirstButtonReturn {
            if todoDbManager.deleteTodo(id: todo.id) {
                loadData()
            }
        }
    }

    private func showEditSheet(for todo: ProjectTodoItem) {
        guard let window = self.window else { return }

        let sheet = TodoDetailSheet(todo: todo)
        sheet.onSave = { [weak self] in
            self?.loadData()
        }
        sheet.onDelete = { [weak self] in
            self?.loadData()
        }

        window.contentViewController?.presentAsSheet(sheet)
    }

    // MARK: - Actions

    @objc private func refreshClicked() {
        log("TodoListView: refreshClicked")
        loadData()
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: selectedFilter = .all
        case 1: selectedFilter = .pending
        case 2: selectedFilter = .inProgress
        case 3: selectedFilter = .completed
        default: selectedFilter = .all
        }
        loadData()
    }

    // MARK: - Batch Actions

    @objc private func batchMarkCompleteClicked() {
        let ids = getSelectedTodoIds()
        guard !ids.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = L(.todo_batch_confirm_title)
        alert.informativeText = String(format: L(.todo_batch_confirm_message), ids.count)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L(.todo_batch_complete))
        alert.addButton(withTitle: L(.cancel))

        if alert.runModal() == .alertFirstButtonReturn {
            let updated = todoDbManager.updateTodosStatus(ids: ids, status: "completed")
            log("TodoListView: Batch marked \(updated) todos as completed")
            loadData()
        }
    }

    @objc private func batchMarkPendingClicked() {
        let ids = getSelectedTodoIds()
        guard !ids.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = L(.todo_batch_confirm_title)
        alert.informativeText = String(format: L(.todo_batch_confirm_message), ids.count)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L(.todo_batch_pending))
        alert.addButton(withTitle: L(.cancel))

        if alert.runModal() == .alertFirstButtonReturn {
            let updated = todoDbManager.updateTodosStatus(ids: ids, status: "pending")
            log("TodoListView: Batch marked \(updated) todos as pending")
            loadData()
        }
    }

    @objc private func batchDeleteClicked() {
        let ids = getSelectedTodoIds()
        guard !ids.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = L(.todo_batch_confirm_title)
        alert.informativeText = String(format: L(.todo_batch_confirm_message), ids.count)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L(.todo_batch_delete))
        alert.addButton(withTitle: L(.cancel))

        if alert.runModal() == .alertFirstButtonReturn {
            let deleted = todoDbManager.deleteTodos(ids: ids)
            log("TodoListView: Batch deleted \(deleted) todos")
            loadData()
        }
    }

    // MARK: - Filter Types

    enum TodoFilter {
        case all
        case pending
        case inProgress
        case completed
    }
}

// MARK: - NSTableViewDelegate & DataSource

extension TodoListView: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return todos.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < todos.count else { return nil }
        let todo = todos[row]

        let cell = TodoRowView()
        cell.configure(with: todo)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < todos.count else { return 44 }
        let todo = todos[row]

        // Adjust height if has children
        if let children = todo.children, !children.isEmpty {
            return 44 + CGFloat(children.count * 28)
        }
        return 44
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // Update batch toolbar visibility
        updateBatchToolbar()

        // Only post detail notification for single selection
        let selectedRows = tableView.selectedRowIndexes
        if selectedRows.count == 1, let row = selectedRows.first, row < todos.count {
            let todo = todos[row]
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowTodoDetail"),
                object: nil,
                userInfo: ["todoId": todo.id]
            )
        }
    }
}

// MARK: - Todo Row View

class TodoRowView: NSTableCellView {
    private let statusIcon = NSTextField(labelWithString: "")
    private let priorityIcon = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let projectLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let childrenStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.font = .systemFont(ofSize: 14)

        priorityIcon.translatesAutoresizingMaskIntoConstraints = false
        priorityIcon.font = .systemFont(ofSize: 10)
        priorityIcon.textColor = .systemOrange

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail

        projectLabel.translatesAutoresizingMaskIntoConstraints = false
        projectLabel.font = .systemFont(ofSize: 11)
        projectLabel.textColor = .secondaryLabelColor

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .tertiaryLabelColor

        childrenStack.translatesAutoresizingMaskIntoConstraints = false
        childrenStack.orientation = .vertical
        childrenStack.alignment = .leading
        childrenStack.spacing = 2

        addSubview(statusIcon)
        addSubview(priorityIcon)
        addSubview(titleLabel)
        addSubview(projectLabel)
        addSubview(timeLabel)
        addSubview(childrenStack)

        NSLayoutConstraint.activate([
            statusIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            statusIcon.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            statusIcon.widthAnchor.constraint(equalToConstant: 20),

            priorityIcon.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 4),
            priorityIcon.centerYAnchor.constraint(equalTo: statusIcon.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: priorityIcon.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: statusIcon.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),

            projectLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            projectLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            timeLabel.centerYAnchor.constraint(equalTo: statusIcon.centerYAnchor),

            childrenStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor, constant: 16),
            childrenStack.topAnchor.constraint(equalTo: projectLabel.bottomAnchor, constant: 4),
            childrenStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    func configure(with todo: ProjectTodoItem) {
        statusIcon.stringValue = todo.statusIcon
        statusIcon.textColor = colorForStatus(todo.status)

        priorityIcon.stringValue = todo.priority > 0 ? todo.priorityIcon : ""

        titleLabel.stringValue = todo.title
        titleLabel.textColor = todo.isCompleted ? .secondaryLabelColor : .labelColor

        projectLabel.stringValue = todo.projectName
        timeLabel.stringValue = todo.estimatedTimeFormatted ?? ""

        // Configure children
        childrenStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let children = todo.children {
            for child in children.prefix(5) {
                let childRow = createChildRow(child)
                childrenStack.addArrangedSubview(childRow)
            }
            if children.count > 5 {
                let moreLabel = NSTextField(labelWithString: "+\(children.count - 5) more...")
                moreLabel.font = .systemFont(ofSize: 10)
                moreLabel.textColor = .tertiaryLabelColor
                childrenStack.addArrangedSubview(moreLabel)
            }
        }
    }

    private func createChildRow(_ child: ProjectTodoItem) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4

        let icon = NSTextField(labelWithString: child.statusIcon)
        icon.font = .systemFont(ofSize: 10)
        icon.textColor = colorForStatus(child.status)

        let title = NSTextField(labelWithString: child.title)
        title.font = .systemFont(ofSize: 11)
        title.textColor = child.isCompleted ? .tertiaryLabelColor : .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail

        row.addArrangedSubview(icon)
        row.addArrangedSubview(title)

        return row
    }

    private func colorForStatus(_ status: String) -> NSColor {
        switch status {
        case "pending": return .systemGray
        case "in_progress": return .systemBlue
        case "blocked": return .systemRed
        case "completed": return .systemGreen
        case "cancelled": return .systemGray
        default: return .labelColor
        }
    }
}
