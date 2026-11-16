import Foundation
import Model

/// A reclaim candidate — never deleted automatically; shown for the user to review.
public struct StorageCandidate: Sendable, Hashable, Identifiable {
    public enum Category: String, Sendable, Hashable, CaseIterable {
        case trash
        case cache
        case log
        case buildArtifact
        case download
        case media
        case appData
        case other

        public var title: String {
            switch self {
            case .trash: return "Trash"
            case .cache: return "Cache"
            case .log: return "Logs"
            case .buildArtifact: return "Build leftover"
            case .download: return "Old download"
            case .media: return "Unused media"
            case .appData: return "App data"
            case .other: return "Large & idle"
            }
        }

        /// Higher = prefer recommending first (regenerable / safer).
        var baseWeight: Double {
            switch self {
            case .trash: return 100
            case .cache: return 95
            case .log: return 90
            case .buildArtifact: return 88
            case .download: return 70
            case .appData: return 55
            case .media: return 48
            case .other: return 40
            }
        }
    }

    public var id: String { path }
    public var path: String
    public var bytes: UInt64
    public var category: Category
    public var reason: String
    public var daysIdle: Int?
    public var priority: Double
    public var recommended: Bool

    public init(
        path: String,
        bytes: UInt64,
        category: Category,
        reason: String,
        daysIdle: Int? = nil,
        priority: Double = 0,
        recommended: Bool = false
    ) {
        self.path = path
        self.bytes = bytes
        self.category = category
        self.reason = reason
        self.daysIdle = daysIdle
        self.priority = priority
        self.recommended = recommended
    }
}

public struct StorageScanResult: Sendable {
    public var candidates: [StorageCandidate]
    public var accessDenied: Bool
    public var targetFreeBytes: UInt64
    public var availableBytes: UInt64
    public var bytesNeeded: UInt64
    public var recommendedBytes: UInt64

    public var recommended: [StorageCandidate] { candidates.filter(\.recommended) }

    public init(
        candidates: [StorageCandidate] = [],
        accessDenied: Bool = false,
        targetFreeBytes: UInt64 = StorageScanner.targetFreeBytes,
        availableBytes: UInt64 = 0,
        bytesNeeded: UInt64 = 0,
        recommendedBytes: UInt64 = 0
    ) {
        self.candidates = candidates
        self.accessDenied = accessDenied
        self.targetFreeBytes = targetFreeBytes
        self.availableBytes = availableBytes
        self.bytesNeeded = bytesNeeded
        self.recommendedBytes = recommendedBytes
    }
}

/// Fast, FileManager-only reclaim scan. No `du` subprocesses — must finish quickly.
public struct StorageScanner: Sendable {
    public static let targetFreeBytes: UInt64 = 80_000_000_000

    private let minCandidateBytes: UInt64 = 20_000_000
    private let overallBudgetSeconds: TimeInterval = 6

    public init() {}

