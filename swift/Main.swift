import Foundation
import AppKit
import UserNotifications

// MARK: - Main Entry Point

@main
struct ClaudeMonitorApp {
    static func main() {
        let args = CommandLine.arguments
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate

        if args.count > 1 {
            let mode = args[1]

            // [Mode 1: Detector]
            // Called by Shell Wrapper before Claude runs.
            // Output format: "bundleID|PID|CGWindowID" for window-level activation
            if mode == "detect" {
                if let front = NSWorkspace.shared.frontmostApplication {
                    let bundleID = front.bundleIdentifier ?? "com.apple.Terminal"
                    let pid = front.processIdentifier

                    // Get frontmost window's CGWindowID using Quartz Window Services
                    var windowID: UInt32 = 0

                    func findWindow(options: CGWindowListOption) -> UInt32 {
                        let list = CGWindowListCopyWindowInfo([options, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                        for window in list {
                            if let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                               ownerPID == pid,
                               let layer = window[kCGWindowLayer as String] as? Int,
                               layer == 0,
                               let wid = window[kCGWindowNumber as String] as? UInt32 {
                                return wid
                            }
                        }
                        return 0
                    }

                    windowID = findWindow(options: .optionOnScreenOnly)
                    if windowID == 0 {
                        windowID = findWindow(options: .optionAll)
                    }

                    // Output format: "bundleID|PID|CGWindowID"
                    print("\(bundleID)|\(pid)|\(windowID)")
                } else {
                    print("com.apple.Terminal|0|0")
                }
                exit(0)
            }

            // [Mode 2: Notifier]
            // Called by Python Hook after Claude finishes.
            // Args: notify <title> <message> [sound] [bundle_id] [pid] [cgWindowID]
            else if mode == "notify" {
                guard args.count > 3 else { exit(1) }
                let title = args[2]
                let message = args[3]
                let soundName = args.count > 4 ? args[4] : "Crystal"
                let targetBundle = args.count > 5 ? args[5] : "com.apple.Terminal"
                let targetPID: Int32 = args.count > 6 ? Int32(args[6]) ?? 0 : 0
                let cgWindowID: UInt32 = args.count > 7 ? UInt32(args[7]) ?? 0 : 0

                log("SEND: Title='\(title)' Target='\(targetBundle)' PID=\(targetPID) CGWindowID=\(cgWindowID)")

                let center = UNUserNotificationCenter.current()
                let sema = DispatchSemaphore(value: 0)

                center.requestAuthorization(options: [.alert, .sound]) { _, _ in sema.signal() }
                sema.wait()

                // Register notification categories for rich notifications
                registerNotificationCategories()

                let content = UNMutableNotificationContent()
                content.title = title
                content.body = message

                // Set category for action buttons
                content.categoryIdentifier = "TASK_STATUS"

                // Set sound with validation (soundName is defined above)
                if !soundName.isEmpty {
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
                }

                // Log sound setting
                log("SOUND: Using sound '\(soundName.isEmpty ? "system default" : soundName)'")

                // Set app icon for notifications
                let appBundleURL = Bundle.main.bundleURL
                content.userInfo = [
                    "targetBundle": targetBundle,
                    "targetPID": targetPID,
                    "cgWindowID": cgWindowID
                ]

                let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

                center.add(req) { err in
                    if let e = err { log("SEND_ERR: \(e)") }
                    exit(0)
                }
                RunLoop.main.run()
            }

            // [Mode 3: GUI]
            // Shows settings window for permission check and testing
            else if mode == "gui" {
                log("GUI: Starting settings window")
                delegate.showSettingsWindow()
                app.run()
            }

            // Unknown mode
            else {
                print("Usage: ClaudeMonitor <detect|notify|gui>")
                print("  detect              - Detect frontmost app (outputs bundleID|PID|CGWindowID)")
                print("  notify <t> <m> ...  - Send notification")
                print("  gui                 - Show settings window")
                exit(1)
            }
        } else {
            // [Mode 4: Default - Smart launch]
            // Start in background, AppDelegate will detect if launched from:
            // - Notification click: stay in background, activate target window
            // - App icon click: show settings window (switch to regular mode)
            log("LAUNCH: Starting in background mode (auto-detect)")
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}

// MARK: - Rich Notification Categories

/// Register notification categories with action buttons
func registerNotificationCategories() {
    // Jump to terminal action
    let jumpAction = UNNotificationAction(
        identifier: "JUMP_ACTION",
        title: "跳转到终端",
        options: [.foreground]
    )

    // Dismiss action
    let dismissAction = UNNotificationAction(
        identifier: "DISMISS_ACTION",
        title: "稍后处理",
        options: []
    )

    // View details action
    let viewAction = UNNotificationAction(
        identifier: "VIEW_ACTION",
        title: "查看详情",
        options: [.foreground]
    )

    // Task status category (for idle, decision needed, etc.)
    let taskCategory = UNNotificationCategory(
        identifier: "TASK_STATUS",
        actions: [jumpAction, dismissAction],
        intentIdentifiers: [],
        options: [.customDismissAction]
    )

    // Decision needed category (with more prominent actions)
    let decisionCategory = UNNotificationCategory(
        identifier: "DECISION_NEEDED",
        actions: [jumpAction, viewAction, dismissAction],
        intentIdentifiers: [],
        options: [.customDismissAction]
    )

    // Permission needed category
    let permissionCategory = UNNotificationCategory(
        identifier: "PERMISSION_NEEDED",
        actions: [jumpAction, dismissAction],
        intentIdentifiers: [],
        options: [.customDismissAction]
    )

    UNUserNotificationCenter.current().setNotificationCategories([
        taskCategory,
        decisionCategory,
        permissionCategory
    ])

    log("CATEGORY: Registered notification categories")
}
