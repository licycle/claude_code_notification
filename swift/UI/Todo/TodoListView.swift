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
        tv.rowHeight = 44
        tv.intercellSpacing = NSSize(width: 0, height: 1)
        tv.headerView = nil
        tv.delegate = self
        tv.dataSource = self
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
        let button = NSButton(title: "+", target: self, action: #selector(createTaskClicked))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.font = .boldSystemFont(ofSize: 14)
        button.toolTip = "Create new task"
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

        addSubview(filterSegment)
        addSubview(createButton)
        addSubview(statsLabel)
        addSubview(scrollView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            filterSegment.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            filterSegment.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),

            createButton.centerYAnchor.constraint(equalTo: filterSegment.centerYAnchor),
            createButton.leadingAnchor.constraint(equalTo: filterSegment.trailingAnchor, constant: 12),
            createButton.widthAnchor.constraint(equalToConstant: 30),

            statsLabel.centerYAnchor.constraint(equalTo: filterSegment.centerYAnchor),
            statsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: filterSegment.bottomAnchor, constant: 8),
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
        sheet.onTaskCreated = { [weak self] taskId, shouldDecompose in
            if shouldDecompose {
                // Run decomposition in background
                let projects = DatabaseManager.shared.getUniqueProjects(limit: 5)
                BackgroundTaskRunner.shared.runDecompose(taskId: taskId, projects: projects) { success, message in
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
        updateStatsLabel()
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

    // MARK: - Actions

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
        let row = tableView.selectedRow
        guard row >= 0 && row < todos.count else { return }

        let todo = todos[row]
        // Post notification to show detail
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowTodoDetail"),
            object: nil,
            userInfo: ["todoId": todo.id]
        )
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
