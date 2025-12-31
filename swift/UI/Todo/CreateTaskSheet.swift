import Cocoa

/// Sheet for creating a new Global Task with optional auto-decomposition
class CreateTaskSheet: NSViewController {

    // MARK: - Callbacks
    var onTaskCreated: ((Int, Bool) -> Void)?  // (taskId, shouldDecompose)
    var onCancel: (() -> Void)?

    // MARK: - UI Components
    private lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Create New Task")
        label.font = .boldSystemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var titleField: NSTextField = {
        let field = NSTextField()
        field.placeholderString = "Task title (required)"
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private lazy var descriptionLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Description:")
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

    private lazy var projectsLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Target Projects (one per line):")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var projectsField: NSTextView = {
        let textView = NSTextView()
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        return textView
    }()

    private lazy var projectsScrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = projectsField
        return scrollView
    }()

    private lazy var priorityLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Priority:")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var priorityPopup: NSPopUpButton = {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: ["Normal", "High", "Urgent"])
        popup.translatesAutoresizingMaskIntoConstraints = false
        return popup
    }()

    private lazy var decomposeCheckbox: NSButton = {
        let button = NSButton(checkboxWithTitle: "Auto-decompose task into Todos (requires claude-todo)", target: nil, action: nil)
        button.state = .on
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var cancelButton: NSButton = {
        let button = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\u{1b}"  // Escape key
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var createButton: NSButton = {
        let button = NSButton(title: "Create Task", target: self, action: #selector(createClicked))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"  // Return key
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var statusLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 450))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadRecentProjects()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(titleLabel)
        view.addSubview(titleField)
        view.addSubview(descriptionLabel)
        view.addSubview(descriptionScrollView)
        view.addSubview(projectsLabel)
        view.addSubview(projectsScrollView)
        view.addSubview(priorityLabel)
        view.addSubview(priorityPopup)
        view.addSubview(decomposeCheckbox)
        view.addSubview(cancelButton)
        view.addSubview(createButton)
        view.addSubview(statusLabel)

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

            // Projects label
            projectsLabel.topAnchor.constraint(equalTo: descriptionScrollView.bottomAnchor, constant: 16),
            projectsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // Projects field
            projectsScrollView.topAnchor.constraint(equalTo: projectsLabel.bottomAnchor, constant: 4),
            projectsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            projectsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            projectsScrollView.heightAnchor.constraint(equalToConstant: 80),

            // Priority
            priorityLabel.topAnchor.constraint(equalTo: projectsScrollView.bottomAnchor, constant: 16),
            priorityLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            priorityPopup.centerYAnchor.constraint(equalTo: priorityLabel.centerYAnchor),
            priorityPopup.leadingAnchor.constraint(equalTo: priorityLabel.trailingAnchor, constant: 8),
            priorityPopup.widthAnchor.constraint(equalToConstant: 120),

            // Decompose checkbox
            decomposeCheckbox.topAnchor.constraint(equalTo: priorityLabel.bottomAnchor, constant: 16),
            decomposeCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // Status label
            statusLabel.topAnchor.constraint(equalTo: decomposeCheckbox.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // Buttons
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            cancelButton.trailingAnchor.constraint(equalTo: createButton.leadingAnchor, constant: -12),

            createButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            createButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    private func loadRecentProjects() {
        // Load unique project paths from sessions
        let projects = DatabaseManager.shared.getUniqueProjects(limit: 10)
        projectsField.string = projects.joined(separator: "\n")
    }

    // MARK: - Actions

    @objc private func cancelClicked() {
        onCancel?()
        dismiss(nil)
    }

    @objc private func createClicked() {
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            showError("Title is required")
            return
        }

        let description = descriptionField.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let priority = priorityPopup.indexOfSelectedItem
        let shouldDecompose = decomposeCheckbox.state == .on

        // Get project paths
        let projects = projectsField.string
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Create global task in database
        let taskId = TodoDatabaseManager.shared.createGlobalTask(
            title: title,
            description: description.isEmpty ? nil : description,
            priority: priority
        )

        guard taskId > 0 else {
            showError("Failed to create task")
            return
        }

        // If not decomposing, create a simple todo for each project
        if !shouldDecompose && !projects.isEmpty {
            for project in projects {
                _ = TodoDatabaseManager.shared.createTodo(
                    globalTaskId: taskId,
                    projectPath: project,
                    title: title,
                    description: description.isEmpty ? nil : description,
                    priority: priority
                )
            }
        }

        // Notify and close
        onTaskCreated?(taskId, shouldDecompose)
        dismiss(nil)
    }

    private func showError(_ message: String) {
        statusLabel.stringValue = "⚠️ " + message
        statusLabel.textColor = .systemRed
        statusLabel.isHidden = false
    }
}
