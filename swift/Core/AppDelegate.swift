import Foundation
import UserNotifications
import AppKit

// MARK: - Private API Declaration

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    var settingsWindowController: SettingsWindowController?
    var statusBarController: StatusBarController?
    var launchedFromNotification = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set delegate BEFORE app finishes launching to catch cold-start notification clicks
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        log("APP_LAUNCH: Delegate set in willFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("APP_LAUNCH: App started")

        // Setup standard Edit menu for copy/paste support
        setupEditMenu()

        // Initialize status bar (menu bar icon)
        statusBarController = StatusBarController()

        // Listen for settings window requests from status bar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowSettingsWindow),
            name: .showSettingsWindow,
            object: nil
        )

        // Listen for jump to terminal requests from status bar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleJumpToTerminal(_:)),
            name: .jumpToTerminal,
            object: nil
        )

        // Check if launched from notification click after a short delay
        // If no notification event received, this is a user-initiated launch (click app icon)
        // 0.3s to ensure notification callback has time to fire
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            if !self.launchedFromNotification {
                log("APP_LAUNCH: No notification event, showing settings window")
                self.showSettingsWindow()
            } else {
                log("APP_LAUNCH: Launched from notification, staying in background")
            }
        }
    }

    // MARK: - Handle App Reopen (click app icon while running)

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        log("REOPEN: hasVisibleWindows=\(flag)")

        if !flag {
            // Delay to check if notification click happened around the same time
            // 0.2s to ensure notification callback has time to set the flag
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }

                // If notification was clicked recently, skip showing settings
                if self.launchedFromNotification {
                    log("REOPEN: Skipping - notification click detected")
                    // Reset for future reopen events
                    self.launchedFromNotification = false
                } else {
                    log("REOPEN: No notification, showing settings window")
                    self.showSettingsWindow()
                }
            }
        }
        return true
    }

    // MARK: - Show Settings Window (GUI Mode)

    func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        settingsWindowController = SettingsWindowController()
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func handleShowSettingsWindow() {
        showSettingsWindow()
    }

    @objc func handleJumpToTerminal(_ notification: Notification) {
        guard let userInfo = notification.userInfo else {
            log("JUMP: No userInfo in notification")
            return
        }

        let bundleId = userInfo["bundleId"] as? String ?? "com.apple.Terminal"
        let terminalPid = userInfo["terminalPid"] as? Int32 ?? 0
        let windowId = userInfo["windowId"] as? UInt32 ?? 0

        log("JUMP: Jumping to terminal bundleId=\(bundleId) pid=\(terminalPid) windowId=\(windowId)")

        if terminalPid > 0 {
            activateAppByPID(pid: terminalPid, cgWindowID: windowId, fallbackBundle: bundleId)
        } else {
            activateApp(bundleID: bundleId)
        }
    }

    // MARK: - Handle Notification Click and Actions

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {

        // Mark that we were launched from notification (for cold start detection)
        launchedFromNotification = true

        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        log("CLICK_EVENT: Notification action=\(actionIdentifier)")

        let bundleID = userInfo["targetBundle"] as? String
        let targetPID = userInfo["targetPID"] as? Int32 ?? 0
        let cgWindowID = userInfo["cgWindowID"] as? UInt32 ?? 0

        // Handle different actions
        switch actionIdentifier {
        case "JUMP_ACTION", UNNotificationDefaultActionIdentifier:
            // Jump to terminal - activate the target window
            if targetPID > 0 {
                log("ACTION: Jumping to PID \(targetPID) CGWindowID=\(cgWindowID)")
                activateAppByPID(pid: targetPID, cgWindowID: cgWindowID, fallbackBundle: bundleID)
            } else if let bundleID = bundleID {
                log("ACTION: Falling back to bundle activation \(bundleID)")
                activateApp(bundleID: bundleID)
            } else {
                log("ERROR: No bundle ID or PID found in payload")
            }

        case "VIEW_ACTION":
            // View details - could open a details window in the future
            log("ACTION: View details requested")
            // For now, just activate the terminal
            if targetPID > 0 {
                activateAppByPID(pid: targetPID, cgWindowID: cgWindowID, fallbackBundle: bundleID)
            } else if let bundleID = bundleID {
                activateApp(bundleID: bundleID)
            }

        case "DISMISS_ACTION", UNNotificationDismissActionIdentifier:
            // Dismissed - just log and do nothing
            log("ACTION: Notification dismissed")

        default:
            log("ACTION: Unknown action \(actionIdentifier)")
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

        // 2. Unminimize window if needed via Accessibility API
        if cgWindowID > 0 {
            let appElement = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?

            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement] {

                for window in windows {
                    var windowID: CGWindowID = 0
                    let result = _AXUIElementGetWindow(window, &windowID)

                    if result == .success && windowID == cgWindowID {
                        // Unminimize if minimized
                        var minimizedRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
                           let isMinimized = minimizedRef as? Bool, isMinimized {
                            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                            log("ACTION: Unminimized window")
                        }

                        // Raise the specific window to front (critical for same-app multiple windows)
                        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                        log("ACTION: Raised window to front via AXRaiseAction")
                        break
                    }
                }
            }
        }

        // 3. Brief delay to ensure unminimize completes, then activate window
        // Reduced to 0.15s since AXRaiseAction now handles window ordering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.bringWindowToFront(pid: pid, cgWindowID: cgWindowID)
        }
    }

    // MARK: - Setup Edit Menu for Copy/Paste Support

    func setupEditMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit ClaudeMonitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
        log("APP_LAUNCH: Edit menu configured for copy/paste support")
    }

    // MARK: - Bring Window to Front using AppleScript (more reliable)

    func bringWindowToFront(pid: Int32, cgWindowID: UInt32) {
        log("ACTION: Bringing window to front via AppleScript (PID=\(pid), CGWindowID=\(cgWindowID))")

        // Use AppleScript to reliably bring window to front
        let script = """
        tell application "System Events"
            set targetProcess to first process whose unix id is \(pid)
            set frontmost of targetProcess to true
        end tell
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let err = error {
                log("AppleScript error: \(err)")
            } else {
                log("SUCCESS: Window brought to front via AppleScript")
            }
        }

        // Also activate via NSRunningApplication for extra reliability
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
