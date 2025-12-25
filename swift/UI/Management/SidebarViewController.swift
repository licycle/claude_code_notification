import AppKit

// MARK: - Sidebar Delegate Protocol

protocol SidebarViewControllerDelegate: AnyObject {
    func sidebarDidSelectItem(_ item: NavigationItem)
}

// MARK: - Sidebar View Controller

class SidebarViewController: NSViewController {

    weak var delegate: SidebarViewControllerDelegate?

    private var buttons: [NSButton] = []
    private var selectedItem: NavigationItem = .taskCenter

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 600))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateSelection()
    }

    private func setupUI() {
        // Title
        let titleLabel = NSTextField(labelWithString: "Claude Monitor")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Navigation buttons container
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        // Create navigation buttons
        for item in NavigationItem.allCases {
            let button = createNavButton(for: item)
            buttons.append(button)
            stackView.addArrangedSubview(button)

            button.widthAnchor.constraint(equalToConstant: 160).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }

        // Layout
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            stackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10)
        ])
    }

    private func createNavButton(for item: NavigationItem) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .recessed
        button.isBordered = false
        button.tag = item.rawValue

        // Set title with icon
        if #available(macOS 11.0, *) {
            let image = NSImage(systemSymbolName: item.icon, accessibilityDescription: item.title)
            button.image = image
            button.imagePosition = .imageLeading
        }

        button.title = "  " + item.title
        button.alignment = .left
        button.font = NSFont.systemFont(ofSize: 13)

        button.target = self
        button.action = #selector(navButtonClicked(_:))

        return button
    }

    @objc private func navButtonClicked(_ sender: NSButton) {
        guard let item = NavigationItem(rawValue: sender.tag) else { return }
        selectedItem = item
        updateSelection()
        delegate?.sidebarDidSelectItem(item)
    }

    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            let isSelected = index == selectedItem.rawValue

            if isSelected {
                button.contentTintColor = .controlAccentColor
                button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
                button.layer?.cornerRadius = 6
            } else {
                button.contentTintColor = .labelColor
                button.layer?.backgroundColor = nil
            }
        }
    }
}
