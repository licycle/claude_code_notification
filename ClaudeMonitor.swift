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

        let bundleID = userInfo["targetBundle"] as? String
        let targetPID = userInfo["targetPID"] as? Int32 ?? 0
        let cgWindowID = userInfo["cgWindowID"] as? UInt32 ?? 0

        if targetPID > 0 {
            log("ACTION: Attempting to activate PID \(targetPID) CGWindowID=\(cgWindowID)")
            activateAppByPID(pid: targetPID, cgWindowID: cgWindowID, fallbackBundle: bundleID)
        } else if let bundleID = bundleID {
            log("ACTION: Falling back to bundle activation \(bundleID)")
            activateApp(bundleID: bundleID)
        } else {
            log("ERROR: No bundle ID or PID found in payload")
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

    // [NEW] Activate specific process by PID with CGWindowID matching (supports minimized windows)
    func activateAppByPID(pid: Int32, cgWindowID: UInt32, fallbackBundle: String?) {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            log("WARNING: No process found for PID \(pid)")
            if let bundleID = fallbackBundle {
                activateApp(bundleID: bundleID)
            }
            return
        }

        log("ACTION: Found process PID \(pid), cgWindowID=\(cgWindowID), activating...")

        // 1. Unhide if hidden
        if app.isHidden {
            app.unhide()
            log("ACTION: App was hidden, sent unhide request.")
        }

        // 2. Try to find and activate the specific window by CGWindowID using Accessibility API
        var windowFound = false

        if cgWindowID > 0 {
            let appElement = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?

            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement] {

                log("ACTION: Found \(windows.count) windows via Accessibility API")

                for (index, window) in windows.enumerated() {
                    // Use private API to get CGWindowID from AXUIElement
                    var windowID: CGWindowID = 0
                    let result = _AXUIElementGetWindow(window, &windowID)

                    log("ACTION: Window[\(index)] -> CGWindowID=\(windowID) (result=\(result))")

                    if result == .success && windowID == cgWindowID {
                        log("ACTION: Found matching window at index \(index)")

                        // Unminimize if minimized
                        var minimizedRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
                           let isMinimized = minimizedRef as? Bool, isMinimized {
                            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                            log("ACTION: Unminimized window")
                        }

                        // Raise the window
                        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                        log("ACTION: Raised window")

                        windowFound = true
                        break
                    }
                }
            } else {
                log("WARNING: Failed to get windows via Accessibility API")
            }
        }

        // 3. Activate the app (bring to front)
        app.activate(options: [.activateIgnoringOtherApps])

        // 4. If specific window not found, fallback to unminimize all windows via AppleScript
        if !windowFound && cgWindowID > 0 {
            log("WARNING: CGWindowID \(cgWindowID) not found, falling back to unminimize all")
            let script = """
            tell application "System Events"
                set targetProcess to first process whose unix id is \(pid)
                set frontmost of targetProcess to true
                tell targetProcess
                    repeat with w in windows
                        try
                            set value of attribute "AXMinimized" of w to false
                        end try
                    end repeat
                end tell
            end tell
            """
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                scriptObject.executeAndReturnError(&error)
                if let err = error {
                    log("AppleScript fallback error: \(err)")
                }
            }
        }

        log("SUCCESS: Activated PID \(pid) (windowFound=\(windowFound))")
    }
}

// Private API declaration for getting CGWindowID from AXUIElement
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

// --- Main Entry Point (Three-State Logic) ---
let args = CommandLine.arguments
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

if args.count > 1 {
    let mode = args[1]

    // [State 1: Detector]
    // Called by Shell Wrapper before Claude runs.
    // Output format: "bundleID|PID|CGWindowID" for window-level activation
    if mode == "detect" {
        if let front = NSWorkspace.shared.frontmostApplication {
            let bundleID = front.bundleIdentifier ?? "com.apple.Terminal"
            let pid = front.processIdentifier

            // Get frontmost window's CGWindowID using Quartz Window Services
            // Try .optionOnScreenOnly first (visible windows), fallback to .optionAll (includes minimized)
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
    // [State 2: Notifier]
    // Called by Python Hook after Claude finishes.
    // Args: notify <title> <message> [sound] [bundle_id] [pid] [cgWindowID]
    else if mode == "notify" {
        guard args.count > 3 else { exit(1) }
        let title = args[2]
        let message = args[3]
        let soundName = args.count > 4 ? args[4] : "Hero"
        let targetBundle = args.count > 5 ? args[5] : "com.apple.Terminal"
        let targetPID: Int32 = args.count > 6 ? Int32(args[6]) ?? 0 : 0
        let cgWindowID: UInt32 = args.count > 7 ? UInt32(args[7]) ?? 0 : 0

        log("SEND: Title='\(title)' Target='\(targetBundle)' PID=\(targetPID) CGWindowID=\(cgWindowID)")

        let center = UNUserNotificationCenter.current()
        let sema = DispatchSemaphore(value: 0)

        center.requestAuthorization(options: [.alert, .sound]) { _, _ in sema.signal() }
        sema.wait()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        content.userInfo = [
            "targetBundle": targetBundle,
            "targetPID": targetPID,
            "cgWindowID": cgWindowID
        ] // Inject ID, PID and CGWindowID into payload for window-level activation

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
