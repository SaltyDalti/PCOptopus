import Foundation

/// Helper allowlist is code, not a prompt. Unknown keys are refused.
public enum PmsetAllowlist {
    public static let keys: Set<String> = [
        "sleep",
        "displaysleep",
        "disksleep",
        "powernap",
        "womp",
        "tcpkeepalive",
        "ttyskeepawake"
    ]

    public static let powerSourceFlags: Set<String> = ["-c", "-b", "AC", "Battery"]

    public static func flag(for powerSource: String) -> String? {
        switch powerSource {
        case "AC", "-c": return "-c"
        case "Battery", "-b": return "-b"
        default: return nil
        }
    }

    public static func validate(key: String, powerSource: String, value: Int) -> Result<(flag: String, key: String, value: Int), ApplyError> {
        guard keys.contains(key) else {
            return .failure(.refusedKey(key))
        }
        guard let flag = flag(for: powerSource) else {
            return .failure(.failed("Unknown power source \(powerSource)"))
        }
        guard value >= 0, value <= 1440 else {
            return .failure(.failed("Value \(value) out of range"))
        }
        return .success((flag, key, value))
    }
}
