import AppKit
import UserNotifications

// MARK: - Settings Window Controller

class SettingsWindowController: NSWindowController {

    private var notificationStatusLabel: NSTextField!
    private var accessibilityStatusLabel: NSTextField!
    private var testButton: NSButton!
    private var refreshButton: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClaudeMonitor Settings"
        window.center()

        self.init(window: window)
        setupUI()
        refreshStatus()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Main container with padding
        let containerView = NSView(frame: contentView.bounds)
        containerView.autoresizingMask = [.width, .height]
        contentView.addSubview(containerView)

        // Title
        let titleLabel = NSTextField(labelWithString: "Permission Status")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.frame = NSRect(x: 20, y: 230, width: 380, height: 24)
        containerView.addSubview(titleLabel)

        // Notification permission row
        let notificationLabel = NSTextField(labelWithString: "Notification:")
        notificationLabel.font = NSFont.systemFont(ofSize: 14)
        notificationLabel.frame = NSRect(x: 20, y: 190, width: 100, height: 20)
        containerView.addSubview(notificationLabel)

        notificationStatusLabel = NSTextField(labelWithString: "Checking...")
        notificationStatusLabel.font = NSFont.systemFont(ofSize: 14)
        notificationStatusLabel.frame = NSRect(x: 120, y: 190, width: 150, height: 20)
        containerView.addSubview(notificationStatusLabel)

        let notificationSettingsButton = NSButton(title: "Open Settings", target: self, action: #selector(openNotificationSettings))
        notificationSettingsButton.bezelStyle = .rounded
        notificationSettingsButton.frame = NSRect(x: 290, y: 185, width: 110, height: 28)
        containerView.addSubview(notificationSettingsButton)

        // Accessibility permission row
        let accessibilityLabel = NSTextField(labelWithString: "Accessibility:")
        accessibilityLabel.font = NSFont.systemFont(ofSize: 14)
        accessibilityLabel.frame = NSRect(x: 20, y: 150, width: 100, height: 20)
        containerView.addSubview(accessibilityLabel)

        accessibilityStatusLabel = NSTextField(labelWithString: "Checking...")
        accessibilityStatusLabel.font = NSFont.systemFont(ofSize: 14)
        accessibilityStatusLabel.frame = NSRect(x: 120, y: 150, width: 150, height: 20)
        containerView.addSubview(accessibilityStatusLabel)

        let accessibilitySettingsButton = NSButton(title: "Open Settings", target: self, action: #selector(openAccessibilitySettings))
        accessibilitySettingsButton.bezelStyle = .rounded
        accessibilitySettingsButton.frame = NSRect(x: 290, y: 145, width: 110, height: 28)
        containerView.addSubview(accessibilitySettingsButton)

        // Separator
        let separator = NSBox(frame: NSRect(x: 20, y: 120, width: 380, height: 1))
        separator.boxType = .separator
        containerView.addSubview(separator)

        // Test notification button
        testButton = NSButton(title: "Send Test Notification", target: self, action: #selector(sendTestNotification))
        testButton.bezelStyle = .rounded
        testButton.frame = NSRect(x: 110, y: 70, width: 200, height: 32)
        containerView.addSubview(testButton)

        // Refresh button
        refreshButton = NSButton(title: "Refresh Status", target: self, action: #selector(refreshStatus))
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: 110, y: 30, width: 200, height: 32)
        containerView.addSubview(refreshButton)
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
