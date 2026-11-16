import Foundation

public enum Domain: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case compute
    case memory
    case storage
    case energy
    case background
    case software
    case network
    case practices

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compute: return "Compute"
        case .memory: return "Memory"
        case .storage: return "Storage"
        case .energy: return "Energy"
        case .background: return "Background"
        case .software: return "Software"
        case .network: return "Network"
        case .practices: return "Practices"
        }
    }

    public var whatGoodLooksLike: String {
        switch self {
        case .compute:
            return "Efficiency cores handle idle work; performance cores wake for bursts without sustained thermal pressure."
        case .memory:
            return "Memory pressure stays Normal; compressor may work; swap stays flat. Unified memory is shared with the GPU."
        case .storage:
            return "At least 80 GB available on the Data volume so updates, caches, and sleep images have room."
        case .energy:
            return "On AC, system sleep matches your work (about 15–60 minutes). Display sleep can be shorter."
        case .background:
            return "Every login helper has a name you recognize; unused emulators and updaters stay unloaded."
        case .software:
            return "Native arm64 tools are first on PATH; Rosetta Homebrew is a fallback, not the default."
        case .network:
            return "Background transfer is visible when active; quiet when you are deep in local work."
        case .practices:
            return "Four standing habits: free storage, docked sleep that matches work, known helpers, native Homebrew."
        }
    }
}
