import AppKit

// MARK: - Filter Bar Delegate

protocol TaskFilterBarDelegate: AnyObject {
    func filterBarDidChangeSearch(_ keyword: String)
    func filterBarDidChangeStatus(_ status: String?)
    func filterBarDidChangeAccount(_ account: String?)
    func filterBarDidRequestRefresh()
}

// MARK: - Task Filter Bar

class TaskFilterBar: NSView {

    weak var delegate: TaskFilterBarDelegate?

    private var searchField: NSSearchField!
    private var statusPopup: NSPopUpButton!
    private var accountPopup: NSPopUpButton!
    private var refreshButton: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true

        // Search field
        searchField = NSSearchField()
        searchField.placeholderString = "搜索会话..."
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        addSubview(searchField)

        // Status filter
        statusPopup = NSPopUpButton()
        statusPopup.translatesAutoresizingMaskIntoConstraints = false
        statusPopup.addItems(withTitles: [
            "全部状态",
            "工作中",
            "空闲",
            "等待决策",
            "已完成"
        ])
        statusPopup.target = self
        statusPopup.action = #selector(statusChanged(_:))
        addSubview(statusPopup)

        // Account filter
        accountPopup = NSPopUpButton()
        accountPopup.translatesAutoresizingMaskIntoConstraints = false
        accountPopup.addItem(withTitle: "全部账户")
        accountPopup.target = self
        accountPopup.action = #selector(accountChanged(_:))
        addSubview(accountPopup)

        // Refresh button
        refreshButton = NSButton()
        refreshButton.bezelStyle = .rounded
        refreshButton.title = "刷新"
        if #available(macOS 11.0, *) {
            refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        }
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked(_:))
        addSubview(refreshButton)

        // Layout
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 200),

            statusPopup.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 12),
            statusPopup.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusPopup.widthAnchor.constraint(equalToConstant: 100),

            accountPopup.leadingAnchor.constraint(equalTo: statusPopup.trailingAnchor, constant: 8),
            accountPopup.centerYAnchor.constraint(equalTo: centerYAnchor),
            accountPopup.widthAnchor.constraint(equalToConstant: 100),

            refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            refreshButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        // Load accounts
        loadAccounts()
    }

    private func loadAccounts() {
        let accounts = DatabaseManager.shared.getUniqueAccounts()
        for account in accounts {
            accountPopup.addItem(withTitle: account)
        }
    }

    func reloadAccounts() {
        accountPopup.removeAllItems()
        accountPopup.addItem(withTitle: "全部账户")
        loadAccounts()
    }

    // MARK: - Actions

    @objc private func searchChanged(_ sender: NSSearchField) {
        delegate?.filterBarDidChangeSearch(sender.stringValue)
    }

    @objc private func statusChanged(_ sender: NSPopUpButton) {
        let status: String?
        switch sender.indexOfSelectedItem {
        case 1: status = "working"
        case 2: status = "idle"
        case 3: status = "waiting_for_user"
        case 4: status = "completed"
        default: status = nil
        }
        delegate?.filterBarDidChangeStatus(status)
    }

    @objc private func accountChanged(_ sender: NSPopUpButton) {
        let account: String? = sender.indexOfSelectedItem == 0 ? nil : sender.titleOfSelectedItem
        delegate?.filterBarDidChangeAccount(account)
    }

    @objc private func refreshClicked(_ sender: NSButton) {
        delegate?.filterBarDidRequestRefresh()
    }
}
