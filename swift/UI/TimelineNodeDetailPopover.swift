import AppKit

// MARK: - Timeline Node Detail Popover
// 时间线节点详情 Popover
// 用于显示完整的节点标题和描述，支持多行滚动显示

class TimelineNodeDetailPopover: NSViewController {

    // MARK: - Properties

    private let nodeTitle: String
    private let nodeDescription: String

    // MARK: - Initialization

    init(title: String, description: String) {
        self.nodeTitle = title
        self.nodeDescription = description
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override func loadView() {
        // 计算内容高度（基于文本长度）
        let maxWidth: CGFloat = 280  // 内容区域最大宽度（减去 padding）
        let maxHeight: CGFloat = 160 // 最大显示高度

        // 创建临时 NSTextField 来测量文本高度
        let font = NSFont.systemFont(ofSize: 12)
        let combinedText = "\(nodeTitle)\n\n\(nodeDescription)"

        let tempTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: maxWidth, height: 0))
        tempTextView.font = font
        tempTextView.string = combinedText
        tempTextView.textContainerInset = NSSize(width: 0, height: 0)

        // 计算实际需要的高度
        tempTextView.sizeToFit()
        let contentHeight = min(tempTextView.frame.height + 20, maxHeight)

        // 创建主视图（包含 padding）
        let totalWidth: CGFloat = 300  // 280 + 20 (左右各 10px padding)
        view = NSView(frame: NSRect(x: 0, y: 0, width: totalWidth, height: contentHeight + 20))

        // 设置背景（可选）
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        // 创建滚动视图
        let scrollView = NSScrollView(frame: NSRect(x: 10, y: 10, width: maxWidth, height: contentHeight))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // 创建文本视图
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: maxWidth - 20, height: 0))
        textView.isEditable = false
        textView.isSelectable = true  // 允许用户选择和复制文本
        textView.backgroundColor = .clear
        textView.font = font
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 4, height: 4)

        // 设置文本内容
        let attributedString = NSMutableAttributedString()

        // 标题（粗体）
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        attributedString.append(NSAttributedString(string: nodeTitle, attributes: titleAttributes))

        // 分隔行
        attributedString.append(NSAttributedString(string: "\n\n"))

        // 描述（普通字体）
        let descAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        attributedString.append(NSAttributedString(string: nodeDescription, attributes: descAttributes))

        textView.textStorage?.setAttributedString(attributedString)

        // 自动调整文本视图高度
        textView.sizeToFit()

        // 设置 scroll view 的 document view
        scrollView.documentView = textView

        // 添加到主视图
        view.addSubview(scrollView)
    }
}
