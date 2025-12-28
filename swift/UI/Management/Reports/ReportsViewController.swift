import AppKit

// MARK: - Reports View Controller

class ReportsViewController: NSViewController {

    private var tabView: NSSegmentedControl!
    private var contentView: NSView!
    private var dailyReportView: DailyReportView?
    private var comingSoonLabel: NSTextField?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 600))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupLanguageObserver()
        showDailyReport()
    }

    private func setupLanguageObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: LocalizationManager.languageChangedNotification,
            object: nil
        )
    }

    @objc private func languageDidChange() {
        updateTabLabels()
        comingSoonLabel?.stringValue = L(.report_coming_soon)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func updateTabLabels() {
        tabView.setLabel(L(.report_daily), forSegment: 0)
        tabView.setLabel(L(.report_weekly), forSegment: 1)
        tabView.setLabel(L(.report_monthly), forSegment: 2)
    }

    private func setupUI() {
        // Tab control
        tabView = NSSegmentedControl(labels: [L(.report_daily), L(.report_weekly), L(.report_monthly)], trackingMode: .selectOne, target: self, action: #selector(tabChanged(_:)))
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
        case 1: showComingSoon()
        case 2: showComingSoon()
        default: break
        }
    }

    private func showDailyReport() {
        contentView.subviews.forEach { $0.removeFromSuperview() }
        comingSoonLabel = nil

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

    private func showComingSoon() {
        contentView.subviews.forEach { $0.removeFromSuperview() }

        let label = NSTextField(labelWithString: L(.report_coming_soon))
        label.font = NSFont.systemFont(ofSize: 16)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        comingSoonLabel = label

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    func refresh() {
        dailyReportView?.refresh()
    }
}
