import Foundation
import Model

public struct PmsetSettings: Sendable, Hashable {
    public var sleep: Int?
    public var displaysleep: Int?
    public var disksleep: Int?
    public var powernap: Int?
    public var womp: Int?
    public var hibernatemode: Int?
    public var standby: Int?
    public var tcpkeepalive: Int?
    public var ttyskeepawake: Int?

    public init(
        sleep: Int? = nil,
        displaysleep: Int? = nil,
        disksleep: Int? = nil,
        powernap: Int? = nil,
        womp: Int? = nil,
        hibernatemode: Int? = nil,
        standby: Int? = nil,
        tcpkeepalive: Int? = nil,
        ttyskeepawake: Int? = nil
    ) {
        self.sleep = sleep
        self.displaysleep = displaysleep
        self.disksleep = disksleep
        self.powernap = powernap
        self.womp = womp
        self.hibernatemode = hibernatemode
        self.standby = standby
        self.tcpkeepalive = tcpkeepalive
        self.ttyskeepawake = ttyskeepawake
    }

    public subscript(key: String) -> Int? {
        switch key {
        case "sleep": return sleep
        case "displaysleep": return displaysleep
        case "disksleep": return disksleep
        case "powernap": return powernap
        case "womp": return womp
        case "hibernatemode": return hibernatemode
        case "standby": return standby
        case "tcpkeepalive": return tcpkeepalive
        case "ttyskeepawake": return ttyskeepawake
        default: return nil
        }
    }
}

public enum PmsetParser {
    /// Parse `pmset -g custom` into AC and Battery maps.
    public static func parseCustom(_ text: String) -> (ac: PmsetSettings, battery: PmsetSettings) {
        var ac = PmsetSettings()
        var battery = PmsetSettings()
        var section: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasSuffix(":") {
                section = String(line.dropLast())
                continue
            }
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 2, let value = Int(parts[1]) else { continue }
            let key = String(parts[0])
            switch section {
            case "AC Power":
                ac = apply(key: key, value: value, to: ac)
            case "Battery Power":
                battery = apply(key: key, value: value, to: battery)
            default:
                break
            }
        }
        return (ac, battery)
    }

    public static func parseCurrent(_ text: String) -> PmsetSettings {
        var settings = PmsetSettings()
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Currently") || line.isEmpty { continue }
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 2, let value = Int(parts[1]) else { continue }
            settings = apply(key: String(parts[0]), value: value, to: settings)
        }
        return settings
    }

    private static func apply(key: String, value: Int, to settings: PmsetSettings) -> PmsetSettings {
        var s = settings
        switch key {
        case "sleep": s.sleep = value
        case "displaysleep": s.displaysleep = value
        case "disksleep": s.disksleep = value
        case "powernap": s.powernap = value
        case "womp": s.womp = value
        case "hibernatemode": s.hibernatemode = value
        case "standby": s.standby = value
        case "tcpkeepalive": s.tcpkeepalive = value
        case "ttyskeepawake": s.ttyskeepawake = value
        default: break
        }
        return s
    }
}
