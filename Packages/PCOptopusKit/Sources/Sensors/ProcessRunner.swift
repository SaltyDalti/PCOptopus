import Foundation

public protocol ProcessRunning: Sendable {
    func run(_ launchPath: String, arguments: [String]) throws -> String
}

public struct ShellProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ launchPath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        let err = Pipe()
        process.standardOutput = pipe
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public struct FixtureProcessRunner: ProcessRunning, @unchecked Sendable {
    private let map: [String: String]

    public init(map: [String: String]) {
        self.map = map
    }

    public func run(_ launchPath: String, arguments: [String]) throws -> String {
        let key = ([launchPath] + arguments).joined(separator: " ")
        if let value = map[key] { return value }
        // Fuzzy match by last argument tokens
        for (k, v) in map {
            if arguments.allSatisfy({ k.contains($0) }) || k.contains(arguments.joined(separator: " ")) {
                return v
            }
        }
        throw SensorError.commandFailed("No fixture for \(key)")
    }
}

public enum SensorError: Error, Sendable {
    case commandFailed(String)
    case parseFailed(String)
    case unavailable(String)
}
