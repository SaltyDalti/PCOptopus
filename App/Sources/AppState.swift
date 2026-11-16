import AppKit
import Foundation
import Combine
import Model
import Store
import Sensors
import Policy
import Apply
import Coach

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
    @Published public var todayParagraph: String = "Starting up — measuring this Mac in the background…"
    @Published public var pulse: PulseScore = .measuring
    @Published public var largeFolders: [LargeFolderEntry] = []
    @Published public var storageScan = StorageScanResult()
    @Published public var didRunStorageScan = false
    @Published public var selectedDomain: Domain = .storage
    @Published public var selectedFindingID: String?
    @Published public var askQuestion: String = ""
    @Published public var askAnswer: CoachAnswer?
    @Published public var onboardingStep: Int = 0
    @Published public var isScanningFolders = false
    /// True when macOS TCC blocked Files & Folders reads during a scan.
    @Published public var needsFilesAccess = false
    @Published public var lastError: String?
    @Published public var cpuFraction: Double = 0

    /// Short live status for the status strip ("Reading power settings…").
    @Published public var statusMessage: String = "Starting…"
    /// True while a user-visible action or baseline is in flight.
    @Published public var isBusy = false
    /// Toast / banner after an action ("Done — AC sleep set to 30 minutes.").
    @Published public var flashMessage: String?
    /// Baseline progress 0…1 during first read.
    @Published public var baselineProgress: Double = 0
    @Published public var baselineComplete = false
    /// Bumped only when the UI should redraw — not on every 2s CPU sample.
    @Published public var uiGeneration: UInt64 = 0

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
    private var flashClearTask: Task<Void, Never>?
    private let sensorQueue = DispatchQueue(label: "com.pcoptopus.sensors", qos: .utility)
    /// Storage scans must not sit behind slow sensor work or they feel like a dead button.
    private let scanQueue = DispatchQueue(label: "com.pcoptopus.storage-scan", qos: .userInitiated)
    private var mediumInFlight = false
    private var slowInFlight = false
    private var scanGeneration: UInt64 = 0
    private var lastAutoFightAt: Date?
    private var fightGeneration: UInt64 = 0

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
        } else {
            baselineComplete = true
        }
        if startLoops {
            start()
        }
    }

    public func start() {
        statusMessage = "Measuring this Mac…"
        isBusy = true
        // Fast path first so the window paints with something useful.
        refreshFastAsync()
        runBaselineThenLoops()
    }

    public func stop() {
        fastTask?.cancel()
        mediumTask?.cancel()
        slowTask?.cancel()
        flashClearTask?.cancel()
    }

    /// One-tap first-run: finish onboarding and fight for Pulse 100.
    public func acceptAndStart() {
        settings.autopilotMasterEnabled = true
        saveSettings()
        flash("Goal: Pulse 100. PCOptopus will fix what it can and keep fighting to hold it.")
        completeOnboarding()
        if !baselineComplete {
            statusMessage = "Still finishing the first read…"
            isBusy = true
        } else {
            statusMessage = "Fighting for Pulse 100"
            isBusy = false
            fightForPulse100(userInitiated: false)
        }
        bumpUI()
    }

    private func runBaselineThenLoops() {
        sensorQueue.async { [weak self] in
            guard let self else { return }
            self.publishStatus("Reading power and memory…", progress: 0.15, busy: true)
            let medium = self.fastSensors.read(includePmset: true, includeAssertions: true)
            let mediumBundle = self.fastSensors.sampleBundle(from: medium)

            self.publishStatus("Reading storage and helpers…", progress: 0.55, busy: true)
            let slow = self.slowSensors.read()
            let slowBundle = self.slowSensors.sampleBundle(from: slow)

            DispatchQueue.main.async {
                self.identity = slow.identity
                self.merge(mediumBundle)
                self.merge(slowBundle)
                self.runPolicyTick()
                self.baselineProgress = 1
                self.baselineComplete = true
                self.isBusy = false
                if self.pulse.percent >= 100 {
                    self.statusMessage = "Pulse 100 · holding"
                } else {
                    self.statusMessage = "Pulse \(self.pulse.percent) · fighting for +\(self.pulse.deficit)"
                    if let lead = self.leadFindings().first {
                        self.flash("Pulse \(self.pulse.percent) — fighting \(lead.title) toward 100")
                    }
                }
                // Advance past the "waiting" onboarding beat automatically.
                if !self.settings.hasCompletedOnboarding, self.onboardingStep == 1 {
                    self.onboardingStep = 2
                }
                self.bumpUI()
                self.startPeriodicLoops()
                self.scheduleAutoFightIfNeeded()
            }
        }
    }

    private func startPeriodicLoops() {
        fastTask?.cancel()
        mediumTask?.cancel()
        slowTask?.cancel()
        fastTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.refreshFastAsync()
            }
        }
        mediumTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                self?.refreshMediumAsync()
            }
        }
        slowTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                self?.refreshSlowAsync()
            }
        }
    }

    private func publishStatus(_ message: String, progress: Double, busy: Bool) {
        DispatchQueue.main.async {
            self.statusMessage = message
            self.baselineProgress = progress
            self.isBusy = busy
            self.bumpUI()
        }
    }

    public func flash(_ message: String, seconds: Double = 4.5) {
        flashMessage = message
        bumpUI()
        flashClearTask?.cancel()
        let nanos = UInt64(max(1.0, seconds) * 1_000_000_000)
        flashClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard let self else { return }
            await MainActor.run {
                if self.flashMessage == message {
                    self.flashMessage = nil
                    self.bumpUI()
                }
            }
        }
    }

    public func bumpUI() {
        uiGeneration &+= 1
    }

    public func refreshFastAsync() {
        sensorQueue.async { [weak self] in
            guard let self else { return }
            let snap = self.fastSensors.read(includePmset: false, includeAssertions: false)
            DispatchQueue.main.async {
                // Keep CPU in memory for the menu bar — do not publish UI reloads every 2s.
                self.cpuFraction = snap.cpuUsedFraction
                var compute = Sample(domain: .compute)
                compute.set(.cpuUsedFraction, snap.cpuUsedFraction)
                self.ring.append(SampleBundle(samples: [compute]))
            }
        }
    }

    public func refreshMediumAsync() {
        guard !mediumInFlight else { return }
        mediumInFlight = true
        sensorQueue.async { [weak self] in
            guard let self else { return }
            let snap = self.fastSensors.read(includePmset: true, includeAssertions: true)
            let fastBundle = self.fastSensors.sampleBundle(from: snap)
            DispatchQueue.main.async {
                self.merge(fastBundle)
                self.runPolicyTick()
                self.mediumInFlight = false
                if self.baselineComplete, !self.isBusy, !self.isScanningFolders {
                    // Don't clobber a fresh Scan complete / action status on the medium tick.
                    if self.statusMessage.hasPrefix("Watching")
                        || self.statusMessage.hasPrefix("Steady")
                        || self.statusMessage.hasPrefix("Pulse ")
                        || self.statusMessage.hasPrefix("Found ")
                        || self.statusMessage.hasPrefix("Measuring")
                        || self.statusMessage.hasPrefix("Reading")
                        || self.statusMessage.hasPrefix("Still finishing")
                        || self.statusMessage.hasPrefix("Fighting")
                        || self.statusMessage.hasPrefix("Granted") {
                        if self.pulse.deficit == 0 {
                            self.statusMessage = "Pulse 100 · holding"
                        } else {
                            self.statusMessage = "Pulse \(self.pulse.percent) · fighting for +\(self.pulse.deficit)"
                        }
                    }
                }
                self.bumpUI()
                self.scheduleAutoFightIfNeeded()
            }
        }
    }

    public func refreshSlowAsync() {
        guard !slowInFlight else { return }
        slowInFlight = true
        sensorQueue.async { [weak self] in
            guard let self else { return }
            let snap = self.slowSensors.read()
            let slowBundle = self.slowSensors.sampleBundle(from: snap)
            DispatchQueue.main.async {
                self.identity = snap.identity
                self.merge(slowBundle)
                self.runPolicyTick()
                self.slowInFlight = false
                self.bumpUI()
            }
        }
    }

    /// Kept for call sites that still say refresh*; always async.
    public func refreshFast() { refreshFastAsync() }
    public func refreshMedium() { refreshMediumAsync() }
    public func refreshSlow() { refreshSlowAsync() }

    private func merge(_ incoming: SampleBundle) {
        var byDomain: [Domain: Sample] = [:]
        for s in bundle.samples { byDomain[s.domain] = s }
        for s in incoming.samples { byDomain[s.domain] = s }
        bundle = SampleBundle(timestamp: Date(), samples: Array(byDomain.values))
        try? store.insertSample(contentsOf: bundle.samples)
    }

    public func runPolicyTick() {
        let previousPulse = pulse.percent
        let result = policy.evaluate(bundle: bundle, contract: contract, settings: settings)
        findings = result.findings
        autopilotStatus = result.autopilotStatus
        activeProfile = result.activeProfile
        practices = policy.practices(from: findings, bundle: bundle)
        pulse = PulseScore.compute(findings: findings, bundle: bundle)
        todayParagraph = coach.todayParagraph(
            findings: findings,
            bundle: bundle,
            status: autopilotStatus,
            pulse: pulse
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
                // Re-score after the change so the flash shows the climb.
                let refreshed = policy.evaluate(bundle: bundle, contract: contract, settings: settings)
                findings = refreshed.findings
                pulse = PulseScore.compute(findings: findings, bundle: bundle)
                let delta = pulse.percent - previousPulse
                if delta > 0 {
                    flash("Autopilot: Pulse \(previousPulse) → \(pulse.percent) (+\(delta)) · \(entry.title)")
                } else {
                    flash("Autopilot fighting: \(entry.title) → \(entry.afterValue)")
                }
            } catch {
                lastError = error.localizedDescription
                flash("Autopilot paused: \(error.localizedDescription)")
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

    /// Legacy entry — Today now fights the whole Pulse deficit, not one finding.
    public func fixLeadFinding() {
        fightForPulse100(userInitiated: true)
    }

    /// Single goal: get Pulse to 100 using every safe fix available right now.
    public func fightForPulse100(userInitiated: Bool) {
        guard settings.hasCompletedOnboarding || userInitiated else { return }
        guard !settings.killSwitch else {
            if userInitiated {
                flash("Kill switch is on — turn it off in Settings to fight for Pulse 100")
                bumpUI()
            }
            return
        }
        guard pulse.percent < 100 else {
            if userInitiated {
                flash("Pulse already at 100 — holding")
            }
            return
        }
        if !userInitiated {
            if isBusy || isScanningFolders { return }
            if let last = lastAutoFightAt, Date().timeIntervalSince(last) < 45 { return }
        }
        lastAutoFightAt = Date()
        fightGeneration &+= 1
        let generation = fightGeneration

        settings.autopilotMasterEnabled = true
        let leads = leadFindings()
        var willScan = false
        var confirmQueue: [(String, ActionDefinition)] = []

        for finding in leads {
            for actionID in finding.actionIDs {
                guard let def = ActionCatalog.definition(id: actionID) else { continue }
                switch def.risk {
                case .autopilot:
                    contract.setEnabled(actionID, enabled: true)
                    if let defaults = def.defaultBounds {
                        var bounds = contract.grant(for: actionID)?.bounds ?? defaults
                        if bounds.target == nil { bounds.target = defaults.target }
                        if bounds.min == nil { bounds.min = defaults.min }
                        if bounds.max == nil { bounds.max = defaults.max }
                        contract.setBounds(actionID, bounds: bounds)
                    }
                    if actionID == "background.agent.disable" {
                        var bounds = contract.grant(for: actionID)?.bounds ?? ActionBounds()
                        bounds.agentLabel = bounds.agentLabel
                            ?? inferAgentLabel(from: finding)
                            ?? "com.BlueStacks.AppPlayer.Service"
                        contract.setBounds(actionID, bounds: bounds)
                    }
                case .confirm:
                    confirmQueue.append((actionID, def))
                case .manual:
                    if actionID == "storage.scan.largeFolders" {
                        willScan = true
                    }
                }
            }
        }

        // Metric-only storage drag (no finding action) still gets a scan plan.
        if !willScan,
           pulse.drags.contains(where: { $0.id.hasPrefix("storage") || $0.id.hasPrefix("metric.storage") }) {
            willScan = true
        }

        try? store.saveContract(contract)
        try? store.saveSettings(settings)

        isBusy = true
        statusMessage = "Fighting for Pulse 100…"
        if userInitiated {
            flash("Fighting for Pulse 100 — applying every safe fix", seconds: 8)
        }
        bumpUI()

        // Immediate confirm-tier applies (brew PATH, sleep, etc.).
        if let first = confirmQueue.first {
            applyFightConfirm(actionID: first.0, remaining: Array(confirmQueue.dropFirst()), generation: generation, willScan: willScan)
        } else if willScan {
            isBusy = false
            scanLargeFolders()
            runPolicyTick()
        } else {
            runPolicyTick()
            isBusy = false
            statusMessage = pulse.percent >= 100
                ? "Pulse 100 · holding"
                : "Pulse \(pulse.percent) · fighting for +\(pulse.deficit)"
            if userInitiated, pulse.percent < 100 {
                flash("Granted what I can. Remaining +\(pulse.deficit) needs your help (often storage cleanup).", seconds: 10)
            }
            bumpUI()
        }
    }

    private func scheduleAutoFightIfNeeded() {
        guard baselineComplete, settings.hasCompletedOnboarding else { return }
        guard pulse.percent < 100, !settings.killSwitch else { return }
        fightForPulse100(userInitiated: false)
    }

    private func inferAgentLabel(from finding: Finding) -> String? {
        for line in finding.evidence {
            if line.contains("com."), let token = line.split(whereSeparator: { $0 == " " || $0 == "," }).first(where: { $0.hasPrefix("com.") }) {
                return String(token)
            }
        }
        let labels = (bundle.string(.backgroundAgentLabels) ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return labels.first { $0.localizedCaseInsensitiveContains("BlueStacks") }
            ?? labels.first
    }

    private func applyFightConfirm(
        actionID: String,
        remaining: [(String, ActionDefinition)],
        generation: UInt64,
        willScan: Bool
    ) {
        guard generation == fightGeneration else { return }
        if actionID == "software.brew.path.native" {
            applyConfirmAsync(
                actionID: actionID,
                parameters: [:],
                before: "PATH without native first",
                after: "/opt/homebrew/bin first",
                successFlash: "PATH fixed toward Pulse 100"
            ) { [weak self] in
                self?.continueFight(remaining: remaining, generation: generation, willScan: willScan)
            }
        } else if actionID.hasPrefix("energy.") {
            let before = bundle.int(.energyACSleepMinutes).map(String.init) ?? "?"
            let target = Int(contract.grant(for: "energy.ac.sleep.set")?.bounds.target
                ?? ActionCatalog.definition(id: "energy.ac.sleep.set")?.defaultBounds?.target
                ?? 30)
            applyConfirmAsync(
                actionID: "energy.ac.sleep.set",
                parameters: ["key": "sleep", "powerSource": "AC", "value": String(target)],
                before: before,
                after: String(target),
                successFlash: "AC sleep set — reclaiming Pulse"
            ) { [weak self] in
                self?.continueFight(remaining: remaining, generation: generation, willScan: willScan)
            }
        } else {
            continueFight(remaining: remaining, generation: generation, willScan: willScan)
        }
    }

    private func continueFight(
        remaining: [(String, ActionDefinition)],
        generation: UInt64,
        willScan: Bool
    ) {
        guard generation == fightGeneration else { return }
        if let next = remaining.first {
            applyFightConfirm(actionID: next.0, remaining: Array(remaining.dropFirst()), generation: generation, willScan: willScan)
            return
        }
        if willScan {
            scanLargeFolders()
        } else {
            runPolicyTick()
            isBusy = false
            statusMessage = pulse.percent >= 100
                ? "Pulse 100 · holding"
                : "Pulse \(pulse.percent) · fighting for +\(pulse.deficit)"
            bumpUI()
        }
    }

    private func applySleepNow() {
        let before = bundle.int(.energyACSleepMinutes).map(String.init) ?? "?"
        let target = Int(contract.grant(for: "energy.ac.sleep.set")?.bounds.target ?? 30)
        applyConfirmAsync(
            actionID: "energy.ac.sleep.set",
            parameters: ["key": "sleep", "powerSource": "AC", "value": String(target)],
            before: before,
            after: String(target),
            successFlash: "Done — AC sleep set to \(Formatters.minutes(target)). Undo anytime in Journal."
        )
    }

    public func applyConfirm(
        actionID: String,
        parameters: [String: String],
        before: String,
        after: String
    ) {
        applyConfirmAsync(
            actionID: actionID,
            parameters: parameters,
            before: before,
            after: after,
            successFlash: "Done — \(ActionCatalog.definition(id: actionID)?.title ?? actionID)"
        )
    }

    private func applyConfirmAsync(
        actionID: String,
        parameters: [String: String],
        before: String,
        after: String,
        successFlash: String,
        onFinished: (() -> Void)? = nil
    ) {
        isBusy = true
        statusMessage = "Applying change… (macOS may ask for your password)"
        flash("Applying… if a password dialog appears, that’s expected")
        let decision = PolicyDecision(
            actionID: actionID,
            beforeValue: before,
            afterValue: after,
            parameters: parameters,
            reason: "Fighting for Pulse 100"
        )
        sensorQueue.async { [weak self] in
            guard let self else { return }
            do {
                let entry = try self.journalCoordinator.apply(
                    decision: decision,
                    actor: .you,
                    killSwitch: self.settings.killSwitch
                )
                DispatchQueue.main.async {
                    let beforePulse = self.pulse.percent
                    self.journal.insert(entry, at: 0)
                    self.isBusy = false
                    self.runPolicyTick()
                    let afterPulse = self.pulse.percent
                    let climb = afterPulse - beforePulse
                    self.statusMessage = climb > 0
                        ? "Pulse \(beforePulse) → \(afterPulse)"
                        : "Change applied · Pulse \(afterPulse)"
                    if climb > 0 {
                        self.flash("Pulse \(beforePulse) → \(afterPulse) (+\(climb)). \(successFlash)")
                    } else {
                        self.flash(successFlash)
                    }
                    self.bumpUI()
                    // Re-read slowly so findings reflect shell PATH / pmset after the change.
                    self.refreshSlowAsync()
                    self.refreshMediumAsync()
                    onFinished?()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.lastError = error.localizedDescription
                    self.statusMessage = "Couldn’t apply change"
                    self.flash("Couldn’t apply: \(error.localizedDescription)")
                    self.bumpUI()
                    onFinished?()
                }
            }
        }
    }

    public func undo(entry: JournalEntry) {
        isBusy = true
        statusMessage = "Undoing…"
        sensorQueue.async { [weak self] in
            guard let self else { return }
            do {
                let updated = try self.journalCoordinator.undo(
                    entryID: entry.id,
                    killSwitch: self.settings.killSwitch
                )
                DispatchQueue.main.async {
                    if let idx = self.journal.firstIndex(where: { $0.id == entry.id }) {
                        self.journal[idx] = updated
                    }
                    self.isBusy = false
                    self.statusMessage = "Undone"
                    self.flash("Undone — restored \(entry.beforeValue)")
                    self.refreshMediumAsync()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.lastError = error.localizedDescription
                    self.flash("Undo failed: \(error.localizedDescription)")
                }
            }
        }
    }

    public func scanLargeFolders() {
        scanGeneration &+= 1
        let generation = scanGeneration
        isScanningFolders = true
        isBusy = true
        statusMessage = "Scanning for old & unused files…"
        // Seed an empty-but-visible plan so the Today panel appears immediately.
        storageScan = StorageScanResult(
            candidates: [],
            accessDenied: false,
            targetFreeBytes: StorageScanner.targetFreeBytes,
            availableBytes: UInt64(bundle.double(.storageAvailableBytes) ?? 0),
            bytesNeeded: 0,
            recommendedBytes: 0
        )
        flash("Scanning caches & leftovers — nothing will be deleted", seconds: 8)
        bumpUI()

        let available = UInt64(bundle.double(.storageAvailableBytes) ?? 0)
        scanQueue.async { [weak self] in
            guard let self else { return }
            let result = self.slowSensors.scanLargeFoldersDetailed(availableBytes: available)
            DispatchQueue.main.async {
                guard generation == self.scanGeneration else { return }
                self.finishStorageScan(result)
            }
        }

        // Hard ceiling — UI must never stay on Scanning forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, generation == self.scanGeneration, self.isScanningFolders else { return }
            self.didRunStorageScan = true
            self.isScanningFolders = false
            self.isBusy = false
            if self.storageScan.candidates.isEmpty {
                self.statusMessage = "Scan timed out — try Full Disk Access, then Show me again"
                self.flash("Scan stalled. Enable Full Disk Access for /Applications/PCOptopus.app, quit, reopen, retry.", seconds: 12)
                self.needsFilesAccess = true
            } else {
                self.statusMessage = "Storage plan ready (partial)"
                self.flash("Showing what we found so far. Full Disk Access helps find more.", seconds: 10)
            }
            self.bumpUI()
        }
    }

    private func finishStorageScan(_ result: SlowSensors.FolderScanResult) {
        storageScan = result.storage
        largeFolders = result.entries
        didRunStorageScan = true
        needsFilesAccess = result.accessDenied || !isRunningFromApplications
        isScanningFolders = false
        isBusy = false
        if !result.storage.candidates.isEmpty {
            let rec = result.storage.recommended.count
            let reclaim = Formatters.bytes(result.storage.recommendedBytes)
            statusMessage = "Storage plan ready — \(rec) recommended (\(reclaim))"
            if result.storage.bytesNeeded > 0 {
                flash("Need \(Formatters.bytes(result.storage.bytesNeeded)) more free. Recommended reclaim \(reclaim).", seconds: 10)
            } else if let top = result.storage.recommended.first {
                flash("Under target. Optional cleanup: \(Formatters.bytes(top.bytes)) · \(top.path)", seconds: 8)
            } else {
                flash("Scan finished — \(result.storage.candidates.count) items listed.", seconds: 8)
            }
            if result.accessDenied {
                // Keep results primary; FDA is a hint, not a failure.
                statusMessage = "Storage plan ready — some folders still blocked"
            }
        } else if result.accessDenied {
            statusMessage = "macOS blocked folder reads"
            flash("Enable Full Disk Access, quit, reopen /Applications/PCOptopus.app, then Show me again", seconds: 12)
        } else {
            statusMessage = "Scan finished — nothing obvious to reclaim"
            flash("Scan finished. Nothing obvious to reclaim. If that seems wrong, enable Full Disk Access.", seconds: 10)
        }
        bumpUI()
    }
    /// Full Disk Access is what actually sticks for Library/Caches/etc. Files & Folders alone is not enough.
    public func openFilesAndFoldersSettings() {
        openFullDiskAccessSettings()
    }

    public func openFullDiskAccessSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                flash("Enable PCOptopus under Full Disk Access, then quit and reopen the /Applications copy")
                return
            }
        }
        flash("System Settings → Privacy & Security → Full Disk Access → enable PCOptopus")
    }

    public var isRunningFromApplications: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    public var accessHelpText: String {
        if needsFilesAccess {
            if isRunningFromApplications {
                return "macOS is still blocking some folders. Turn on Full Disk Access for /Applications/PCOptopus.app, then quit and reopen that copy. Rebuilds keep this grant (stable local signing)."
            }
            return "Open /Applications/PCOptopus.app (not this rebuild path) and enable Full Disk Access once — it sticks across package-app rebuilds."
        }
        if isRunningFromApplications {
            return "Full Disk Access lets scans read Library, Caches, and Downloads. PCOptopus never deletes without you. Grants stick across rebuilds."
        }
        return "Always use /Applications/PCOptopus.app. Full Disk Access is tied to the local signing cert, so rebuilds won’t reset it."
    }

    public func submitAsk() {
        statusMessage = "Thinking…"
        askAnswer = coach.answer(question: askQuestion, findings: findings, bundle: bundle, pulse: pulse)
        statusMessage = "Answer ready"
        flash("Answer ready below")
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
        flash("Diagnostic exported")
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