    public func scan(availableBytes: UInt64, limit: Int = 36) -> StorageScanResult {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let needed = availableBytes >= Self.targetFreeBytes
            ? UInt64(0)
            : Self.targetFreeBytes - availableBytes
        let deadline = Date().addingTimeInterval(overallBudgetSeconds)
        var accessDenied = false
        var raw: [StorageCandidate] = []

        // Only scan Library / Trash / build leftovers by default.
        // Touching Downloads/Documents/Desktop/Movies triggers interactive TCC
        // "Allow" sheets and feels like permissions are going crazy — especially
        // while the app is still ad-hoc signed. Full Disk Access covers these
        // Library paths without per-folder prompts.
        //
        // Demo mode: only the seeded PCOptopusDemo folder so recordings never
        // surface real Discord/Code/Adobe paths or other personal leftovers.
        let roots: [(path: String, category: StorageCandidate.Category)] = {
            if DemoMode.isEnabled {
                let demo = DemoMode.seedCacheDirectory.path
                return [
                    (demo, .cache),
                    ("\(demo)/OldInstallerLeftovers", .buildArtifact),
                    ("\(demo)/StaleBuildCache", .buildArtifact)
                ]
            }
            return [
                ("\(home)/.Trash", .trash),
                ("\(home)/Library/Caches", .cache),
                ("\(home)/Library/Logs", .log),
                ("\(home)/Library/Developer/Xcode/DerivedData", .buildArtifact),
                ("\(home)/Library/Developer/Xcode/Archives", .buildArtifact),
                ("\(home)/Library/Developer/CoreSimulator/Caches", .buildArtifact),
                ("\(home)/Library/Application Support/Caches", .cache),
                ("\(home)/Library/Application Support/Steam", .appData),
                ("\(home)/Library/Application Support/BlueStacks", .appData),
                ("\(home)/Library/Application Support/Adobe", .appData),
                ("\(home)/Library/Application Support/Google", .appData),
                ("\(home)/Library/Application Support/Discord", .appData),
                ("\(home)/Library/Application Support/Code", .cache),
                ("\(home)/Library/Application Support/Cursor", .cache)
            ]
        }()

        for root in roots {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0.15 { break }
            let slice = timed(
                seconds: min(0.45, remaining),
                fallback: RootSlice(candidates: [], accessDenied: false)
            ) {
                self.scanRoot(
                    root.path,
                    category: root.category,
                    home: home,
                    deadline: Date().addingTimeInterval(0.4)
                )
            }
            raw.append(contentsOf: slice.candidates)
            if slice.accessDenied { accessDenied = true }
        }

        // Dedup by path; prefer higher priority.
        var byPath: [String: StorageCandidate] = [:]
        for item in raw where item.bytes >= minCandidateBytes {
            if let existing = byPath[item.path], existing.priority >= item.priority { continue }
            byPath[item.path] = item
        }

        // Drop parents when a child is listed.
        let paths = Array(byPath.keys)
        for path in paths {
            if paths.contains(where: { $0 != path && $0.hasPrefix(path + "/") }) {
                byPath.removeValue(forKey: path)
            }
        }

        var ranked = Array(byPath.values)
        for i in ranked.indices {
            ranked[i].priority = score(ranked[i])
        }
        ranked.sort { $0.priority > $1.priority }

        var recommendedBytes: UInt64 = 0
        var marked: [StorageCandidate] = []
        let safeWhenHealthy: Set<StorageCandidate.Category> = [.trash, .cache, .log, .buildArtifact]
        for var item in ranked.prefix(limit) {
            if needed == 0 {
                item.recommended = safeWhenHealthy.contains(item.category) && recommendedBytes < 8_000_000_000
            } else {
                item.recommended = recommendedBytes < needed
            }
            if item.recommended { recommendedBytes += item.bytes }
            marked.append(item)
        }

        return StorageScanResult(
            candidates: marked,
            accessDenied: accessDenied,
            targetFreeBytes: Self.targetFreeBytes,
            availableBytes: availableBytes,
            bytesNeeded: needed,
            recommendedBytes: recommendedBytes
        )
    }

    // MARK: - Root walk (no subprocesses)

    private struct RootSlice: Sendable {
        var candidates: [StorageCandidate]
        var accessDenied: Bool
    }

    private func scanRoot(
        _ root: String,
        category: StorageCandidate.Category,
        home: String,
        deadline: Date
    ) -> RootSlice {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir) else {
            return RootSlice(candidates: [], accessDenied: false)
        }

        var out: [StorageCandidate] = []
        var accessDenied = false

        if !isDir.boolValue {
            if let cand = candidateFile(root, category: category, home: home) {
                out.append(cand)
            }
            return RootSlice(candidates: out, accessDenied: false)
        }

        let names: [String]
        do {
            names = try fm.contentsOfDirectory(atPath: root)
        } catch {
            return RootSlice(candidates: [], accessDenied: isPermissionError(error))
        }

        let preferChildren = ["Application Support", "Documents", "Desktop", "Downloads", "Movies", "Music", "Pictures", "Caches"]
            .contains { root.hasSuffix("/\($0)") }

        if !preferChildren, let rootCand = candidateDirectory(root, category: category, home: home, maxDepth: 1, itemCap: 250) {
            out.append(rootCand)
        }

        let ordered = names
            .filter { !shouldSkipName($0) }
            .sorted { heavyNameRank($0) > heavyNameRank($1) }

