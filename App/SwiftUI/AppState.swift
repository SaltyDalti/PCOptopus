import Foundation
import Combine
import Model
import Store
import Sensors
import Policy
import Apply
import Coach

@MainActor
public final class AppState: ObservableObject {
    @Published public var identity: MachineIdentity = .thisMacSeed
    @Published public var bundle: SampleBundle = SampleBundle()
    @Published public var findings: [Finding] = []
    @Published public var contract: Contract = .emptyDefault()
    @Published public var settings: AppSettings = AppSettings()
    @Published public var journal: [JournalEntry] = []
    @Published public var practices: [Practice] = Practice.catalog
    @Published public var autopilotStatus: AutopilotStatus = .off
    @Published public var activeProfile: WorkProfile = .battery
    @Published public var todayParagraph: String = "Measuring this Mac…"
    @Published public var largeFolders: [LargeFolderEntry] = []
    @Published public var selectedDomain: Domain = .storage
    @Published public var selectedFindingID: String?
    @Published public var askQuestion: String = ""
    @Published public var askAnswer: CoachAnswer?
    @Published public var onboardingStep: Int = 0
    @Published public var isScanningFolders = false
    @Published public var lastError: String?
    @Published public var cpuFraction: Double = 0

    public let store: SQLiteStore
    public let ring = RingBuffer()
    public let policy = PolicyEngine()
    public let coach: any Coaching
    public let applier: any ActionApplying
    public var journalCoordinator: JournalCoordinator

    private let fastSensors: FastSensors
    private let slowSensors: SlowSensors
    private var fastTask: Task<Void, Never>?
    private var mediumTask: Task<Void, Never>?
    private var slowTask: Task<Void, Never>?
    private var networkPrevBytes: UInt64 = 0
    private var networkPrevTime: Date?

    public init(
        store: SQLiteStore? = nil,
        applier: (any ActionApplying)? = nil,
        coach: (any Coaching)? = nil,
        startLoops: Bool = true
    ) {
        let resolvedStore: SQLiteStore
        var loadError: String?
        if let store {
            resolvedStore = store
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("PCOptopus", isDirectory: true)
            do {
                resolvedStore = try SQLiteStore(directory: dir)
            } catch {
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("PCOptopusPreview-\(UUID().uuidString)")
                resolvedStore = try! SQLiteStore(directory: temp)
                loadError = error.localizedDescription
            }
        }
        self.store = resolvedStore
        self.applier = applier ?? SystemApplier()
        self.coach = coach ?? FoundationModelsCoach()
        self.journalCoordinator = JournalCoordinator(store: resolvedStore, applier: self.applier)
        self.fastSensors = FastSensors()
        self.slowSensors = SlowSensors()
        if let loadError { self.lastError = loadError }
        if let contract = try? resolvedStore.loadContract() { self.contract = contract }
        if let settings = try? resolvedStore.loadSettings() { self.settings = settings }
        if let practices = try? resolvedStore.loadPractices() { self.practices = practices }
        if let journal = try? resolvedStore.journalEntries() { self.journal = journal }
        if !settings.hasCompletedOnboarding {
            onboardingStep = 1
        }
        if startLoops {
            start()
        }
    }

