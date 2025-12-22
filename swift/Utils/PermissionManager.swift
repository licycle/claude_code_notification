import Foundation
import UserNotifications
import AppKit

// MARK: - Permission Manager

class PermissionManager {
    static let shared = PermissionManager()

    private init() {}

    // MARK: - Check Notification Permission

    func checkNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let authorized = settings.authorizationStatus == .authorized
                completion(authorized)
            }
        }
    }

    // MARK: - Check Accessibility Permission

    func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    // MARK: - Request Accessibility Permission (with system prompt)

    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Open Settings

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Request Notification Permission

    func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    log("Permission request error: \(error)")
                }
                completion(granted)
            }
        }
    }

    // MARK: - Send Test Notification

    func sendTestNotification(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "ClaudeMonitor Test"
        content.body = "Notification is working correctly!"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Hero"))

        // Log sound setting
        log("TEST_SOUND: Using sound 'Hero'")

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            DispatchQueue.main.async {
                if let error = error {
                    log("Test notification error: \(error)")
                    completion(false)
                } else {
                    log("Test notification sent successfully")
                    completion(true)
                }
            }
        }
    }
}
