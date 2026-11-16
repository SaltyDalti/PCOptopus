import Foundation

public struct MachineIdentity: Codable, Sendable, Hashable {
    public var name: String
    public var modelIdentifier: String
    public var chip: String
    public var performanceCores: Int
    public var efficiencyCores: Int
    public var gpuCores: Int
    public var memoryBytes: UInt64
    public var storageContainerBytes: UInt64
    public var osVersion: String
    public var osBuild: String
    public var sipEnabled: Bool
    public var architecture: String

    public init(
        name: String,
        modelIdentifier: String,
        chip: String,
        performanceCores: Int,
        efficiencyCores: Int,
        gpuCores: Int,
        memoryBytes: UInt64,
        storageContainerBytes: UInt64,
        osVersion: String,
        osBuild: String,
        sipEnabled: Bool,
        architecture: String
    ) {
        self.name = name
        self.modelIdentifier = modelIdentifier
        self.chip = chip
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.gpuCores = gpuCores
        self.memoryBytes = memoryBytes
        self.storageContainerBytes = storageContainerBytes
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.sipEnabled = sipEnabled
        self.architecture = architecture
    }

    public var memoryGigabytesLabel: String {
        let gb = Double(memoryBytes) / 1_073_741_824.0
        return String(format: "%.0f GB unified memory", gb)
    }

    public var coreSplitLabel: String {
        "\(performanceCores) performance + \(efficiencyCores) efficiency cores"
    }

    public var unifiedMemorySentence: String {
        "On \(chip), CPU and GPU share \(memoryGigabytesLabel). Pressure rises when apps and graphics compete for the same pool — emptying RAM is wasted work."
    }

    /// Seed identity from the planning snapshot (redacted). Live sensors re-measure.
    public static let thisMacSeed = MachineIdentity(
        name: "MacBook Pro",
        modelIdentifier: "Mac16,7",
        chip: "Apple M4 Pro",
        performanceCores: 10,
        efficiencyCores: 4,
        gpuCores: 20,
        memoryBytes: 25_769_803_776,
        storageContainerBytes: 493_921_239_040,
        osVersion: "27.3",
        osBuild: "26C5035r",
        sipEnabled: true,
        architecture: "arm64"
    )
}

public struct AgentLabelInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: String { label }
    public var label: String
    public var summary: String
    public var suggestedDisable: Bool

    public init(label: String, summary: String, suggestedDisable: Bool = false) {
        self.label = label
        self.summary = summary
        self.suggestedDisable = suggestedDisable
    }

    public static let known: [AgentLabelInfo] = [
        AgentLabelInfo(label: "com.BlueStacks.AppPlayer.Service", summary: "BlueStacks Android emulator service — heavy resident process.", suggestedDisable: true),
        AgentLabelInfo(label: "com.BlueStacks.AppPlayer.UninstallWatcher", summary: "BlueStacks uninstall watcher.", suggestedDisable: true),
        AgentLabelInfo(label: "com.BlueStacks.AppPlayer.Updater", summary: "BlueStacks updater.", suggestedDisable: true),
        AgentLabelInfo(label: "com.adobe.GC.Invoker-1.0", summary: "Adobe Genuine Software Integrity service invoker."),
        AgentLabelInfo(label: "com.adobe.ccxprocess", summary: "Adobe Creative Cloud helper process."),
        AgentLabelInfo(label: "com.cvte.swst.service", summary: "Display-vendor helper — keep until you recognize the display it belongs to."),
        AgentLabelInfo(label: "com.dropbox.DropboxUpdater.wake", summary: "Dropbox updater wake agent."),
        AgentLabelInfo(label: "com.dropbox.dropboxmacupdate.agent", summary: "Dropbox Mac update agent."),
        AgentLabelInfo(label: "com.dropbox.dropboxmacupdate.xpcservice", summary: "Dropbox Mac update XPC service."),
        AgentLabelInfo(label: "com.google.GoogleUpdater.wake", summary: "Google Updater wake agent."),
        AgentLabelInfo(label: "com.google.keystone.agent", summary: "Google Software Update (Keystone) agent."),
        AgentLabelInfo(label: "com.google.keystone.xpcservice", summary: "Google Keystone XPC service."),
        AgentLabelInfo(label: "com.valvesoftware.steamclean", summary: "Steam cleanup helper.")
    ]

    public static func info(for label: String) -> AgentLabelInfo {
        known.first { $0.label == label }
            ?? AgentLabelInfo(label: label, summary: "User LaunchAgent — open its plist if you do not recognize it.")
    }
}