    public func start() {
        refreshSlow()
        refreshMedium()
        refreshFast()
        fastTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { self?.refreshFast() }
            }
        }
        mediumTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await MainActor.run { self?.refreshMedium() }
            }
        }
        slowTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                await MainActor.run { self?.refreshSlow() }
            }
        }
    }

    public func stop() {
        fastTask?.cancel()
        mediumTask?.cancel()
        slowTask?.cancel()
    }

    public func refreshFast() {
        let snap = fastSensors.read(includePmset: false, includeAssertions: false)
        cpuFraction = snap.cpuUsedFraction
        // Merge thermal/power into current energy sample lightly
        if var energy = bundle.sample(for: .energy) {
            energy.set(.energyThermalState, snap.thermalState.rawValue)
            energy.set(.energyPowerSource, snap.powerSource.rawValue)
            energy.set(.energyLowPowerMode, snap.lowPowerMode)
            var samples = bundle.samples.filter { $0.domain != .energy }
            samples.append(energy)
            bundle = SampleBundle(timestamp: Date(), samples: samples)
        }
        var compute = Sample(domain: .compute)
        compute.set(.cpuUsedFraction, snap.cpuUsedFraction)
        ring.append(SampleBundle(samples: [compute]))
    }

    public func refreshMedium() {
        let snap = fastSensors.read(includePmset: true, includeAssertions: true)
        let fastBundle = fastSensors.sampleBundle(from: snap)
        merge(fastBundle)
        runPolicyTick()
    }

    public func refreshSlow() {
        let snap = slowSensors.read()
        identity = snap.identity
        let slowBundle = slowSensors.sampleBundle(from: snap)
        merge(slowBundle)
        runPolicyTick()
    }

    private func merge(_ incoming: SampleBundle) {
        var byDomain: [Domain: Sample] = [:]
        for s in bundle.samples { byDomain[s.domain] = s }
        for s in incoming.samples { byDomain[s.domain] = s }
        bundle = SampleBundle(timestamp: Date(), samples: Array(byDomain.values))
        try? store.insertSample(contentsOf: bundle.samples)
    }

    public func runPolicyTick() {
        let result = policy.evaluate(bundle: bundle, contract: contract, settings: settings)
        findings = result.findings
        autopilotStatus = result.autopilotStatus
        activeProfile = result.activeProfile
        practices = policy.practices(from: findings, bundle: bundle)
        todayParagraph = coach.todayParagraph(
            findings: findings,
            bundle: bundle,
            status: autopilotStatus
        )
        for finding in findings {
            try? store.upsertFinding(finding)
        }
        try? store.savePractices(practices)

        guard autopilotStatus == .on else { return }
        for decision in result.decisions {
            do {
                let entry = try journalCoordinator.apply(
                    decision: decision,
                    actor: .autopilot,
                    killSwitch: settings.killSwitch
                )
                journal.insert(entry, at: 0)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    public func saveContract() {
        try? store.saveContract(contract)
        runPolicyTick()
    }

    public func saveSettings() {
        try? store.saveSettings(settings)
        runPolicyTick()
    }

    public func applyConfirm(actionID: String, parameters: [String: String], before: String, after: String) {
        let decision = PolicyDecision(
            actionID: actionID,
            beforeValue: before,
            afterValue: after,
            parameters: parameters,
            reason: "Applied once by you"
        )
        do {
            let entry = try journalCoordinator.apply(
                decision: decision,
                actor: .you,
                killSwitch: settings.killSwitch
            )
            journal.insert(entry, at: 0)
            refreshSlow()
            refreshMedium()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func undo(entry: JournalEntry) {
        do {
            let updated = try journalCoordinator.undo(entryID: entry.id, killSwitch: settings.killSwitch)
            if let idx = journal.firstIndex(where: { $0.id == entry.id }) {
                journal[idx] = updated
            }
            refreshMedium()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func scanLargeFolders() {
        isScanningFolders = true
        Task.detached { [slowSensors] in
            let entries = slowSensors.scanLargeFolders()
            await MainActor.run {
                self.largeFolders = entries
                self.isScanningFolders = false
            }
        }
    }

    public func submitAsk() {
        askAnswer = coach.answer(question: askQuestion, findings: findings, bundle: bundle)
    }

    public func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        onboardingStep = 0
        saveSettings()
    }

    public func leadFindings() -> [Finding] {
        findings
            .filter { $0.severity >= .attention }
            .sorted { $0.severity > $1.severity }
    }

    public func finding(id: String) -> Finding? {
        findings.first { $0.id == id }
    }

    public func exportDiagnostic() -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("pcoctopus-diagnostic-\(Int(Date().timeIntervalSince1970)).json")
        let payload: [String: Any] = [
            "identity": [
                "name": identity.name,
                "model": identity.modelIdentifier,
                "chip": identity.chip,
                "memoryBytes": identity.memoryBytes,
                "os": identity.osVersion
            ],
            "findings": findings.map { ["id": $0.id, "severity": $0.severity.rawValue, "title": $0.title] },
            "metrics": bundle.mergedMetrics(),
            "contractEnabled": contract.enabledCount,
            "autopilot": autopilotStatus.rawValue
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else {
            return nil
        }
        try? data.write(to: url)
        return url
    }
}

private extension SQLiteStore {
    func insertSample(contentsOf samples: [Sample]) throws {
        for sample in samples {
            try insertSample(sample)
        }
    }
}
