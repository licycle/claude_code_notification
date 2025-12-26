import AppKit

// MARK: - Management Window Controller

class ManagementWindowController: NSWindowController {

    private var mainViewController: ManagementMainViewController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width:1100, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Claude Monitor - Management Center"
        window.minSize = NSSize(width: 1050, height: 550)
        window.center()

        // Set window appearance
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }

        self.init(window: window)
        setupContent()
    }

    private func setupContent() {
        mainViewController = ManagementMainViewController()
        window?.contentViewController = mainViewController
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Refresh data when window is shown
        mainViewController?.refresh()
    }

    func refresh() {
        mainViewController?.refresh()
    }
}
