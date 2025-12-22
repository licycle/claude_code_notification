import AppKit
import UserNotifications

// MARK: - Settings Configuration Manager

class SettingsManager {
    static let shared = SettingsManager()

    // Config file path - single source of truth for both Swift and Python
    private var configFilePath: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-task-tracker")
        return dir.appendingPathComponent("config.json")
    }

    // In-memory cache (loaded from config.json)
    private var _summaryEnabled: Bool = false
    private var _summaryBaseURL: String = ""
    private var _summaryAPIKey: String = ""
    private var _summaryModel: String = "gpt-3.5-turbo"

    var summaryEnabled: Bool {
        get { _summaryEnabled }
        set { _summaryEnabled = newValue }
    }

    var summaryBaseURL: String {
        get { _summaryBaseURL }
        set { _summaryBaseURL = newValue }
    }

    var summaryAPIKey: String {
        get { _summaryAPIKey }
        set { _summaryAPIKey = newValue }
    }

    var summaryModel: String {
        get { _summaryModel }
        set { _summaryModel = newValue }
    }

    private init() {
        loadFromFile()
    }

    /// Load config from config.json
    func loadFromFile() {
        guard FileManager.default.fileExists(atPath: configFilePath.path) else {
            log("Config file not found, using defaults")
            return
        }

        do {
            let data = try Data(contentsOf: configFilePath)
            guard let config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            if let summary = config["summary"] as? [String: Any] {
                // Check if enabled
                let provider = summary["provider"] as? String ?? "disabled"
                _summaryEnabled = (provider == "third_party")

                // Load third_party config
                if let thirdParty = summary["third_party"] as? [String: Any] {
                    _summaryBaseURL = thirdParty["base_url"] as? String ?? ""
                    _summaryAPIKey = thirdParty["api_key"] as? String ?? ""
                    _summaryModel = thirdParty["model"] as? String ?? "gpt-3.5-turbo"
                }
            }

            log("Config loaded from \(configFilePath.path)")
        } catch {
            log("Failed to load config: \(error)")
        }
    }

    /// Save config to config.json (called explicitly by Save button)
    func saveToFile() {
        do {
            let dir = configFilePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            // Read existing config to preserve other settings
            var config: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: configFilePath.path) {
                if let data = try? Data(contentsOf: configFilePath),
                   let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    config = existing
                }
            }

            // Build summary config
            var summaryConfig: [String: Any] = [:]

            if _summaryEnabled && !_summaryAPIKey.isEmpty {
                summaryConfig["provider"] = "third_party"
                summaryConfig["third_party"] = [
                    "enabled": true,
                    "base_url": _summaryBaseURL,
                    "api_key": _summaryAPIKey,
                    "model": _summaryModel,
                    "max_tokens": 500
                ]
            } else {
                summaryConfig["provider"] = "disabled"
                summaryConfig["disabled"] = true
            }

            config["summary"] = summaryConfig

            // Write config
            let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
            try data.write(to: configFilePath)

            log("Config saved to \(configFilePath.path)")
        } catch {
            log("Failed to save config: \(error)")
        }
    }
}

// MARK: - Settings Window Controller

class SettingsWindowController: NSWindowController, NSTextFieldDelegate {

    private var notificationStatusLabel: NSTextField!
    private var accessibilityStatusLabel: NSTextField!
    private var testButton: NSButton!
    private var refreshButton: NSButton!

    // Summary AI settings controls
    private var summaryEnabledCheckbox: NSButton!
    private var summaryBaseURLField: NSTextField!
    private var summaryAPIKeyField: NSTextField!
    private var summaryAPIKeyToggleButton: NSButton!
    private var isAPIKeyVisible: Bool = false
    private var actualAPIKey: String = ""
    private var summaryModelField: NSTextField!
    private var summaryConfigContainer: NSView!

    // New buttons for save and test
    private var saveAPIConfigButton: NSButton!
    private var testAPIButton: NSButton!
    private var apiStatusLabel: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClaudeMonitor Settings"
        window.center()

        self.init(window: window)
        setupUI()
        refreshStatus()
        loadSummarySettings()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Main container with padding
        let containerView = NSView(frame: contentView.bounds)
        containerView.autoresizingMask = [.width, .height]
        contentView.addSubview(containerView)

        var yOffset: CGFloat = 530

