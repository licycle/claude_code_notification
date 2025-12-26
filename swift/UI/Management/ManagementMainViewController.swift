import AppKit

// MARK: - Navigation Item

enum NavigationItem: Int, CaseIterable {
    case taskCenter = 0
    case reports = 1
    case settings = 2

    var title: String {
        switch self {
        case .taskCenter: return "任务中心"
        case .reports: return "报告分析"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .taskCenter: return "list.bullet.rectangle"
        case .reports: return "chart.bar"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Management Main View Controller

class ManagementMainViewController: NSViewController {

    private var sidebarViewController: SidebarViewController!
    private var contentContainerView: NSView!
    private var currentContentViewController: NSViewController?

    private var taskCenterViewController: TaskCenterViewController?
    private var taskCenterDetailViewController: TaskCenterDetailViewController?
    private var reportsViewController: ReportsViewController?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1050, height: 650))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        showContent(for: .taskCenter)
    }

    private func setupUI() {
        // Sidebar (180px width)
        sidebarViewController = SidebarViewController()
        sidebarViewController.delegate = self
        addChild(sidebarViewController)

        let sidebarView = sidebarViewController.view
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebarView)

        // Content container
        contentContainerView = NSView()
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.wantsLayer = true
        view.addSubview(contentContainerView)

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)

        // Layout constraints
        NSLayoutConstraint.activate([
            // Sidebar
            sidebarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarView.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: 180),

            // Separator
            separator.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            separator.topAnchor.constraint(equalTo: view.topAnchor),
            separator.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            // Content container
            contentContainerView.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func showContent(for item: NavigationItem) {
        // Remove current content
        currentContentViewController?.view.removeFromSuperview()
        currentContentViewController?.removeFromParent()

        // Create or reuse view controller
        let newViewController: NSViewController

        switch item {
        case .taskCenter:
            if taskCenterViewController == nil {
                taskCenterViewController = TaskCenterViewController()
                taskCenterViewController?.delegate = self
            }
            newViewController = taskCenterViewController!

        case .reports:
            if reportsViewController == nil {
                reportsViewController = ReportsViewController()
            }
            newViewController = reportsViewController!

        case .settings:
            // Open settings window instead
            NotificationCenter.default.post(name: .showSettingsWindow, object: nil)
            return
        }

        // Add new content
        addChild(newViewController)
        newViewController.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(newViewController.view)

        NSLayoutConstraint.activate([
            newViewController.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            newViewController.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            newViewController.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            newViewController.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor)
        ])

        currentContentViewController = newViewController
    }

    func refresh() {
        taskCenterViewController?.refresh()
        reportsViewController?.refresh()
    }
}

// MARK: - Sidebar Delegate

extension ManagementMainViewController: SidebarViewControllerDelegate {
    func sidebarDidSelectItem(_ item: NavigationItem) {
        showContent(for: item)
    }
}

// MARK: - TaskCenter Delegate

extension ManagementMainViewController: TaskCenterViewControllerDelegate {
    func taskCenterDidRequestShowDetail(_ session: SessionInfo) {
        showTaskCenterDetail(session: session)
    }

    private func showTaskCenterDetail(session: SessionInfo) {
        // Remove current content
        currentContentViewController?.view.removeFromSuperview()
        currentContentViewController?.removeFromParent()

        // Create detail view controller
        let detailVC = TaskCenterDetailViewController(session: session)
        detailVC.delegate = self
        taskCenterDetailViewController = detailVC

        // Add to view
        addChild(detailVC)
        detailVC.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(detailVC.view)

        NSLayoutConstraint.activate([
            detailVC.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            detailVC.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            detailVC.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            detailVC.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor)
        ])

        currentContentViewController = detailVC
    }
}

// MARK: - TaskCenterDetail Delegate

extension ManagementMainViewController: TaskCenterDetailViewControllerDelegate {
    func taskCenterDetailDidRequestBack() {
        taskCenterDetailViewController = nil
        showContent(for: .taskCenter)
    }

    func taskCenterDetailDidRequestJump(_ session: SessionInfo) {
        NotificationCenter.default.post(
            name: .jumpToTerminal,
            object: nil,
            userInfo: [
                "bundleId": session.bundleId ?? "com.apple.Terminal",
                "terminalPid": session.terminalPid ?? 0,
                "windowId": session.windowId ?? 0
            ]
        )
    }
}
