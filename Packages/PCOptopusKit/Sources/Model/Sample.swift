import Foundation

public struct Sample: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var domain: Domain
    public var timestamp: Date
    /// Metric values as JSON-friendly strings or numbers encoded as strings.
    public var metrics: [String: String]

    public init(
        id: UUID = UUID(),
        domain: Domain,
        timestamp: Date = Date(),
        metrics: [String: String] = [:]
    ) {
        self.id = id
        self.domain = domain
        self.timestamp = timestamp
        self.metrics = metrics
    }

    public func double(_ key: MetricKey) -> Double? {
        guard let raw = metrics[key.rawValue] else { return nil }
        return Double(raw)
    }

    public func int(_ key: MetricKey) -> Int? {
        guard let raw = metrics[key.rawValue] else { return nil }
        return Int(raw)
    }

    public func string(_ key: MetricKey) -> String? {
        metrics[key.rawValue]
    }

    public func bool(_ key: MetricKey) -> Bool? {
        guard let raw = metrics[key.rawValue]?.lowercased() else { return nil }
        switch raw {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }

    public mutating func set(_ key: MetricKey, _ value: String) {
        metrics[key.rawValue] = value
    }

    public mutating func set(_ key: MetricKey, _ value: Double) {
        metrics[key.rawValue] = String(value)
    }

    public mutating func set(_ key: MetricKey, _ value: Int) {
        metrics[key.rawValue] = String(value)
    }

    public mutating func set(_ key: MetricKey, _ value: Bool) {
        metrics[key.rawValue] = value ? "true" : "false"
    }
}

public struct SampleBundle: Codable, Sendable, Hashable {
    public var timestamp: Date
    public var samples: [Sample]

    public init(timestamp: Date = Date(), samples: [Sample] = []) {
        self.timestamp = timestamp
        self.samples = samples
    }

    public func sample(for domain: Domain) -> Sample? {
        samples.first { $0.domain == domain }
    }

    public func mergedMetrics() -> [String: String] {
        var out: [String: String] = [:]
        for sample in samples {
            for (k, v) in sample.metrics {
                out[k] = v
            }
        }
        return out
    }

    public func string(_ key: MetricKey) -> String? {
        mergedMetrics()[key.rawValue]
    }

    public func double(_ key: MetricKey) -> Double? {
        guard let raw = string(key) else { return nil }
        return Double(raw)
    }

    public func int(_ key: MetricKey) -> Int? {
        guard let raw = string(key) else { return nil }
        return Int(raw)
    }

    public func bool(_ key: MetricKey) -> Bool? {
        guard let raw = string(key)?.lowercased() else { return nil }
        switch raw {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }
}
