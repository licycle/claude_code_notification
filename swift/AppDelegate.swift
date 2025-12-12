import Foundation
import UserNotifications
import AppKit

// MARK: - Private API Declaration

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    var settingsWindowController: SettingsWindowController?
    var launchedFromNotification = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set delegate BEFORE app finishes launching to catch cold-start notification clicks
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        log("APP_LAUNCH: Delegate set in willFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("APP_LAUNCH: App started")

        // Check if launched from notification click after a short delay
        // If no notification event received, this is a user-initiated launch (click app icon)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            if !self.launchedFromNotification {
                log("APP_LAUNCH: No notification event, showing settings window")
                self.showSettingsWindow()
            } else {
                log("APP_LAUNCH: Launched from notification, staying in background")
            }
        }
    }

    // MARK: - Show Settings Window (GUI Mode)

    func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        settingsWindowController = SettingsWindowController()
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Handle Notification Click

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {

        // Mark that we were launched from notification (for cold start detection)
        launchedFromNotification = true

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
        // Keep app running - settings window stays in background
    }

    // Allow notifications even when app is foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Activate App by Bundle ID

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
            config.activates = true
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

    // MARK: - Activate App by PID (with CGWindowID matching)

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
