import Cocoa

/// Sheet for creating a new Global Task or Todo
class CreateTaskSheet: NSViewController {

    // MARK: - Mode
    enum CreateMode: Int {
        case globalTask = 0  // Create global task with optional decomposition
        case singleTodo = 1  // Create single todo directly
    }

    // MARK: - Callbacks
    var onTaskCreated: ((Int, Bool, String?, String?, [String]) -> Void)?  // (taskId, shouldDecompose, apiProfile, accountAlias, projects)
    var onTodoCreated: ((Int) -> Void)?  // (todoId)
    var onCancel: (() -> Void)?

    // MARK: - Data
    private var apiProfiles: [String] = []
    private var accounts: [String] = []
    private var currentMode: CreateMode = .globalTask

    // MARK: - UI Components
    private lazy var modeSegment: NSSegmentedControl = {
        let seg = NSSegmentedControl(labels: [
            L(.create_mode_task),
            L(.create_mode_todo)
        ], trackingMode: .selectOne, target: self, action: #selector(modeChanged))
        seg.selectedSegment = 0
        seg.translatesAutoresizingMaskIntoConstraints = false
        return seg
    }()

    private lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: L(.create_task_title))
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
        let button = NSButton(checkboxWithTitle: L(.create_task_decompose), target: self, action: #selector(decomposeChanged))
        button.state = .on
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var apiProfileLabel: NSTextField = {
        let label = NSTextField(labelWithString: L(.create_task_api_profile))
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var apiProfilePopup: NSPopUpButton = {
        let popup = NSPopUpButton()
        popup.translatesAutoresizingMaskIntoConstraints = false
        return popup
    }()

    private lazy var accountLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Account:")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var accountPopup: NSPopUpButton = {
        let popup = NSPopUpButton()
        popup.translatesAutoresizingMaskIntoConstraints = false
        return popup
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
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadRecentProjects()
        loadAPIProfiles()
        loadAccounts()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(modeSegment)
        view.addSubview(titleLabel)
        view.addSubview(titleField)
        view.addSubview(descriptionLabel)
        view.addSubview(descriptionScrollView)
        view.addSubview(projectsLabel)
        view.addSubview(projectsScrollView)
        view.addSubview(priorityLabel)
        view.addSubview(priorityPopup)
        view.addSubview(decomposeCheckbox)
        view.addSubview(apiProfileLabel)
        view.addSubview(apiProfilePopup)
        view.addSubview(accountLabel)
        view.addSubview(accountPopup)
        view.addSubview(cancelButton)
        view.addSubview(createButton)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            // Mode segment at top
            modeSegment.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            modeSegment.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // Title label
            titleLabel.topAnchor.constraint(equalTo: modeSegment.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // Title field
            titleField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Description label (for Todo mode only)
            descriptionLabel.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // Description field (for Todo mode only)
            descriptionScrollView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 4),
            descriptionScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            descriptionScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            descriptionScrollView.heightAnchor.constraint(equalToConstant: 60),

            // Projects label
            projectsLabel.topAnchor.constraint(equalTo: descriptionScrollView.bottomAnchor, constant: 12),
            projectsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // Projects field
            projectsScrollView.topAnchor.constraint(equalTo: projectsLabel.bottomAnchor, constant: 4),
            projectsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            projectsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            projectsScrollView.heightAnchor.constraint(equalToConstant: 60),

            // Priority (for Todo mode only)
            priorityLabel.topAnchor.constraint(equalTo: projectsScrollView.bottomAnchor, constant: 12),
            priorityLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            priorityPopup.centerYAnchor.constraint(equalTo: priorityLabel.centerYAnchor),
            priorityPopup.leadingAnchor.constraint(equalTo: priorityLabel.trailingAnchor, constant: 8),
            priorityPopup.widthAnchor.constraint(equalToConstant: 120),

            // Decompose checkbox (for Task mode only)
            decomposeCheckbox.topAnchor.constraint(equalTo: projectsScrollView.bottomAnchor, constant: 12),
            decomposeCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // API Profile selection (for Task mode only)
            apiProfileLabel.topAnchor.constraint(equalTo: decomposeCheckbox.bottomAnchor, constant: 8),
            apiProfileLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            apiProfilePopup.centerYAnchor.constraint(equalTo: apiProfileLabel.centerYAnchor),
            apiProfilePopup.leadingAnchor.constraint(equalTo: apiProfileLabel.trailingAnchor, constant: 8),
            apiProfilePopup.widthAnchor.constraint(equalToConstant: 200),

            // Account selection (for Task mode only)
            accountLabel.topAnchor.constraint(equalTo: apiProfileLabel.bottomAnchor, constant: 8),
            accountLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            accountPopup.centerYAnchor.constraint(equalTo: accountLabel.centerYAnchor),
            accountPopup.leadingAnchor.constraint(equalTo: accountLabel.trailingAnchor, constant: 8),
            accountPopup.widthAnchor.constraint(equalToConstant: 200),

            // Status label
            statusLabel.topAnchor.constraint(equalTo: accountLabel.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // Buttons
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            cancelButton.trailingAnchor.constraint(equalTo: createButton.leadingAnchor, constant: -12),

            createButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            createButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        // Initially update UI based on mode
        updateUIForMode()
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        currentMode = CreateMode(rawValue: sender.selectedSegment) ?? .globalTask
        updateUIForMode()
    }

    private func updateUIForMode() {
        let isTaskMode = currentMode == .globalTask
        let isTodoMode = currentMode == .singleTodo

        // Update title label
        titleLabel.stringValue = isTaskMode ? L(.create_task_title) : L(.create_todo_title)

        // Update button title
        createButton.title = isTaskMode ? L(.create_task_button) : L(.create_todo_button)

        // Task mode: hide description and priority (only title + projects + decompose)
        descriptionLabel.isHidden = isTaskMode
        descriptionScrollView.isHidden = isTaskMode
        priorityLabel.isHidden = isTaskMode
        priorityPopup.isHidden = isTaskMode

        // Task mode: show decompose, API profile, and account
        decomposeCheckbox.isHidden = isTodoMode
        let showDecomposeOptions = isTaskMode && decomposeCheckbox.state == .on
        apiProfileLabel.isHidden = !showDecomposeOptions
        apiProfilePopup.isHidden = !showDecomposeOptions
        accountLabel.isHidden = !showDecomposeOptions
        accountPopup.isHidden = !showDecomposeOptions

        // Update projects label
        projectsLabel.stringValue = isTaskMode
            ? L(.create_task_projects)
            : L(.create_todo_project)
    }

    private func loadRecentProjects() {
        // Load unique project paths from sessions
        let projects = DatabaseManager.shared.getUniqueProjects(limit: 10)
        projectsField.string = projects.joined(separator: "\n")
    }

    private func loadAPIProfiles() {
        // Load API profiles in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let profiles = APIProfileManager.shared.listProfiles()
            DispatchQueue.main.async {
                self?.apiProfiles = profiles
                self?.updateAPIProfilePopup()
            }
        }
    }

    private func updateAPIProfilePopup() {
        apiProfilePopup.removeAllItems()
        apiProfilePopup.addItem(withTitle: L(.create_task_api_none))

        for profile in apiProfiles {
            apiProfilePopup.addItem(withTitle: profile)
        }

        // If no profiles available, show a hint
        if apiProfiles.isEmpty {
            apiProfilePopup.addItem(withTitle: L(.create_task_api_no_profiles))
            apiProfilePopup.lastItem?.isEnabled = false
        }
    }

    private func loadAccounts() {
        // Load accounts in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let accountList = AccountManager.shared.listAccounts()
            DispatchQueue.main.async {
                self?.accounts = accountList
                self?.updateAccountPopup()
            }
        }
    }

