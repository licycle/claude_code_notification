import AppKit
import UserNotifications

// MARK: - Settings Window Controller

class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {

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

    // Language settings
    private var languagePopup: NSPopUpButton!

    // Labels that need to be updated on language change
    private var titleLabel: NSTextField!
    private var notificationLabel: NSTextField!
    private var accessibilityLabel: NSTextField!
    private var notificationSettingsButton: NSButton!
    private var accessibilitySettingsButton: NSButton!
    private var summaryTitle: NSTextField!
    private var hintLabel: NSTextField!
    private var baseURLLabel: NSTextField!
    private var apiKeyLabel: NSTextField!
    private var modelLabel: NSTextField!
    private var languageLabel: NSTextField!
    private var languageHintLabel: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L(.settings_title)
        window.center()

        self.init(window: window)
        window.delegate = self
        setupUI()
        refreshStatus()
        loadSummarySettings()

        // Listen for language changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: LocalizationManager.languageChangedNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func languageDidChange() {
        updateAllTexts()
    }

    private func updateAllTexts() {
        window?.title = L(.settings_title)
        titleLabel.stringValue = L(.settings_permission_status)
        notificationLabel.stringValue = L(.settings_notification)
        accessibilityLabel.stringValue = L(.settings_accessibility)
        notificationSettingsButton.title = L(.settings_open_settings)
        accessibilitySettingsButton.title = L(.settings_open_settings)
        summaryTitle.stringValue = L(.settings_summary_ai)
        summaryEnabledCheckbox.title = L(.settings_enable_ai_summary)
        hintLabel.stringValue = L(.settings_ai_hint)
        baseURLLabel.stringValue = L(.settings_base_url)
        apiKeyLabel.stringValue = L(.settings_api_key)
        modelLabel.stringValue = L(.settings_model)
        saveAPIConfigButton.title = L(.settings_save)
        testAPIButton.title = L(.settings_test_api)
        testButton.title = L(.settings_send_test)
        refreshButton.title = L(.settings_refresh_status)
        languageLabel.stringValue = L(.settings_language) + ":"
        languageHintLabel.stringValue = L(.settings_language_hint)
        summaryAPIKeyToggleButton.title = isAPIKeyVisible ? L(.settings_hide) : L(.settings_show)
        refreshStatus()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Hide Dock icon when settings window closes
        NSApp.setActivationPolicy(.accessory)
        log("SETTINGS: Window closed, hiding Dock icon")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Main container with padding
        let containerView = NSView(frame: contentView.bounds)
        containerView.autoresizingMask = [.width, .height]
        contentView.addSubview(containerView)

        var yOffset: CGFloat = 590

        // ========== Language Section ==========
        let languageSectionTitle = NSTextField(labelWithString: L(.settings_language))
        languageSectionTitle.font = NSFont.boldSystemFont(ofSize: 16)
        languageSectionTitle.frame = NSRect(x: 20, y: yOffset, width: 400, height: 24)
        containerView.addSubview(languageSectionTitle)
        yOffset -= 35

        languageLabel = NSTextField(labelWithString: L(.settings_language) + ":")
        languageLabel.font = NSFont.systemFont(ofSize: 13)
        languageLabel.frame = NSRect(x: 20, y: yOffset, width: 80, height: 20)
        containerView.addSubview(languageLabel)

        languagePopup = NSPopUpButton(frame: NSRect(x: 100, y: yOffset - 2, width: 120, height: 24))
        for language in Language.allCases {
            languagePopup.addItem(withTitle: language.displayName)
        }
        languagePopup.selectItem(at: LocalizationManager.shared.currentLanguage == .english ? 0 : 1)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        containerView.addSubview(languagePopup)

        languageHintLabel = NSTextField(labelWithString: L(.settings_language_hint))
        languageHintLabel.font = NSFont.systemFont(ofSize: 11)
        languageHintLabel.textColor = .secondaryLabelColor
        languageHintLabel.frame = NSRect(x: 20, y: yOffset - 20, width: 420, height: 16)
        containerView.addSubview(languageHintLabel)
        yOffset -= 50

        // Separator
        let separator0 = NSBox(frame: NSRect(x: 20, y: yOffset, width: 440, height: 1))
        separator0.boxType = .separator
        containerView.addSubview(separator0)
        yOffset -= 30

        // ========== Permission Status Section ==========
        titleLabel = NSTextField(labelWithString: L(.settings_permission_status))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.frame = NSRect(x: 20, y: yOffset, width: 400, height: 24)
        containerView.addSubview(titleLabel)
        yOffset -= 40

        // Notification permission row
        notificationLabel = NSTextField(labelWithString: L(.settings_notification))
        notificationLabel.font = NSFont.systemFont(ofSize: 14)
        notificationLabel.frame = NSRect(x: 20, y: yOffset, width: 100, height: 20)
        containerView.addSubview(notificationLabel)

        notificationStatusLabel = NSTextField(labelWithString: L(.settings_checking))
        notificationStatusLabel.font = NSFont.systemFont(ofSize: 14)
        notificationStatusLabel.frame = NSRect(x: 130, y: yOffset, width: 150, height: 20)
        containerView.addSubview(notificationStatusLabel)

        notificationSettingsButton = NSButton(title: L(.settings_open_settings), target: self, action: #selector(openNotificationSettings))
        notificationSettingsButton.bezelStyle = .rounded
        notificationSettingsButton.frame = NSRect(x: 340, y: yOffset - 5, width: 120, height: 28)
        containerView.addSubview(notificationSettingsButton)
        yOffset -= 40

        // Accessibility permission row
        accessibilityLabel = NSTextField(labelWithString: L(.settings_accessibility))
        accessibilityLabel.font = NSFont.systemFont(ofSize: 14)
        accessibilityLabel.frame = NSRect(x: 20, y: yOffset, width: 100, height: 20)
        containerView.addSubview(accessibilityLabel)

        accessibilityStatusLabel = NSTextField(labelWithString: L(.settings_checking))
        accessibilityStatusLabel.font = NSFont.systemFont(ofSize: 14)
        accessibilityStatusLabel.frame = NSRect(x: 130, y: yOffset, width: 150, height: 20)
        containerView.addSubview(accessibilityStatusLabel)

        accessibilitySettingsButton = NSButton(title: L(.settings_open_settings), target: self, action: #selector(openAccessibilitySettings))
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
        summaryTitle = NSTextField(labelWithString: L(.settings_summary_ai))
        summaryTitle.font = NSFont.boldSystemFont(ofSize: 16)
        summaryTitle.frame = NSRect(x: 20, y: yOffset, width: 400, height: 24)
        containerView.addSubview(summaryTitle)
        yOffset -= 35

        // Enable checkbox
        summaryEnabledCheckbox = NSButton(checkboxWithTitle: L(.settings_enable_ai_summary), target: self, action: #selector(summaryEnabledChanged))
        summaryEnabledCheckbox.frame = NSRect(x: 20, y: yOffset, width: 440, height: 20)
        containerView.addSubview(summaryEnabledCheckbox)
        yOffset -= 10

        // Hint text when disabled
        hintLabel = NSTextField(labelWithString: L(.settings_ai_hint))
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
        baseURLLabel = NSTextField(labelWithString: L(.settings_base_url))
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
        apiKeyLabel = NSTextField(labelWithString: L(.settings_api_key))
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
        summaryAPIKeyToggleButton = NSButton(title: L(.settings_show), target: self, action: #selector(toggleAPIKeyVisibility))
        summaryAPIKeyToggleButton.bezelStyle = .rounded
        summaryAPIKeyToggleButton.frame = NSRect(x: 375, y: configY - 4, width: 55, height: 24)
        summaryConfigContainer.addSubview(summaryAPIKeyToggleButton)
        configY -= 35

        // Model
        modelLabel = NSTextField(labelWithString: L(.settings_model))
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
        saveAPIConfigButton = NSButton(title: L(.settings_save), target: self, action: #selector(saveAPIConfig))
        saveAPIConfigButton.bezelStyle = .rounded
        saveAPIConfigButton.frame = NSRect(x: 90, y: configY, width: 80, height: 28)
        summaryConfigContainer.addSubview(saveAPIConfigButton)

        testAPIButton = NSButton(title: L(.settings_test_api), target: self, action: #selector(testAPIConnection))
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
        testButton = NSButton(title: L(.settings_send_test), target: self, action: #selector(sendTestNotification))
        testButton.bezelStyle = .rounded
        testButton.frame = NSRect(x: 80, y: yOffset, width: 160, height: 32)
        containerView.addSubview(testButton)

        refreshButton = NSButton(title: L(.settings_refresh_status), target: self, action: #selector(refreshStatus))
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: 260, y: yOffset, width: 140, height: 32)
        containerView.addSubview(refreshButton)
    }

    @objc func languageChanged(_ sender: NSPopUpButton) {
        guard let selectedTitle = sender.titleOfSelectedItem,
              let language = Language.allCases.first(where: { $0.displayName == selectedTitle }) else {
            return
        }
        LocalizationManager.shared.setLanguage(language)
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
            summaryAPIKeyToggleButton.title = L(.settings_hide)
        } else {
            // Show masked version
            if actualAPIKey.isEmpty {
                summaryAPIKeyField.stringValue = ""
            } else {
                summaryAPIKeyField.stringValue = String(repeating: "•", count: min(actualAPIKey.count, 32))
            }
            summaryAPIKeyToggleButton.title = L(.settings_show)
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
            apiStatusLabel.stringValue = "⚠️ " + L(.settings_url_required)
            apiStatusLabel.textColor = .systemOrange
            return
        }

        if actualAPIKey.isEmpty {
            apiStatusLabel.stringValue = "⚠️ " + L(.settings_key_required)
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

        apiStatusLabel.stringValue = "✓ " + L(.settings_saved_success)
        apiStatusLabel.textColor = .systemGreen

        log("API config saved: baseURL=\(baseURL), model=\(model.isEmpty ? "gpt-3.5-turbo" : model)")
    }

    @objc func testAPIConnection() {
        let baseURL = summaryBaseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = summaryModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate inputs
        if baseURL.isEmpty {
            apiStatusLabel.stringValue = "⚠️ " + L(.settings_url_required)
            apiStatusLabel.textColor = .systemOrange
            return
        }

        if actualAPIKey.isEmpty {
            apiStatusLabel.stringValue = "⚠️ " + L(.settings_key_required)
            apiStatusLabel.textColor = .systemOrange
            return
        }

        // Disable button and show testing status
        testAPIButton.isEnabled = false
        testAPIButton.title = L(.settings_testing)
        apiStatusLabel.stringValue = "🔄 " + L(.settings_testing)
        apiStatusLabel.textColor = .secondaryLabelColor

        // Build API URL
        let apiURL = baseURL.hasSuffix("/") ? "\(baseURL)chat/completions" : "\(baseURL)/chat/completions"

        // Create test request
        guard let url = URL(string: apiURL) else {
            testAPIButton.isEnabled = true
            testAPIButton.title = L(.settings_test_api)
            apiStatusLabel.stringValue = "✗ " + L(.settings_test_invalid_url)
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
            testAPIButton.title = L(.settings_test_api)
            apiStatusLabel.stringValue = "✗ Failed to create request"
            apiStatusLabel.textColor = .systemRed
            return
        }

        // Execute request
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.testAPIButton.isEnabled = true
                self?.testAPIButton.title = L(.settings_test_api)

                if let error = error {
                    let errorMsg = error.localizedDescription
                    if errorMsg.contains("timed out") {
                        self?.apiStatusLabel.stringValue = "✗ " + L(.settings_test_timeout)
                    } else if errorMsg.contains("Could not connect") {
                        self?.apiStatusLabel.stringValue = "✗ " + L(.settings_test_connection_failed)
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
                    self?.apiStatusLabel.stringValue = "✓ " + L(.settings_test_success)
                    self?.apiStatusLabel.textColor = .systemGreen
                    log("API test successful")
                } else if httpResponse.statusCode == 401 {
                    self?.apiStatusLabel.stringValue = "✗ " + L(.settings_test_invalid_key)
                    self?.apiStatusLabel.textColor = .systemRed
                } else if httpResponse.statusCode == 404 {
                    self?.apiStatusLabel.stringValue = "✗ " + L(.settings_test_not_found)
                    self?.apiStatusLabel.textColor = .systemRed
                } else if httpResponse.statusCode == 429 {
                    self?.apiStatusLabel.stringValue = "⚠️ " + L(.settings_test_rate_limited)
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
                self?.notificationStatusLabel.stringValue = L(.settings_authorized)
                self?.notificationStatusLabel.textColor = .systemGreen
            } else {
                self?.notificationStatusLabel.stringValue = L(.settings_not_authorized)
                self?.notificationStatusLabel.textColor = .systemRed
            }
        }

        // Check accessibility permission
        let accessibilityAuthorized = PermissionManager.shared.checkAccessibilityPermission()
        if accessibilityAuthorized {
            accessibilityStatusLabel.stringValue = L(.settings_authorized)
            accessibilityStatusLabel.textColor = .systemGreen
        } else {
            accessibilityStatusLabel.stringValue = L(.settings_not_authorized)
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
        testButton.title = L(.settings_sending)

        // First check/request permission
        PermissionManager.shared.requestNotificationPermission { [weak self] granted in
            if granted {
                PermissionManager.shared.sendTestNotification { success in
                    self?.testButton.isEnabled = true
                    self?.testButton.title = L(.settings_send_test)

                    if success {
                        self?.showAlert(title: L(.alert_success), message: L(.settings_notification_success))
                    } else {
                        self?.showAlert(title: L(.alert_error), message: L(.settings_notification_error))
                    }
                }
            } else {
                self?.testButton.isEnabled = true
                self?.testButton.title = L(.settings_send_test)
                self?.showAlert(title: L(.alert_error), message: L(.settings_permission_denied))
            }

            // Refresh status after permission request
            self?.refreshStatus()
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = title == L(.alert_success) ? .informational : .warning
        alert.addButton(withTitle: L(.alert_ok))
        alert.runModal()
    }
}
