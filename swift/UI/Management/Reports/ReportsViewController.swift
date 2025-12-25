import AppKit

// MARK: - Reports View Controller

class ReportsViewController: NSViewController {

    private var tabView: NSSegmentedControl!
    private var contentView: NSView!
    private var dailyReportView: DailyReportView?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 600))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        showDailyReport()
    }

    private func setupUI() {
        // Tab control
        tabView = NSSegmentedControl(labels: ["日报", "周报", "月报"], trackingMode: .selectOne, target: self, action: #selector(tabChanged(_:)))
        tabView.selectedSegment = 0
        tabView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabView)

        // Content container
        contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)

        // Layout
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            tabView.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            contentView.topAnchor.constraint(equalTo: tabView.bottomAnchor, constant: 12),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: showDailyReport()
        case 1: showComingSoon("周报")
        case 2: showComingSoon("月报")
        default: break
        }
    }

    private func showDailyReport() {
        contentView.subviews.forEach { $0.removeFromSuperview() }

        if dailyReportView == nil {
            dailyReportView = DailyReportView()
        }

        dailyReportView!.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dailyReportView!)

        NSLayoutConstraint.activate([
            dailyReportView!.topAnchor.constraint(equalTo: contentView.topAnchor),
            dailyReportView!.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dailyReportView!.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dailyReportView!.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        dailyReportView!.refresh()
    }

    private func showComingSoon(_ title: String) {
        contentView.subviews.forEach { $0.removeFromSuperview() }

        let label = NSTextField(labelWithString: "\(title)功能即将推出...")
        label.font = NSFont.systemFont(ofSize: 16)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    func refresh() {
        dailyReportView?.refresh()
    }
}
