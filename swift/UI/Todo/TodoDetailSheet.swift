import Cocoa

/// Sheet for viewing and editing a Todo item
class TodoDetailSheet: NSViewController {

    // MARK: - Callbacks
    var onSave: (() -> Void)?
    var onDelete: (() -> Void)?

    // MARK: - Data
    private let todo: ProjectTodoItem
    private let todoDbManager = TodoDatabaseManager.shared

    // MARK: - UI Components
    private lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: L(.todo_edit))
        label.font = .boldSystemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var titleField: NSTextField = {
        let field = NSTextField()
        field.placeholderString = L(.todo_title_placeholder)
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private lazy var descriptionLabel: NSTextField = {
        let label = NSTextField(labelWithString: L(.todo_description))
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var descriptionField: NSTextView = {
        let textView = NSTextView()
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        return textView
    }()

    private lazy var descriptionScrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = descriptionField
        return scrollView
    }()

    private lazy var statusLabel: NSTextField = {
        let label = NSTextField(labelWithString: L(.todo_status))
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var statusPopup: NSPopUpButton = {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: [
            L(.todo_status_pending),
            L(.todo_status_in_progress),
            L(.todo_status_blocked),
            L(.todo_status_completed),
            L(.todo_status_cancelled)
        ])
        popup.translatesAutoresizingMaskIntoConstraints = false
        return popup
    }()

    private lazy var priorityLabel: NSTextField = {
        let label = NSTextField(labelWithString: L(.todo_priority))
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var priorityPopup: NSPopUpButton = {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: [
            L(.todo_priority_normal),
            L(.todo_priority_high),
            L(.todo_priority_urgent)
        ])
        popup.translatesAutoresizingMaskIntoConstraints = false
        return popup
    }()

    private lazy var estimatedLabel: NSTextField = {
        let label = NSTextField(labelWithString: L(.todo_estimated_time))
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var estimatedField: NSTextField = {
        let field = NSTextField()
        field.placeholderString = L(.todo_minutes)
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private lazy var projectLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var cancelButton: NSButton = {
        let button = NSButton(title: L(.cancel), target: self, action: #selector(cancelClicked))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\u{1b}"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var deleteButton: NSButton = {
        let button = NSButton(title: L(.todo_delete), target: self, action: #selector(deleteClicked))
        button.bezelStyle = .rounded
        button.contentTintColor = .systemRed
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var saveButton: NSButton = {
        let button = NSButton(title: L(.save), target: self, action: #selector(saveClicked))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Initialization

    init(todo: ProjectTodoItem) {
        self.todo = todo
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 380))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadTodoData()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(titleLabel)
        view.addSubview(titleField)
        view.addSubview(descriptionLabel)
        view.addSubview(descriptionScrollView)
        view.addSubview(statusLabel)
        view.addSubview(statusPopup)
        view.addSubview(priorityLabel)
        view.addSubview(priorityPopup)
        view.addSubview(estimatedLabel)
        view.addSubview(estimatedField)
        view.addSubview(projectLabel)
        view.addSubview(cancelButton)
        view.addSubview(deleteButton)
        view.addSubview(saveButton)

        NSLayoutConstraint.activate([
            // Title
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // Title field
            titleField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Description label
            descriptionLabel.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // Description field
            descriptionScrollView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 4),
            descriptionScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            descriptionScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            descriptionScrollView.heightAnchor.constraint(equalToConstant: 80),

            // Status
            statusLabel.topAnchor.constraint(equalTo: descriptionScrollView.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusPopup.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            statusPopup.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),
            statusPopup.widthAnchor.constraint(equalToConstant: 140),

            // Priority
            priorityLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            priorityLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            priorityPopup.centerYAnchor.constraint(equalTo: priorityLabel.centerYAnchor),
            priorityPopup.leadingAnchor.constraint(equalTo: priorityLabel.trailingAnchor, constant: 8),
            priorityPopup.widthAnchor.constraint(equalToConstant: 140),

            // Estimated time
            estimatedLabel.topAnchor.constraint(equalTo: priorityLabel.bottomAnchor, constant: 12),
            estimatedLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            estimatedField.centerYAnchor.constraint(equalTo: estimatedLabel.centerYAnchor),
            estimatedField.leadingAnchor.constraint(equalTo: estimatedLabel.trailingAnchor, constant: 8),
            estimatedField.widthAnchor.constraint(equalToConstant: 80),

            // Project label
            projectLabel.topAnchor.constraint(equalTo: estimatedLabel.bottomAnchor, constant: 12),
            projectLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            projectLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Buttons
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            deleteButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            deleteButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 12),

            saveButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    private func loadTodoData() {
        titleField.stringValue = todo.title
        descriptionField.string = todo.description ?? ""

        // Set status
        let statusIndex: Int
        switch todo.status {
        case "pending": statusIndex = 0
        case "in_progress": statusIndex = 1
        case "blocked": statusIndex = 2
        case "completed": statusIndex = 3
        case "cancelled": statusIndex = 4
        default: statusIndex = 0
        }
        statusPopup.selectItem(at: statusIndex)

        // Set priority
        priorityPopup.selectItem(at: todo.priority)

        // Set estimated time
        if let minutes = todo.estimatedMinutes {
            estimatedField.stringValue = "\(minutes)"
        }

        // Set project path
        projectLabel.stringValue = "\(L(.todo_project)) \(todo.projectPath)"
        projectLabel.toolTip = todo.projectPath
    }

    // MARK: - Actions

    @objc private func cancelClicked() {
        dismiss(nil)
    }

    @objc private func deleteClicked() {
        let alert = NSAlert()
        alert.messageText = L(.todo_delete_confirm_title)
        alert.informativeText = L(.todo_delete_confirm_message)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L(.todo_delete))
        alert.addButton(withTitle: L(.cancel))

        if alert.runModal() == .alertFirstButtonReturn {
            if todoDbManager.deleteTodo(id: todo.id) {
                onDelete?()
                dismiss(nil)
            }
        }
    }

    @objc private func saveClicked() {
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            NSSound.beep()
            return
        }

        let description = descriptionField.string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Map status index to string
        let statusValues = ["pending", "in_progress", "blocked", "completed", "cancelled"]
        let status = statusValues[statusPopup.indexOfSelectedItem]

        let priority = priorityPopup.indexOfSelectedItem

        var estimatedMinutes: Int? = nil
        if let minutes = Int(estimatedField.stringValue) {
            estimatedMinutes = minutes
        }

        let success = todoDbManager.updateTodo(
            id: todo.id,
            title: title,
            description: description.isEmpty ? nil : description,
            status: status,
            priority: priority,
            estimatedMinutes: estimatedMinutes
        )

        if success {
            onSave?()
            dismiss(nil)
        } else {
            NSSound.beep()
        }
    }
}