        for name in ordered.prefix(24) {
            if Date() > deadline { break }
            let childPath = (root as NSString).appendingPathComponent(name)
            var childDir: ObjCBool = false
            guard fm.fileExists(atPath: childPath, isDirectory: &childDir) else { continue }
            let childCategory = categorize(path: childPath, fallback: category)
            if childDir.boolValue {
                if let cand = candidateDirectory(childPath, category: childCategory, home: home, maxDepth: 1, itemCap: 200) {
                    out.append(cand)
                }
            } else if let cand = candidateFile(childPath, category: childCategory, home: home) {
                out.append(cand)
            }
        }

        // Downloads: also list large idle files at top level.
        if root.hasSuffix("/Downloads") {
            for name in ordered.prefix(40) {
                if Date() > deadline { break }
                let path = (root as NSString).appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
                if let cand = candidateFile(path, category: .download, home: home) {
                    out.append(cand)
                }
            }
        }

        return RootSlice(candidates: out, accessDenied: accessDenied)
    }

    private func candidateFile(_ path: String, category: StorageCandidate.Category, home: String) -> StorageCandidate? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .contentAccessDateKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
        let bytes = UInt64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        guard bytes >= minCandidateBytes else { return nil }
        let idle = daysIdle(modified: values.contentModificationDate, accessed: values.contentAccessDate)
        let resolved = categorize(path: path, fallback: category)
        let lower = path.lowercased()
        let installer = [".dmg", ".pkg", ".zip", ".iso"].contains { lower.hasSuffix($0) }
        let threshold = installer ? 14 : idleThreshold(for: resolved)
        if [.download, .media, .other].contains(resolved) {
            guard let idle, idle >= threshold else { return nil }
        }
        var cand = StorageCandidate(
            path: redactHome(path, home: home),
            bytes: bytes,
            category: resolved,
            reason: reasonText(category: resolved, idle: idle, bytes: bytes),
            daysIdle: idle
        )
        cand.priority = score(cand) + (installer ? 8 : 0)
        return cand
    }

    private func candidateDirectory(
        _ path: String,
        category: StorageCandidate.Category,
        home: String,
        maxDepth: Int,
        itemCap: Int
    ) -> StorageCandidate? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
            .totalFileAllocatedSizeKey,
            .totalFileSizeKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys), values.isDirectory == true else { return nil }
        let quick = values.totalFileAllocatedSize.map(UInt64.init) ?? values.totalFileSize.map(UInt64.init)
        let bytes = quick ?? directorySizeBounded(path: path, maxDepth: maxDepth, itemCap: itemCap)
        guard bytes >= minCandidateBytes else { return nil }
        let idle = daysIdle(modified: values.contentModificationDate, accessed: values.contentAccessDate)
        let resolved = categorize(path: path, fallback: category)
        let regenerable = [.trash, .cache, .log, .buildArtifact].contains(resolved) || isKnownSafeName(path)
        let huge = bytes >= 800_000_000
        if !regenerable, !huge, let idle, idle < idleThreshold(for: resolved) {
            return nil
        }
        guard regenerable || huge || bytes >= 500_000_000 || (idle ?? 0) >= idleThreshold(for: resolved) else {
            return nil
        }
        var cand = StorageCandidate(
            path: redactHome(path, home: home),
            bytes: bytes,
            category: resolved,
            reason: reasonText(category: resolved, idle: idle, bytes: bytes),
            daysIdle: idle
        )
        cand.priority = score(cand)
        return cand
    }

    private func directorySizeBounded(path: String, maxDepth: Int, itemCap: Int) -> UInt64 {
        guard maxDepth >= 0 else { return 0 }
        let fm = FileManager.default
        // Prefer metadata; enumerator walks are what hang under TCC.
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .totalFileSizeKey]) {
            if let n = values.totalFileAllocatedSize { return UInt64(n) }
            if let n = values.totalFileSize { return UInt64(n) }
        }
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var total: UInt64 = 0
        var count = 0
        let localDeadline = Date().addingTimeInterval(0.2)
        while let item = enumerator.nextObject() as? String {
            count += 1
            if count > itemCap || Date() > localDeadline { break }
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            let full = (path as NSString).appendingPathComponent(item)
            if let size = try? fm.attributesOfItem(atPath: full)[.size] as? UInt64 {
                total += size
            }
        }
        return total
    }

    private func timed<T: Sendable>(seconds: TimeInterval, fallback: T, work: @escaping @Sendable () -> T) -> T {
        let box = TimeoutBox(fallback)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.value = work()
            group.leave()
        }
        _ = group.wait(timeout: .now() + seconds)
        return box.value
    }

    // MARK: - Scoring / classify

    private func score(_ c: StorageCandidate) -> Double {
        var s = c.category.baseWeight
        if let idle = c.daysIdle { s += min(45.0, Double(idle) / 8.0) }
        let mb = Double(c.bytes) / 1_000_000
        s += min(35.0, log10(max(mb, 1)) * 12)
        if isKnownSafeName(c.path) { s += 12 }
        return s
    }

    private func idleThreshold(for category: StorageCandidate.Category) -> Int {
        switch category {
        case .download: return 30
        case .media: return 120
        case .other: return 90
        case .appData: return 60
        default: return 0
        }
    }

    private func reasonText(category: StorageCandidate.Category, idle: Int?, bytes: UInt64) -> String {
        let size = Formatters.bytes(bytes)
        if let idle {
            if idle >= 365 { return "\(category.title) · ~\(size) · idle \(idle / 30) mo" }
            return "\(category.title) · ~\(size) · idle \(idle)d"
        }
        return "\(category.title) · ~\(size)"
    }

    private func categorize(path: String, fallback: StorageCandidate.Category) -> StorageCandidate.Category {
        let lower = path.lowercased()
        if lower.contains("/.trash") { return .trash }
        if lower.contains("/caches") || lower.contains("/cache/") || lower.hasSuffix("/cache") { return .cache }
        if lower.contains("/logs") || lower.hasSuffix(".log") { return .log }
        if lower.contains("deriveddata") || lower.contains("coresimulator") || lower.contains("/archives") {
            return .buildArtifact
        }
        if lower.contains("/downloads") || lower.hasSuffix(".dmg") || lower.hasSuffix(".pkg") || lower.hasSuffix(".zip") {
            return .download
        }
        if lower.contains("/movies") || lower.contains("/music") || lower.contains("/pictures") { return .media }
        if lower.contains("/application support") { return .appData }
        return fallback
    }

    private func isKnownSafeName(_ path: String) -> Bool {
        let lower = path.lowercased()
        let needles = ["deriveddata", "caches", "cache", "logs", ".trash", "coresimulator/caches", "gpuCache", "code cache"]
        return needles.contains { lower.contains($0.lowercased()) }
    }

    private func shouldSkipName(_ name: String) -> Bool {
        if name.hasPrefix(".") && name != ".Trash" { return true }
        let skip = ["CloudStorage", "Mobile Documents", "Containers", "Group Containers", "Mail", "Messages", "Keychains", "Photos Library.photoslibrary"]
        return skip.contains(name)
    }

    private func heavyNameRank(_ name: String) -> Int {
        let lower = name.lowercased()
        let weights = [
            "steam": 100, "adobe": 95, "bluestacks": 95, "google": 80, "caches": 90,
            "deriveddata": 90, "docker": 85, "android": 80, "discord": 70, "chrome": 70
        ]
        return weights.first { lower.contains($0.key) }?.value ?? 0
    }

    private func daysIdle(modified: Date?, accessed: Date?) -> Int? {
        let dates = [accessed, modified].compactMap { $0 }
        guard let newest = dates.max() else { return nil }
        return max(0, Int(Date().timeIntervalSince(newest) / 86_400))
    }

    private func redactHome(_ path: String, home: String) -> String {
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, [EPERM, EACCES].contains(Int32(ns.code)) { return true }
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError { return true }
        let text = ns.localizedDescription.lowercased()
        return text.contains("permission") || text.contains("not permitted") || text.contains("denied")
    }
}

private final class TimeoutBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
    init(_ value: T) { _value = value }
}
