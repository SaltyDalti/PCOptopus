import AppKit
import Model

// MARK: - Primitives

func label(_ text: String, font: NSFont, color: NSColor = .labelColor, wrap: Bool = true) -> NSTextField {
    // NonHittingTextField: plain NSTextField labels can steal clicks from buttons
    // when frames overlap during Auto Layout passes.
    let field = NonHittingTextField(wrappingLabelWithString: text)
    field.font = font
    field.textColor = color
    field.isSelectable = false
    field.isEditable = false
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    if !wrap {
        field.maximumNumberOfLines = 1
        field.cell?.lineBreakMode = .byTruncatingTail
    }
    return field
}

/// Label that never becomes the hit-test target — clicks fall through to controls beneath/alongside.
final class NonHittingTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

func vstack(_ views: [NSView], spacing: CGFloat = 8, alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = alignment
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

func hstack(_ views: [NSView], spacing: CGFloat = 8, alignment: NSLayoutConstraint.Attribute = .centerY) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = alignment
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

func flexibleSpacer() -> NSView {
    let v = NonHittingSpacer()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.setContentHuggingPriority(.defaultLow, for: .horizontal)
    v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return v
}

/// Spacer that never steals clicks from neighboring buttons.
private final class NonHittingSpacer: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

func hairline() -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    box.translatesAutoresizingMaskIntoConstraints = false
    return box
}

func primaryButton(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
    // Use a push button with a standard bezel — colored bezelStyle buttons
    // inside layer-backed scroll views intermittently drop mouse-up actions.
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .regularSquare
    button.setButtonType(.momentaryPushIn)
    button.isBordered = true
    button.isEnabled = true
    button.refusesFirstResponder = false
    button.isContinuous = false
    if #available(macOS 11.0, *) {
        button.controlSize = .large
    }
    button.font = Theme.bodyMedium()
    button.contentTintColor = Theme.accent
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
    return button
}

/// Big accent CTA that handles mouseDown itself — used when NSButton actions are flaky.
final class ActionChip: NSView {
    var title: String = "" {
        didSet { titleLabel.stringValue = title; needsDisplay = true }
    }
    var isEnabled: Bool = true {
        didSet { alphaValue = isEnabled ? 1 : 0.45 }
    }
    var onTap: (() -> Void)?

    private let titleLabel = NonHittingTextField(wrappingLabelWithString: "")
    private var pressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = Theme.accent.cgColor
        titleLabel.font = Theme.bodyMedium()
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        layer?.backgroundColor = Theme.accent.withAlphaComponent(0.85).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        layer?.backgroundColor = Theme.accent.cgColor
        defer { pressed = false }
        guard isEnabled, pressed else { return }
        let p = convert(event.locationInWindow, from: nil)
        if bounds.contains(p) {
            onTap?()
        }
    }

    override func mouseExited(with event: NSEvent) {
        pressed = false
        layer?.backgroundColor = Theme.accent.cgColor
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

func secondaryButton(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .rounded
    if #available(macOS 11.0, *) { button.controlSize = .large }
    return button
}

func linkButton(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .inline
    button.isBordered = false
    button.contentTintColor = Theme.accent
    button.font = Theme.bodyMedium()
    return button
}

// MARK: - Soft panel

final class SoftPanel: NSView {
    let content = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Layout.radius
        layer?.backgroundColor = Theme.elevated.cgColor
        // Keep mouse events flowing to buttons inside the panel.
        layer?.masksToBounds = false
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18)
        ])
    }

    override var acceptsFirstResponder: Bool { false }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.elevated.cgColor
    }

    func setViews(_ views: [NSView]) {
        content.arrangedSubviews.forEach {
            content.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        views.forEach { content.addArrangedSubview($0) }
    }
}

// MARK: - Badges

final class Pill: NSView {
    private let text = label("", font: Theme.captionMedium())

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9
        addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func set(_ string: String, color: NSColor) {
        text.stringValue = string
        text.textColor = color
        layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
    }
}

// MARK: - Pulse meter (Mac health 0…100)

final class PulseMeter: NSView {
    private let eyebrow = label("PULSE", font: Theme.captionMedium(), color: Theme.tertiaryLabel)
    private let valueLabel = label("—", font: Theme.display(36))
    private let detailLabel = label("", font: Theme.caption(), color: Theme.secondaryLabel)
    private let bar = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Layout.radius
        layer?.backgroundColor = Theme.elevated.cgColor

        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        bar.controlSize = .small
        bar.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.alignment = .right
        detailLabel.maximumNumberOfLines = 2

