import Foundation

/// Single health number the coach and autopilot fight to keep near 100.
public struct PulseScore: Sendable, Equatable {
    public enum Band: String, Sendable, Equatable {
        case excellent
        case good
        case strained
        case critical

        public var title: String {
            switch self {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .strained: return "Strained"
            case .critical: return "Critical"
            }
        }
    }

    public struct Drag: Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var points: Int

        public init(id: String, title: String, points: Int) {
            self.id = id
            self.title = title
            self.points = points
        }
    }

    public var percent: Int
    public var band: Band
    public var drags: [Drag]

    public var deficit: Int { max(0, 100 - percent) }

    public var headline: String {
        if percent >= 100 {
            return "Pulse 100 — holding steady"
        }
        return "Pulse \(percent) — fighting for +\(deficit)"
    }

    public var primaryDragTitle: String? { drags.first?.title }

    public init(percent: Int, band: Band, drags: [Drag]) {
        self.percent = min(100, max(0, percent))
        self.band = band
        self.drags = drags
    }

    public static let measuring = PulseScore(percent: 100, band: .excellent, drags: [])

    /// Scores machine health from current findings and live metrics.
    public static func compute(findings: [Finding], bundle: SampleBundle) -> PulseScore {
        var score = 100.0
        var drags: [Drag] = []

        let actionable = findings
            .filter { $0.severity >= .attention }
            .sorted { $0.severity > $1.severity }

        for finding in actionable {
            let hit: Double
            switch finding.severity {
            case .act: hit = 14
            case .attention: hit = 8
            case .steady: hit = 0
            }
            guard hit > 0 else { continue }
            score -= hit
            drags.append(Drag(id: finding.id, title: finding.title, points: Int(hit)))
        }

        // Soft metric pressure even when a rule hasn't fired yet.
        if let available = bundle.double(.storageAvailableBytes) {
            let gb = available / 1_000_000_000
            if gb < 80, !drags.contains(where: { $0.id.hasPrefix("storage.") }) {
                let hit = min(18.0, (80 - gb) / 80 * 22)
                if hit >= 3 {
                    score -= hit
                    drags.append(Drag(id: "metric.storage", title: "Storage headroom", points: Int(hit.rounded())))
                }
            }
        }

        if let pressure = bundle.string(.memoryPressure)?.lowercased() {
            if pressure.contains("critical") {
                score -= 22
                drags.append(Drag(id: "metric.memory", title: "Memory pressure critical", points: 22))
            } else if pressure.contains("warn") {
                score -= 10
                drags.append(Drag(id: "metric.memory", title: "Memory pressure elevated", points: 10))
            }
        }

        if let thermal = bundle.string(.energyThermalState)?.lowercased() {
            if thermal.contains("critical") {
                score -= 18
                drags.append(Drag(id: "metric.thermal", title: "Thermal critical", points: 18))
            } else if thermal.contains("serious") {
                score -= 8
                drags.append(Drag(id: "metric.thermal", title: "Thermal pressure", points: 8))
            }
        }

        let percent = Int(score.rounded())
        let clamped = min(100, max(0, percent))
        let band: Band
        switch clamped {
        case 90...100: band = .excellent
        case 75..<90: band = .good
        case 50..<75: band = .strained
        default: band = .critical
        }

        let sorted = Array(drags.sorted { $0.points > $1.points }.prefix(5))
        return PulseScore(percent: clamped, band: band, drags: sorted)
    }
}
