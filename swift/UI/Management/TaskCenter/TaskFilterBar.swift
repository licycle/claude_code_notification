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
        setupLanguageObserver()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupLanguageObserver()
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
        searchField.placeholderString = L(.filter_search_placeholder)
        refreshButton.title = L(.session_list_refresh)
        updateStatusPopup()
        reloadAccounts()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func updateStatusPopup() {
        let currentIndex = statusPopup.indexOfSelectedItem
        statusPopup.removeAllItems()
        statusPopup.addItems(withTitles: [
            L(.filter_all_status),
            L(.filter_working),
            L(.filter_idle),
            L(.filter_waiting),
            L(.filter_completed)
        ])
        statusPopup.selectItem(at: currentIndex)
    }

    private func setupUI() {
        wantsLayer = true

        // Search field
        searchField = NSSearchField()
        searchField.placeholderString = L(.filter_search_placeholder)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        addSubview(searchField)

        // Status filter
        statusPopup = NSPopUpButton()
        statusPopup.translatesAutoresizingMaskIntoConstraints = false
        statusPopup.addItems(withTitles: [
            L(.filter_all_status),
            L(.filter_working),
            L(.filter_idle),
            L(.filter_waiting),
            L(.filter_completed)
        ])
        statusPopup.target = self
        statusPopup.action = #selector(statusChanged(_:))
        addSubview(statusPopup)

        // Account filter
        accountPopup = NSPopUpButton()
        accountPopup.translatesAutoresizingMaskIntoConstraints = false
        accountPopup.addItem(withTitle: L(.filter_all_accounts))
        accountPopup.target = self
        accountPopup.action = #selector(accountChanged(_:))
        addSubview(accountPopup)

        // Refresh button
        refreshButton = NSButton()
        refreshButton.bezelStyle = .rounded
        refreshButton.title = L(.session_list_refresh)
        if #available(macOS 11.0, *) {
            refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
            refreshButton.imagePosition = .imageLeading
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
        accountPopup.addItem(withTitle: L(.filter_all_accounts))
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