        // ========== Permission Status Section ==========
        let titleLabel = NSTextField(labelWithString: "Permission Status")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.frame = NSRect(x: 20, y: yOffset, width: 400, height: 24)
        containerView.addSubview(titleLabel)
        yOffset -= 40

        // Notification permission row
        let notificationLabel = NSTextField(labelWithString: "Notification:")
        notificationLabel.font = NSFont.systemFont(ofSize: 14)
        notificationLabel.frame = NSRect(x: 20, y: yOffset, width: 100, height: 20)
        containerView.addSubview(notificationLabel)

        notificationStatusLabel = NSTextField(labelWithString: "Checking...")
        notificationStatusLabel.font = NSFont.systemFont(ofSize: 14)
        notificationStatusLabel.frame = NSRect(x: 130, y: yOffset, width: 150, height: 20)
        containerView.addSubview(notificationStatusLabel)

        let notificationSettingsButton = NSButton(title: "Open Settings", target: self, action: #selector(openNotificationSettings))
        notificationSettingsButton.bezelStyle = .rounded
        notificationSettingsButton.frame = NSRect(x: 340, y: yOffset - 5, width: 120, height: 28)
        containerView.addSubview(notificationSettingsButton)
        yOffset -= 40

        // Accessibility permission row
        let accessibilityLabel = NSTextField(labelWithString: "Accessibility:")
        accessibilityLabel.font = NSFont.systemFont(ofSize: 14)
        accessibilityLabel.frame = NSRect(x: 20, y: yOffset, width: 100, height: 20)
        containerView.addSubview(accessibilityLabel)

        accessibilityStatusLabel = NSTextField(labelWithString: "Checking...")
        accessibilityStatusLabel.font = NSFont.systemFont(ofSize: 14)
        accessibilityStatusLabel.frame = NSRect(x: 130, y: yOffset, width: 150, height: 20)
        containerView.addSubview(accessibilityStatusLabel)

        let accessibilitySettingsButton = NSButton(title: "Open Settings", target: self, action: #selector(openAccessibilitySettings))
        accessibilitySettingsButton.bezelStyle = .rounded
        accessibilitySettingsButton.frame = NSRect(x: 340, y: yOffset - 5, width: 120, height: 28)
        containerView.addSubview(accessibilitySettingsButton)
        yOffset -= 30

        // Separator
        let separator1 = NSBox(frame: NSRect(x: 20, y: yOffset, width: 440, height: 1))
        separator1.boxType = .separator
        containerView.addSubview(separator1)
        yOffset -= 30

        // ========== Summary AI Section ==========
        let summaryTitle = NSTextField(labelWithString: "Summary AI Settings")
        summaryTitle.font = NSFont.boldSystemFont(ofSize: 16)
        summaryTitle.frame = NSRect(x: 20, y: yOffset, width: 400, height: 24)
        containerView.addSubview(summaryTitle)
        yOffset -= 35

        // Enable checkbox
        summaryEnabledCheckbox = NSButton(checkboxWithTitle: "Enable AI Summary (uses API to summarize notifications)", target: self, action: #selector(summaryEnabledChanged))
        summaryEnabledCheckbox.frame = NSRect(x: 20, y: yOffset, width: 440, height: 20)
        containerView.addSubview(summaryEnabledCheckbox)
        yOffset -= 10

        // Hint text when disabled
        let hintLabel = NSTextField(labelWithString: "When disabled, notifications show raw user prompt and AI assistance requests")
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.frame = NSRect(x: 38, y: yOffset, width: 420, height: 16)
        containerView.addSubview(hintLabel)
        yOffset -= 25

        // Config container (shown only when enabled)
        summaryConfigContainer = NSView(frame: NSRect(x: 20, y: yOffset - 180, width: 440, height: 190))
        containerView.addSubview(summaryConfigContainer)

        var configY: CGFloat = 155

        // Base URL
        let baseURLLabel = NSTextField(labelWithString: "Base URL:")
        baseURLLabel.font = NSFont.systemFont(ofSize: 13)
        baseURLLabel.frame = NSRect(x: 0, y: configY, width: 80, height: 20)
        summaryConfigContainer.addSubview(baseURLLabel)

        summaryBaseURLField = NSTextField(frame: NSRect(x: 90, y: configY - 2, width: 340, height: 24))
        summaryBaseURLField.placeholderString = "https://api.openai.com/v1"
        summaryBaseURLField.isEditable = true
        summaryBaseURLField.isSelectable = true
        summaryConfigContainer.addSubview(summaryBaseURLField)
        configY -= 35

        // API Key
        let apiKeyLabel = NSTextField(labelWithString: "API Key:")
        apiKeyLabel.font = NSFont.systemFont(ofSize: 13)
        apiKeyLabel.frame = NSRect(x: 0, y: configY, width: 80, height: 20)
        summaryConfigContainer.addSubview(apiKeyLabel)

        summaryAPIKeyField = NSTextField(frame: NSRect(x: 90, y: configY - 2, width: 280, height: 24))
        summaryAPIKeyField.placeholderString = "sk-..."
        summaryAPIKeyField.isEditable = true
        summaryAPIKeyField.isSelectable = true
        summaryAPIKeyField.target = self
        summaryAPIKeyField.action = #selector(apiKeyFieldChanged)
        summaryConfigContainer.addSubview(summaryAPIKeyField)

        // Show/Hide toggle button
        summaryAPIKeyToggleButton = NSButton(title: "Show", target: self, action: #selector(toggleAPIKeyVisibility))
        summaryAPIKeyToggleButton.bezelStyle = .rounded
        summaryAPIKeyToggleButton.frame = NSRect(x: 375, y: configY - 4, width: 55, height: 24)
        summaryConfigContainer.addSubview(summaryAPIKeyToggleButton)
        configY -= 35

        // Model
        let modelLabel = NSTextField(labelWithString: "Model:")
        modelLabel.font = NSFont.systemFont(ofSize: 13)
        modelLabel.frame = NSRect(x: 0, y: configY, width: 80, height: 20)
        summaryConfigContainer.addSubview(modelLabel)

        summaryModelField = NSTextField(frame: NSRect(x: 90, y: configY - 2, width: 200, height: 24))
        summaryModelField.placeholderString = "gpt-3.5-turbo"
        summaryModelField.isEditable = true
        summaryModelField.isSelectable = true
        summaryConfigContainer.addSubview(summaryModelField)
        configY -= 40

        // Save and Test API buttons
        saveAPIConfigButton = NSButton(title: "Save", target: self, action: #selector(saveAPIConfig))
        saveAPIConfigButton.bezelStyle = .rounded
        saveAPIConfigButton.frame = NSRect(x: 90, y: configY, width: 80, height: 28)
        summaryConfigContainer.addSubview(saveAPIConfigButton)

        testAPIButton = NSButton(title: "Test API", target: self, action: #selector(testAPIConnection))
        testAPIButton.bezelStyle = .rounded
        testAPIButton.frame = NSRect(x: 180, y: configY, width: 100, height: 28)
        summaryConfigContainer.addSubview(testAPIButton)
        configY -= 30

        // API status label
        apiStatusLabel = NSTextField(labelWithString: "")
        apiStatusLabel.font = NSFont.systemFont(ofSize: 11)
        apiStatusLabel.frame = NSRect(x: 90, y: configY, width: 340, height: 16)
        summaryConfigContainer.addSubview(apiStatusLabel)

        yOffset -= 210

        // Separator
        let separator2 = NSBox(frame: NSRect(x: 20, y: yOffset, width: 440, height: 1))
        separator2.boxType = .separator
        containerView.addSubview(separator2)
        yOffset -= 30

        // ========== Test & Refresh Buttons ==========
        testButton = NSButton(title: "Send Test Notification", target: self, action: #selector(sendTestNotification))
        testButton.bezelStyle = .rounded
        testButton.frame = NSRect(x: 80, y: yOffset, width: 160, height: 32)
        containerView.addSubview(testButton)

        refreshButton = NSButton(title: "Refresh Status", target: self, action: #selector(refreshStatus))
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: 260, y: yOffset, width: 140, height: 32)
        containerView.addSubview(refreshButton)
    }

    private func loadSummarySettings() {
        let settings = SettingsManager.shared
        summaryEnabledCheckbox.state = settings.summaryEnabled ? .on : .off
        summaryBaseURLField.stringValue = settings.summaryBaseURL
        actualAPIKey = settings.summaryAPIKey
        updateAPIKeyDisplay()
        summaryModelField.stringValue = settings.summaryModel
        updateSummaryConfigVisibility()
    }

    private func updateAPIKeyDisplay() {
        if isAPIKeyVisible {
            summaryAPIKeyField.stringValue = actualAPIKey
            summaryAPIKeyToggleButton.title = "Hide"
        } else {
            // Show masked version
            if actualAPIKey.isEmpty {
                summaryAPIKeyField.stringValue = ""
            } else {
                summaryAPIKeyField.stringValue = String(repeating: "•", count: min(actualAPIKey.count, 32))
            }
            summaryAPIKeyToggleButton.title = "Show"
        }
    }

    private func maskAPIKey(_ key: String) -> String {
        guard !key.isEmpty else { return "" }
        return String(repeating: "•", count: min(key.count, 32))
    }

    private func updateSummaryConfigVisibility() {
        let isEnabled = summaryEnabledCheckbox.state == .on
        summaryConfigContainer.isHidden = !isEnabled
        summaryConfigContainer.alphaValue = isEnabled ? 1.0 : 0.3
    }

    @objc func summaryEnabledChanged() {
        let settings = SettingsManager.shared
        settings.summaryEnabled = summaryEnabledCheckbox.state == .on
        updateSummaryConfigVisibility()
        // Note: Don't auto-save, user must click Save button
    }

    @objc func saveAPIConfig() {
        let settings = SettingsManager.shared

        // Get values from fields
        let baseURL = summaryBaseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = summaryModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate
        if baseURL.isEmpty {
            apiStatusLabel.stringValue = "⚠️ Base URL is required"
            apiStatusLabel.textColor = .systemOrange
            return
        }

        if actualAPIKey.isEmpty {
            apiStatusLabel.stringValue = "⚠️ API Key is required"
            apiStatusLabel.textColor = .systemOrange
            return
        }

        // Update in-memory settings
        settings.summaryEnabled = summaryEnabledCheckbox.state == .on
        settings.summaryBaseURL = baseURL
        settings.summaryAPIKey = actualAPIKey
        settings.summaryModel = model.isEmpty ? "gpt-3.5-turbo" : model

        // Save to config.json (the single source of truth)
        settings.saveToFile()

        apiStatusLabel.stringValue = "✓ Saved to config.json"
        apiStatusLabel.textColor = .systemGreen

        log("API config saved: baseURL=\(baseURL), model=\(model.isEmpty ? "gpt-3.5-turbo" : model)")
    }

    @objc func testAPIConnection() {
        let baseURL = summaryBaseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = summaryModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate inputs
        if baseURL.isEmpty {
            apiStatusLabel.stringValue = "⚠️ Please enter Base URL first"
            apiStatusLabel.textColor = .systemOrange
            return
        }

        if actualAPIKey.isEmpty {
            apiStatusLabel.stringValue = "⚠️ Please enter API Key first"
            apiStatusLabel.textColor = .systemOrange
            return
        }

        // Disable button and show testing status
        testAPIButton.isEnabled = false
        testAPIButton.title = "Testing..."
        apiStatusLabel.stringValue = "🔄 Testing API connection..."
        apiStatusLabel.textColor = .secondaryLabelColor

        // Build API URL
        let apiURL = baseURL.hasSuffix("/") ? "\(baseURL)chat/completions" : "\(baseURL)/chat/completions"

        // Create test request
        guard let url = URL(string: apiURL) else {
            testAPIButton.isEnabled = true
            testAPIButton.title = "Test API"
            apiStatusLabel.stringValue = "✗ Invalid URL format"
            apiStatusLabel.textColor = .systemRed
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(actualAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // Simple test payload
        let testPayload: [String: Any] = [
            "model": model.isEmpty ? "gpt-3.5-turbo" : model,
            "messages": [
                ["role": "user", "content": "Hi"]
            ],
            "max_tokens": 5
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: testPayload)
        } catch {
            testAPIButton.isEnabled = true
            testAPIButton.title = "Test API"
            apiStatusLabel.stringValue = "✗ Failed to create request"
            apiStatusLabel.textColor = .systemRed
            return
        }

        // Execute request
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.testAPIButton.isEnabled = true
                self?.testAPIButton.title = "Test API"

                if let error = error {
                    let errorMsg = error.localizedDescription
                    if errorMsg.contains("timed out") {
                        self?.apiStatusLabel.stringValue = "✗ Connection timeout"
                    } else if errorMsg.contains("Could not connect") {
                        self?.apiStatusLabel.stringValue = "✗ Cannot connect to server"
                    } else {
                        self?.apiStatusLabel.stringValue = "✗ \(errorMsg.prefix(50))"
                    }
                    self?.apiStatusLabel.textColor = .systemRed
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self?.apiStatusLabel.stringValue = "✗ Invalid response"
                    self?.apiStatusLabel.textColor = .systemRed
                    return
                }

                if httpResponse.statusCode == 200 {
                    self?.apiStatusLabel.stringValue = "✓ API connection successful!"
                    self?.apiStatusLabel.textColor = .systemGreen
                    log("API test successful")
                } else if httpResponse.statusCode == 401 {
                    self?.apiStatusLabel.stringValue = "✗ Invalid API Key (401)"
                    self?.apiStatusLabel.textColor = .systemRed
                } else if httpResponse.statusCode == 404 {
                    self?.apiStatusLabel.stringValue = "✗ Endpoint not found (404) - check Base URL"
                    self?.apiStatusLabel.textColor = .systemRed
                } else if httpResponse.statusCode == 429 {
                    self?.apiStatusLabel.stringValue = "⚠️ Rate limited (429) - but API key is valid"
                    self?.apiStatusLabel.textColor = .systemOrange
                } else {
                    // Try to get error message from response
                    var errorDetail = ""
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorObj = json["error"] as? [String: Any],
                       let message = errorObj["message"] as? String {
                        errorDetail = ": \(message.prefix(40))"
                    }
                    self?.apiStatusLabel.stringValue = "✗ Error \(httpResponse.statusCode)\(errorDetail)"
                    self?.apiStatusLabel.textColor = .systemRed
                }
            }
        }
        task.resume()
    }

    @objc func toggleAPIKeyVisibility() {
        isAPIKeyVisible.toggle()
        updateAPIKeyDisplay()
    }

    @objc func apiKeyFieldChanged() {
        let fieldValue = summaryAPIKeyField.stringValue
        // Only update if visible (user is editing) or if it's a paste operation (contains non-bullet chars)
        if isAPIKeyVisible || !fieldValue.contains("•") {
            actualAPIKey = fieldValue
            SettingsManager.shared.summaryAPIKey = actualAPIKey
            if !isAPIKeyVisible {
                // User pasted while hidden, update display
                updateAPIKeyDisplay()
            }
        }
    }

    @objc func refreshStatus() {
        // Check notification permission
        PermissionManager.shared.checkNotificationPermission { [weak self] authorized in
            if authorized {
                self?.notificationStatusLabel.stringValue = "Authorized"
                self?.notificationStatusLabel.textColor = .systemGreen
            } else {
                self?.notificationStatusLabel.stringValue = "Not Authorized"
                self?.notificationStatusLabel.textColor = .systemRed
            }
        }

        // Check accessibility permission
        let accessibilityAuthorized = PermissionManager.shared.checkAccessibilityPermission()
        if accessibilityAuthorized {
            accessibilityStatusLabel.stringValue = "Authorized"
            accessibilityStatusLabel.textColor = .systemGreen
        } else {
            accessibilityStatusLabel.stringValue = "Not Authorized"
            accessibilityStatusLabel.textColor = .systemRed
        }
    }

    @objc func openNotificationSettings() {
        PermissionManager.shared.openNotificationSettings()
    }

    @objc func openAccessibilitySettings() {
        // Request permission first (triggers system dialog if not trusted)
        let _ = PermissionManager.shared.requestAccessibilityPermission()
        // Also open settings page
        PermissionManager.shared.openAccessibilitySettings()
        // Refresh status after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshStatus()
        }
    }

    @objc func sendTestNotification() {
        testButton.isEnabled = false
        testButton.title = "Sending..."

        // First check/request permission
        PermissionManager.shared.requestNotificationPermission { [weak self] granted in
            if granted {
                PermissionManager.shared.sendTestNotification { success in
                    self?.testButton.isEnabled = true
                    self?.testButton.title = "Send Test Notification"

                    if success {
                        self?.showAlert(title: "Success", message: "Test notification sent!")
                    } else {
                        self?.showAlert(title: "Error", message: "Failed to send notification")
                    }
                }
            } else {
                self?.testButton.isEnabled = true
                self?.testButton.title = "Send Test Notification"
                self?.showAlert(title: "Permission Denied", message: "Please grant notification permission first")
            }

            // Refresh status after permission request
            self?.refreshStatus()
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = title == "Success" ? .informational : .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
