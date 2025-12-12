import Foundation
import UserNotifications
import AppKit

// --- Global Logging System ---
let logPath = NSString(string: "~/.claude-hooks/swift_debug.log").expandingTildeInPath
func log(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let entry = "[\(ts)] \(msg)\n"
    if let data = entry.data(using: .utf8) {
        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        } else {
            try? entry.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }
}

// --- App Delegate ---
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("APP_LAUNCH: App started (Cold Start)")
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // If started without arguments (e.g. via notification click),
        // keep alive briefly to handle the event, then exit if no event occurs.
        if CommandLine.arguments.count <= 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                log("TIMEOUT: No interaction detected, exiting.")
                exit(0)
            }
        }
    }

    // [CRITICAL] Handle Notification Click
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {

        let userInfo = response.notification.request.content.userInfo
        log("CLICK_EVENT: Notification clicked")

        if let bundleID = userInfo["targetBundle"] as? String {
            log("ACTION: Attempting to activate \(bundleID)")
            activateApp(bundleID: bundleID)
        } else {
            log("ERROR: No bundle ID found in payload")
        }

        completionHandler()
        // Delay exit slightly to ensure the open command is processed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
    }

    // Allow notifications even when app is foreground (rare for this use case)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // [FIX] Logic to restore minimized windows
    func activateApp(bundleID: String) {
        // 1. If the app is strictly hidden (Cmd+H), unhide it first.
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            if app.isHidden {
                app.unhide()
                log("ACTION: App was hidden, sent unhide request.")
            }
        }

        // 2. Use NSWorkspace openApplication.
        // This is equivalent to clicking the Dock icon. It sends a 'reopen' event
        // which forces minimized windows to pop back up.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true // Bring to front
            config.addsToRecentItems = false

            log("ACTION: Sending Open/Reopen request via Workspace...")

            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, err in
                if let e = err {
                    log("ERROR_LAUNCH: \(e)")
                } else {
                    log("SUCCESS: Open request sent.")
                }
            }
        } else {
            log("ERROR: Could not resolve URL for Bundle ID: \(bundleID)")
        }
    }
}

// --- Main Entry Point (Three-State Logic) ---
let args = CommandLine.arguments
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

if args.count > 1 {
    let mode = args[1]

    // [State 1: Detector]
    // Called by Shell Wrapper before Claude runs.
    if mode == "detect" {
        if let front = NSWorkspace.shared.frontmostApplication {
            // Print Bundle ID to stdout for Shell capture
            print(front.bundleIdentifier ?? "com.apple.Terminal")
        }
        exit(0)
    }
    // [State 2: Notifier]
    // Called by Python Hook after Claude finishes.
    else if mode == "notify" {
        guard args.count > 3 else { exit(1) }
        let title = args[2]
        let message = args[3]
        let soundName = args.count > 4 ? args[4] : "Hero"
        let targetBundle = args.count > 5 ? args[5] : "com.apple.Terminal"

        log("SEND: Title='\(title)' Target='\(targetBundle)'")

        let center = UNUserNotificationCenter.current()
        let sema = DispatchSemaphore(value: 0)

        center.requestAuthorization(options: [.alert, .sound]) { _, _ in sema.signal() }
        sema.wait()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        content.userInfo = ["targetBundle": targetBundle] // Inject ID into payload

        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        center.add(req) { err in
            if let e = err { log("SEND_ERR: \(e)") }
            exit(0)
        }
        RunLoop.main.run()
    }
} else {
    // [State 3: Handler]
    // GUI Mode (Activated by Notification Click)
    app.run()
}
