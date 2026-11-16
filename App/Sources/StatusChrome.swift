import AppKit

final class StatusStrip: NSView {
    private let spinner = NSProgressIndicator()
    private let message = label("", font: Theme.caption(), color: Theme.secondaryLabel)
    private let bar = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Theme.elevated.cgColor

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isDisplayedWhenStopped = false

        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = true
        bar.controlSize = .small

        let row = hstack([spinner, message, flexibleSpacer()], spacing: 8)
        addSubview(row)
        addSubview(bar)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 2)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(message: String, busy: Bool, progress: Double, baselineComplete: Bool) {
        self.message.stringValue = message
        busy ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
        if baselineComplete {
            bar.isHidden = true
        } else {
            bar.isHidden = false
            bar.doubleValue = progress
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.elevated.cgColor
    }
}

final class FlashBanner: NSView {
    private let text = label("", font: Theme.bodyMedium())

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        isHidden = true
        addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ message: String?) {
        guard let message, !message.isEmpty else {
            isHidden = true
            return
        }
        text.stringValue = message
        let bad = message.localizedCaseInsensitiveContains("couldn’t")
            || message.localizedCaseInsensitiveContains("failed")
            || message.localizedCaseInsensitiveContains("couldn't")
        let color = bad ? Theme.act : Theme.steady
        text.textColor = color
        layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        isHidden = false
    }
}
