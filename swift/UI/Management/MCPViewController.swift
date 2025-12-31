import AppKit

/// View controller for MCP server management
class MCPViewController: NSViewController {

    // MARK: - UI Components

    private lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: L(.nav_mcp))
        label.font = NSFont.boldSystemFont(ofSize: 20)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var statusCard: NSView = {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }()

    private lazy var statusIcon: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var statusLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var pidLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var urlLabel: NSTextField = {
        let label = NSTextField(labelWithString: "http://127.0.0.1:8765/mcp")
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.isSelectable = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var startButton: NSButton = {
        let button = NSButton(title: L(.mcp_start), target: self, action: #selector(startClicked))
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var stopButton: NSButton = {
        let button = NSButton(title: L(.mcp_stop), target: self, action: #selector(stopClicked))
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var restartButton: NSButton = {
        let button = NSButton(title: L(.mcp_restart), target: self, action: #selector(restartClicked))
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var logCard: NSView = {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }()

    private lazy var logTitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: L(.mcp_log_title))
        label.font = NSFont.boldSystemFont(ofSize: 14)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var logTextView: NSTextView = {
        let textView = NSTextView()
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        return textView
    }()

    private lazy var logScrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = logTextView
        return scrollView
    }()

    private lazy var refreshLogButton: NSButton = {
        let button = NSButton(title: L(.mcp_refresh_log), target: self, action: #selector(refreshLogClicked))
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private var refreshTimer: Timer?

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateStatus()
        loadLog()
        startAutoRefresh()
        setupLanguageObserver()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopAutoRefresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupUI() {
        // Add main title
        view.addSubview(titleLabel)

        // Status card
        view.addSubview(statusCard)
        statusCard.addSubview(statusIcon)
        statusCard.addSubview(statusLabel)
        statusCard.addSubview(pidLabel)
        statusCard.addSubview(urlLabel)
        statusCard.addSubview(startButton)
        statusCard.addSubview(stopButton)
        statusCard.addSubview(restartButton)

        // Log card
        view.addSubview(logCard)
        logCard.addSubview(logTitleLabel)
        logCard.addSubview(logScrollView)
        logCard.addSubview(refreshLogButton)

        NSLayoutConstraint.activate([
            // Title
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // Status card
            statusCard.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            statusCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            statusCard.heightAnchor.constraint(equalToConstant: 120),

            // Status icon
            statusIcon.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            statusIcon.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 16),
            statusIcon.widthAnchor.constraint(equalToConstant: 24),
            statusIcon.heightAnchor.constraint(equalToConstant: 24),

            // Status label
            statusLabel.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: statusIcon.centerYAnchor),

            // PID label
            pidLabel.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            pidLabel.topAnchor.constraint(equalTo: statusIcon.bottomAnchor, constant: 12),

            // URL label
            urlLabel.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            urlLabel.topAnchor.constraint(equalTo: pidLabel.bottomAnchor, constant: 4),

            // Buttons
            startButton.trailingAnchor.constraint(equalTo: stopButton.leadingAnchor, constant: -8),
            startButton.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 16),

            stopButton.trailingAnchor.constraint(equalTo: restartButton.leadingAnchor, constant: -8),
            stopButton.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 16),

            restartButton.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -16),
            restartButton.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 16),

            // Log card
            logCard.topAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: 16),
            logCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            logCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            logCard.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),

            // Log title
            logTitleLabel.topAnchor.constraint(equalTo: logCard.topAnchor, constant: 12),
            logTitleLabel.leadingAnchor.constraint(equalTo: logCard.leadingAnchor, constant: 16),

            // Refresh log button
            refreshLogButton.centerYAnchor.constraint(equalTo: logTitleLabel.centerYAnchor),
            refreshLogButton.trailingAnchor.constraint(equalTo: logCard.trailingAnchor, constant: -16),

            // Log scroll view
            logScrollView.topAnchor.constraint(equalTo: logTitleLabel.bottomAnchor, constant: 8),
            logScrollView.leadingAnchor.constraint(equalTo: logCard.leadingAnchor, constant: 16),
            logScrollView.trailingAnchor.constraint(equalTo: logCard.trailingAnchor, constant: -16),
            logScrollView.bottomAnchor.constraint(equalTo: logCard.bottomAnchor, constant: -16)
        ])
    }

    private func setupLanguageObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: LocalizationManager.languageChangedNotification,
            object: nil
        )
    }

    @objc private func languageDidChange() {
        titleLabel.stringValue = L(.nav_mcp)
        startButton.title = L(.mcp_start)
        stopButton.title = L(.mcp_stop)
        restartButton.title = L(.mcp_restart)
        logTitleLabel.stringValue = L(.mcp_log_title)
        refreshLogButton.title = L(.mcp_refresh_log)
        updateStatus()
    }

    // MARK: - Status

    private func updateStatus() {
        let isRunning = MCPServerManager.shared.running

        if isRunning {
            if #available(macOS 11.0, *) {
                statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Running")
                statusIcon.contentTintColor = .systemGreen
            }
            statusLabel.stringValue = L(.mcp_status_running)
            statusLabel.textColor = .systemGreen

            if let pid = MCPServerManager.shared.pid {
                pidLabel.stringValue = "PID: \(pid)"
            } else {
                pidLabel.stringValue = ""
            }

            startButton.isEnabled = false
            stopButton.isEnabled = true
            restartButton.isEnabled = true
        } else {
            if #available(macOS 11.0, *) {
                statusIcon.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Stopped")
                statusIcon.contentTintColor = .systemRed
            }
            statusLabel.stringValue = L(.mcp_status_stopped)
            statusLabel.textColor = .systemRed
            pidLabel.stringValue = ""

            startButton.isEnabled = true
            stopButton.isEnabled = false
            restartButton.isEnabled = false
        }
    }

    // MARK: - Log

    private func loadLog() {
        let logPath = NSString(string: "~/.claude-task-tracker/logs/mcp_server.log").expandingTildeInPath

        guard FileManager.default.fileExists(atPath: logPath) else {
            logTextView.string = "(No log file found)"
            return
        }

        do {
            let content = try String(contentsOfFile: logPath, encoding: .utf8)
            // Show last 100 lines
            let lines = content.components(separatedBy: .newlines)
            let lastLines = lines.suffix(100).joined(separator: "\n")
            logTextView.string = lastLines

            // Scroll to bottom
            logTextView.scrollToEndOfDocument(nil)
        } catch {
            logTextView.string = "(Error reading log: \(error.localizedDescription))"
        }
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Actions

    @objc private func startClicked() {
        MCPServerManager.shared.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.updateStatus()
            self?.loadLog()
        }
    }

    @objc private func stopClicked() {
        MCPServerManager.shared.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateStatus()
        }
    }

    @objc private func restartClicked() {
        MCPServerManager.shared.restart()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.updateStatus()
            self?.loadLog()
        }
    }

    @objc private func refreshLogClicked() {
        loadLog()
    }

    func refresh() {
        updateStatus()
        loadLog()
    }
}
