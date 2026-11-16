import Foundation
import Model

public struct SystemApplier: ActionApplying {
    private let runner: ProcessRunner
    private let helperClient: HelperClienting

    public init(runner: ProcessRunner = ProcessRunner(), helperClient: HelperClienting = LocalHelperClient()) {
        self.runner = runner
        self.helperClient = helperClient
    }

    public func apply(
        actionID: String,
        parameters: [String: String],
        killSwitch: Bool
    ) throws -> ApplyResult {
        if killSwitch { throw ApplyError.killSwitchEngaged }
        switch actionID {
        case "energy.ac.sleep.set", "energy.ac.displaysleep.set", "energy.battery.sleep.set":
            return try applyPmset(parameters: parameters, killSwitch: killSwitch)
        case "background.agent.disable":
            return try applyLaunchAgent(parameters: parameters, enable: false)
        case "software.brew.path.native":
            return try applyNativeBrewPath()
        case "energy.assertion.quitApp":
            guard let name = parameters["processName"], !name.isEmpty else {
                throw ApplyError.failed("Missing processName")
            }
            _ = try runner.run("/usr/bin/osascript", arguments: [
                "-e", "tell application \"\(name)\" to quit"
            ])
            return ApplyResult()
        case "storage.scan.largeFolders":
            throw ApplyError.notImplemented("Scan is a read path in Sensors — UI invokes it directly.")
        default:
            throw ApplyError.unknownAction(actionID)
        }
    }

    public func rollback(
        actionID: String,
        rollbackPayload: String,
        parameters: [String: String],
        killSwitch: Bool
    ) throws -> ApplyResult {
        if killSwitch { throw ApplyError.killSwitchEngaged }
        switch actionID {
        case "energy.ac.sleep.set", "energy.ac.displaysleep.set", "energy.battery.sleep.set":
            var params = parameters
            params["value"] = rollbackPayload
            return try applyPmset(parameters: params, killSwitch: killSwitch)
        case "background.agent.disable":
            return try applyLaunchAgent(
                parameters: ["label": rollbackPayload],
                enable: true
            )
        case "software.brew.path.native":
            return try restoreZProfile(from: rollbackPayload)
        default:
            throw ApplyError.unknownAction(actionID)
        }
    }

    private func applyPmset(parameters: [String: String], killSwitch: Bool) throws -> ApplyResult {
        guard let key = parameters["key"],
              let powerSource = parameters["powerSource"],
              let valueString = parameters["value"],
              let value = Int(valueString) else {
            throw ApplyError.failed("Missing pmset parameters")
        }
        switch PmsetAllowlist.validate(key: key, powerSource: powerSource, value: value) {
        case .failure(let error):
            throw error
        case .success(let validated):
            try helperClient.setPmset(
                flag: validated.flag,
                key: validated.key,
                value: validated.value,
                killSwitch: killSwitch
            )
            return ApplyResult(rollbackPayload: valueString)
        }
    }

    private func applyLaunchAgent(parameters: [String: String], enable: Bool) throws -> ApplyResult {
        guard let label = parameters["label"], !label.isEmpty else {
            throw ApplyError.failed("Missing LaunchAgent label")
        }
        // Only user LaunchAgents
        if label.hasPrefix("com.apple.") {
            throw ApplyError.failed("System agents are out of scope")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let plist = home
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
        guard FileManager.default.fileExists(atPath: plist.path) else {
            throw ApplyError.failed("Plist not found for \(label)")
        }
        let uid = getuid()
        let domain = "gui/\(uid)"
        if enable {
            _ = try runner.run("/bin/launchctl", arguments: ["bootstrap", domain, plist.path])
        } else {
            // Copy plist contents into rollback via reading file
            let data = try Data(contentsOf: plist)
            _ = try? runner.run("/bin/launchctl", arguments: ["bootout", domain, plist.path])
            return ApplyResult(rollbackPayload: String(data: data, encoding: .utf8) ?? label)
        }
        return ApplyResult(rollbackPayload: label)
    }

    private func applyNativeBrewPath() throws -> ApplyResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let zprofile = home.appendingPathComponent(".zprofile")
        let previous: String
        if FileManager.default.fileExists(atPath: zprofile.path) {
            previous = try String(contentsOf: zprofile, encoding: .utf8)
        } else {
            previous = ""
        }
        let marker = "# PCOptopus native Homebrew"
        let line = "eval \"$(/opt/homebrew/bin/brew shellenv)\" \(marker)\n"
        var next = previous
        if !previous.contains("/opt/homebrew/bin") {
            next = line + previous
        } else if !previous.contains(marker) {
            // Already has opt/homebrew; still record journal
        }
        try next.write(to: zprofile, atomically: true, encoding: .utf8)
        return ApplyResult(rollbackPayload: previous)
    }

    private func restoreZProfile(from previous: String) throws -> ApplyResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let zprofile = home.appendingPathComponent(".zprofile")
        try previous.write(to: zprofile, atomically: true, encoding: .utf8)
        return ApplyResult()
    }
}

public struct ProcessRunner: Sendable {
    public init() {}

    public func run(_ launchPath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(data: errData, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            throw ApplyError.failed(message)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public protocol HelperClienting: Sendable {
    func setPmset(flag: String, key: String, value: Int, killSwitch: Bool) throws
}

/// Development path: invoke `pmset` directly. Production uses the privileged helper binary.
public struct LocalHelperClient: HelperClienting {
    public init() {}

    public func setPmset(flag: String, key: String, value: Int, killSwitch: Bool) throws {
        if killSwitch { throw ApplyError.killSwitchEngaged }
        guard PmsetAllowlist.keys.contains(key) else {
            throw ApplyError.refusedKey(key)
        }
        let runner = ProcessRunner()
        // pmset for the current user domain often needs admin for -c/-b writes.
        _ = try runner.run("/usr/bin/pmset", arguments: [flag, key, String(value)])
    }
}