        let left = vstack([eyebrow, detailLabel], spacing: 4)
        let top = hstack([left, flexibleSpacer(), valueLabel], spacing: 12, alignment: .centerY)
        let stack = vstack([top, bar], spacing: 10)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            bar.heightAnchor.constraint(equalToConstant: 6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ pulse: PulseScore, autopilot: AutopilotStatus) {
        let color = Theme.pulse(pulse.band)
        eyebrow.textColor = color
        valueLabel.stringValue = "\(pulse.percent)"
        valueLabel.textColor = color
        bar.doubleValue = Double(pulse.percent)
        if pulse.percent >= 100 {
            detailLabel.stringValue = "Goal held at 100"
        } else if let drag = pulse.primaryDragTitle {
            let fight = autopilot == .on ? "Fighting" : "Arming fight"
            detailLabel.stringValue = "\(fight) for +\(pulse.deficit) · \(drag)"
        } else {
            detailLabel.stringValue = "Fighting for +\(pulse.deficit) toward 100"
        }
        layer?.backgroundColor = color.withAlphaComponent(0.08).cgColor
        setAccessibilityElement(true)
        setAccessibilityLabel("Pulse \(pulse.percent) percent. \(detailLabel.stringValue)")
        setAccessibilityRole(.group)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Color refreshed on next apply.
    }
}

// MARK: - Quiet vital (no heavy card chrome)

final class QuietVital: NSView {
    private let titleLabel = label("", font: Theme.captionMedium(), color: Theme.tertiaryLabel)
    private let valueLabel = label("", font: Theme.monoDigit())
    private let detailLabel = label("", font: Theme.caption(), color: Theme.secondaryLabel)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = vstack([titleLabel, valueLabel, detailLabel], spacing: 4)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(title: String, value: String, detail: String) {
        titleLabel.stringValue = title.uppercased()
        valueLabel.stringValue = value
        detailLabel.stringValue = detail
        setAccessibilityElement(true)
        setAccessibilityLabel("\(title): \(value). \(detail)")
        setAccessibilityRole(.group)
    }
}

// MARK: - Page shell (fixed document stack — do not rebuild)

final class PageShell: NSView {
    let scroll = NSScrollView()
    private let document = FlippedView()
    let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Theme.pageFill.cgColor

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false
        // Avoid contentInsets padding — it can desync drawing vs hit-testing.
        scroll.contentInsets = .init()
        scroll.scrollerInsets = .init()

        document.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Layout.gap
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        addSubview(scroll)

        // Pad with layout constants (not contentInsets). Pin document width to the
        // clip view so drawn frames match hit-testing (AppKit AL documentView rule).
        let inset = Layout.pageInset
        let widthCap = stack.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.contentMax)
        widthCap.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: inset),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: inset),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -inset),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.widthAnchor.constraint(equalTo: document.widthAnchor, constant: -(inset * 2)),
            widthCap
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func install(_ views: [NSView]) {
        views.forEach { stack.addArrangedSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
    }

    func scrollToReveal(_ view: NSView) {
        layoutSubtreeIfNeeded()
        let target = view.convert(view.bounds, to: scroll.contentView)
        scroll.contentView.scrollToVisible(target.insetBy(dx: 0, dy: -24))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.pageFill.cgColor
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Sidebar row

struct SidebarItem: Equatable {
    let id: String
    let title: String
    let symbol: String
}

final class SidebarRowView: NSTableCellView {
    private let icon = NSImageView()
    private let title = label("", font: Theme.bodyMedium(), wrap: false)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        // Labels/icons must not steal table selection clicks.
        title.refusesFirstResponder = true
        title.isSelectable = false
        icon.refusesFirstResponder = true
        let row = hstack([icon, title], spacing: 9)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Forward hits to the cell so NSTableView can change selection.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    func apply(_ item: SidebarItem, selected: Bool) {
        title.stringValue = item.title
        title.textColor = selected ? .labelColor : .secondaryLabelColor
        title.font = selected ? Theme.bodyMedium() : Theme.body()
        icon.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)
        icon.contentTintColor = selected ? Theme.accent : .tertiaryLabelColor
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
    }
}
