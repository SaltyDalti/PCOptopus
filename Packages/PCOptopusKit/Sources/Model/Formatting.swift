import Foundation

public enum Formatters {
    public static func bytes(_ value: Double) -> String {
        bytes(UInt64(max(0, value)))
    }

    public static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(value)
        var idx = 0
        while size >= 1024 && idx < units.count - 1 {
            size /= 1024
            idx += 1
        }
        if idx == 0 {
            return "\(Int(size)) \(units[idx])"
        }
        if size >= 100 {
            return String(format: "%.0f %@", size, units[idx])
        }
        if size >= 10 {
            return String(format: "%.1f %@", size, units[idx])
        }
        return String(format: "%.2f %@", size, units[idx])
    }

    public static func availableOfTotal(available: UInt64, total: UInt64) -> String {
        "\(bytes(available)) available of \(bytes(total))"
    }

    public static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    public static func minutes(_ value: Int) -> String {
        if value == 0 { return "never (0)" }
        if value == 1 { return "1 minute" }
        return "\(value) minutes"
    }
}
