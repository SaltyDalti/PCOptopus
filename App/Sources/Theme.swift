import AppKit
import Model

enum Theme {
    /// Calm steel blue — one accent only.
    static let accent = NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.70, alpha: 1)
    static let steady = NSColor(calibratedRed: 0.22, green: 0.55, blue: 0.42, alpha: 1)
    static let attention = NSColor(calibratedRed: 0.80, green: 0.52, blue: 0.14, alpha: 1)
    static let act = NSColor(calibratedRed: 0.75, green: 0.28, blue: 0.26, alpha: 1)

    static var secondaryLabel: NSColor { .secondaryLabelColor }
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }
    static var pageFill: NSColor { .windowBackgroundColor }
    static var sidebarFill: NSColor { NSColor.controlBackgroundColor.withSystemEffect(.disabled) }
    static var elevated: NSColor { .controlBackgroundColor }
    static var hairline: NSColor { .separatorColor }

    static func severity(_ s: Severity) -> NSColor {
        switch s {
        case .steady: return steady
        case .attention: return attention
        case .act: return act
        }
    }

    static func autopilot(_ s: AutopilotStatus) -> NSColor {
        switch s {
        case .off: return .secondaryLabelColor
        case .on: return steady
        case .paused: return attention
        case .stopped: return act
        }
    }

    static func pulse(_ band: PulseScore.Band) -> NSColor {
        switch band {
        case .excellent: return steady
        case .good: return accent
        case .strained: return attention
        case .critical: return act
        }
    }

    static func display(_ size: CGFloat = 32) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }
    static func title(_ size: CGFloat = 22) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }
    static func headline() -> NSFont { .systemFont(ofSize: 15, weight: .semibold) }
    static func body() -> NSFont { .systemFont(ofSize: 13, weight: .regular) }
    static func bodyMedium() -> NSFont { .systemFont(ofSize: 13, weight: .medium) }
    static func caption() -> NSFont { .systemFont(ofSize: 11, weight: .regular) }
    static func captionMedium() -> NSFont { .systemFont(ofSize: 11, weight: .medium) }
    static func mono() -> NSFont { .monospacedSystemFont(ofSize: 12, weight: .regular) }
    static func monoDigit() -> NSFont { .monospacedDigitSystemFont(ofSize: 14, weight: .medium) }
}

enum Layout {
    static let pageInset: CGFloat = 36
    static let contentMax: CGFloat = 720
    static let sidebarWidth: CGFloat = 188
    static let radius: CGFloat = 14
    static let gap: CGFloat = 20
}
