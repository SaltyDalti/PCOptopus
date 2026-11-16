import Foundation

/// Portfolio / screen-recording mode: sanitize host name and keep UI free of personal labels.
public enum DemoMode {
    public static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--demo") { return true }
        if ProcessInfo.processInfo.environment["PCOCTOPUS_DEMO"] == "1" { return true }
        let flag = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PCOptopus/demo.flag")
        return FileManager.default.fileExists(atPath: flag.path)
    }

    public static let displayName = "Demo MacBook Pro"

    /// Safe reclaimables for Show me / Fight for 100 demos. Never touch real user files.
    public static var seedCacheDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/PCOptopusDemo", isDirectory: true)
    }
}