    private func updateAccountPopup() {
        accountPopup.removeAllItems()
        accountPopup.addItem(withTitle: "Default")

        for account in accounts {
            accountPopup.addItem(withTitle: account)
        }

        // If no accounts available, show a hint
        if accounts.isEmpty {
            accountPopup.addItem(withTitle: "(No accounts configured)")
            accountPopup.lastItem?.isEnabled = false
        }
    }

    @objc private func decomposeChanged(_ sender: NSButton) {
        updateUIForMode()
    }

    // MARK: - Actions

    @objc private func cancelClicked() {
        onCancel?()
        dismiss(nil)
    }

    @objc private func createClicked() {
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            showError(L(.create_error_title_required))
            return
        }

        let description = descriptionField.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let priority = priorityPopup.indexOfSelectedItem

        // Get project paths
        let projects = projectsField.string
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if currentMode == .singleTodo {
            // Create single todo directly
            guard let project = projects.first else {
                showError(L(.create_error_project_required))
                return
            }

            let todoId = TodoDatabaseManager.shared.createTodo(
                globalTaskId: nil,
                projectPath: project,
                title: title,
                description: description.isEmpty ? nil : description,
                priority: priority
            )

            guard todoId > 0 else {
                showError(L(.create_error_failed))
                return
            }

            onTodoCreated?(todoId)
            dismiss(nil)

        } else {
            // Create global task
            let shouldDecompose = decomposeCheckbox.state == .on

            // Get selected API profile (nil if first item "None" is selected)
            var selectedProfile: String? = nil
            if shouldDecompose && apiProfilePopup.indexOfSelectedItem > 0 {
                selectedProfile = apiProfilePopup.titleOfSelectedItem
            }

            // Get selected account alias (nil if first item "Default" is selected)
            var selectedAccount: String? = nil
            if shouldDecompose && accountPopup.indexOfSelectedItem > 0 {
                selectedAccount = accountPopup.titleOfSelectedItem
            }

            // Create global task in database
            let taskId = TodoDatabaseManager.shared.createGlobalTask(
                title: title,
                description: description.isEmpty ? nil : description,
                priority: priority
            )

            guard taskId > 0 else {
                showError(L(.create_error_failed))
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
            onTaskCreated?(taskId, shouldDecompose, selectedProfile, selectedAccount, projects)
            dismiss(nil)
        }
    }

    private func showError(_ message: String) {
        statusLabel.stringValue = "⚠️ " + message
        statusLabel.textColor = .systemRed
        statusLabel.isHidden = false
    }
}
