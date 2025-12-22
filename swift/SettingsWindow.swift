import AppKit
import UserNotifications

// MARK: - Settings Configuration Manager

class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    // Keys
    private let kSummaryEnabled = "summaryAIEnabled"
    private let kSummaryBaseURL = "summaryBaseURL"
    private let kSummaryAPIKey = "summaryAPIKey"
    private let kSummaryModel = "summaryModel"

    // Config file path for Python to read
    private var configFilePath: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-task-tracker")
        return dir.appendingPathComponent("config.json")
    }

    var summaryEnabled: Bool {
        get { defaults.bool(forKey: kSummaryEnabled) }
        set {
            defaults.set(newValue, forKey: kSummaryEnabled)
            syncConfigToFile()
        }
    }

    var summaryBaseURL: String {
        get { defaults.string(forKey: kSummaryBaseURL) ?? "" }
        set {
            defaults.set(newValue, forKey: kSummaryBaseURL)
            syncConfigToFile()
        }
    }

    var summaryAPIKey: String {
        get { defaults.string(forKey: kSummaryAPIKey) ?? "" }
        set {
            defaults.set(newValue, forKey: kSummaryAPIKey)
            syncConfigToFile()
        }
    }

    var summaryModel: String {
        get { defaults.string(forKey: kSummaryModel) ?? "gpt-3.5-turbo" }
        set {
            defaults.set(newValue, forKey: kSummaryModel)
            syncConfigToFile()
        }
    }

    private init() {}

    func syncConfigToFile() {
        do {
            let dir = configFilePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            // Read existing config or create new
            var config: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: configFilePath.path) {
                if let data = try? Data(contentsOf: configFilePath),
                   let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    config = existing
                }
            }

            // Update summary section
            var summaryConfig: [String: Any] = [:]

            if summaryEnabled && !summaryAPIKey.isEmpty {
                summaryConfig["provider"] = "third_party"
                summaryConfig["third_party"] = [
                    "enabled": true,
                    "base_url": summaryBaseURL,
                    "api_key": summaryAPIKey,
                    "model": summaryModel,
                    "max_tokens": 500
                ]
            } else {
                // Disabled - use raw display mode
                summaryConfig["provider"] = "disabled"
                summaryConfig["disabled"] = true
            }

            config["summary"] = summaryConfig

            // Write config
            let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
            try data.write(to: configFilePath)

            log("Settings synced to \(configFilePath.path)")
        } catch {
            log("Failed to sync settings: \(error)")
        }
    }
}

// MARK: - Settings Window Controller

class SettingsWindowController: NSWindowController {

    private var notificationStatusLabel: NSTextField!
    private var accessibilityStatusLabel: NSTextField!
    private var testButton: NSButton!
    private var refreshButton: NSButton!

    // Summary AI settings controls
    private var summaryEnabledCheckbox: NSButton!
    private var summaryBaseURLField: NSTextField!
    private var summaryAPIKeyField: NSSecureTextField!
    private var summaryModelField: NSTextField!
    private var summaryConfigContainer: NSView!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
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

        var yOffset: CGFloat = 470

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
        summaryConfigContainer = NSView(frame: NSRect(x: 20, y: yOffset - 120, width: 440, height: 130))
        containerView.addSubview(summaryConfigContainer)

        var configY: CGFloat = 100

        // Base URL
        let baseURLLabel = NSTextField(labelWithString: "Base URL:")
        baseURLLabel.font = NSFont.systemFont(ofSize: 13)
        baseURLLabel.frame = NSRect(x: 0, y: configY, width: 80, height: 20)
        summaryConfigContainer.addSubview(baseURLLabel)

        summaryBaseURLField = NSTextField(frame: NSRect(x: 90, y: configY - 2, width: 340, height: 24))
        summaryBaseURLField.placeholderString = "https://api.openai.com/v1"
        summaryBaseURLField.target = self
        summaryBaseURLField.action = #selector(summaryConfigChanged)
        summaryConfigContainer.addSubview(summaryBaseURLField)
        configY -= 35

        // API Key
        let apiKeyLabel = NSTextField(labelWithString: "API Key:")
        apiKeyLabel.font = NSFont.systemFont(ofSize: 13)
        apiKeyLabel.frame = NSRect(x: 0, y: configY, width: 80, height: 20)
        summaryConfigContainer.addSubview(apiKeyLabel)

        summaryAPIKeyField = NSSecureTextField(frame: NSRect(x: 90, y: configY - 2, width: 340, height: 24))
        summaryAPIKeyField.placeholderString = "sk-..."
        summaryAPIKeyField.target = self
        summaryAPIKeyField.action = #selector(summaryConfigChanged)
        summaryConfigContainer.addSubview(summaryAPIKeyField)
        configY -= 35

        // Model
        let modelLabel = NSTextField(labelWithString: "Model:")
        modelLabel.font = NSFont.systemFont(ofSize: 13)
        modelLabel.frame = NSRect(x: 0, y: configY, width: 80, height: 20)
        summaryConfigContainer.addSubview(modelLabel)

        summaryModelField = NSTextField(frame: NSRect(x: 90, y: configY - 2, width: 200, height: 24))
        summaryModelField.placeholderString = "gpt-3.5-turbo"
        summaryModelField.target = self
        summaryModelField.action = #selector(summaryConfigChanged)
        summaryConfigContainer.addSubview(summaryModelField)

        yOffset -= 150

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
        summaryAPIKeyField.stringValue = settings.summaryAPIKey
        summaryModelField.stringValue = settings.summaryModel
        updateSummaryConfigVisibility()
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
    }

    @objc func summaryConfigChanged() {
        let settings = SettingsManager.shared
        settings.summaryBaseURL = summaryBaseURLField.stringValue
        settings.summaryAPIKey = summaryAPIKeyField.stringValue
        settings.summaryModel = summaryModelField.stringValue.isEmpty ? "gpt-3.5-turbo" : summaryModelField.stringValue
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
