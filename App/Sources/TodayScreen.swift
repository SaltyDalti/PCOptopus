import AppKit
import Model

/// Fixed layout — never rebuilds the tree. Updates labels in place.
final class TodayScreen: NSView {
    var onLeadAction: (() -> Void)?
    var onUndo: (() -> Void)?
    var onOpenPermissions: (() -> Void)?

    private let page = PageShell()
    private let brand = label("PCOptopus", font: Theme.title(26))
    private let subtitle = label("Your Mac, kept in good shape", font: Theme.body(), color: Theme.secondaryLabel)
    private let pill = Pill()
    private let pulseMeter = PulseMeter()

    private let heroEyebrow = label("NEEDS ATTENTION", font: Theme.captionMedium(), color: Theme.tertiaryLabel)
    private let heroTitle = label("", font: Theme.title(20))
    private let heroBody = label("", font: Theme.body(), color: Theme.secondaryLabel)
    private let fixButton = primaryButton("Show me", target: nil, action: nil)
    private let heroPanel = SoftPanel()
    private let clearPanel = SoftPanel()
    private let clearTitle = label("Pulse at 100", font: Theme.headline())
    private let clearBody = label(
        "Nothing dragging health. Autopilot keeps fighting to hold Pulse at 100.",
        font: Theme.body(),
        color: Theme.secondaryLabel
    )

    private let coachLabel = label("", font: Theme.body(), color: Theme.secondaryLabel)

    private let vitalStorage = QuietVital()
    private let vitalMemory = QuietVital()
    private let vitalEnergy = QuietVital()

    private let journalLabel = label("", font: Theme.caption(), color: Theme.tertiaryLabel)
    private let undoButton = linkButton("Undo", target: nil, action: nil)
    private let scanTitle = label("RECOMMENDED DELETIONS", font: Theme.captionMedium(), color: Theme.tertiaryLabel)
    private let scanSummary = label("", font: Theme.body(), color: Theme.secondaryLabel)
    private let scanBody: NSTextField = {
        let field = label("", font: Theme.mono(), color: Theme.secondaryLabel)
        field.maximumNumberOfLines = 16
        field.cell?.lineBreakMode = .byWordWrapping
        return field
    }()
    private let scanFootnote = label(
        "PCOptopus never deletes. Review in Finder, then empty Trash yourself.",
        font: Theme.caption(),
        color: Theme.tertiaryLabel
    )
    private let scanPanel = SoftPanel()
    private let permissionTitle = label("FULL DISK ACCESS", font: Theme.captionMedium(), color: Theme.tertiaryLabel)
    private let permissionBody = label(
        "macOS blocked folder reads. Enable Full Disk Access for /Applications/PCOptopus.app, then quit and reopen that copy.",
        font: Theme.body(),
        color: Theme.secondaryLabel
    )
    private let permissionButton = secondaryButton("Open Full Disk Access", target: nil, action: nil)
    private let permissionPanel = SoftPanel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: leadingAnchor),
            page.trailingAnchor.constraint(equalTo: trailingAnchor),
            page.topAnchor.constraint(equalTo: topAnchor),
            page.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        fixButton.target = self
        fixButton.action = #selector(fixTapped)
        undoButton.target = self
        undoButton.action = #selector(undoTapped)
        permissionButton.target = self
        permissionButton.action = #selector(permissionsTapped)

        let top = hstack([
            vstack([brand, subtitle], spacing: 4),
            flexibleSpacer(),
            pill
        ], spacing: 12, alignment: .top)

        heroPanel.setViews([heroEyebrow, heroTitle, heroBody, fixButton])
        clearPanel.setViews([clearTitle, clearBody])
        clearPanel.isHidden = true
        scanPanel.setViews([scanTitle, scanSummary, scanBody, scanFootnote])
        scanPanel.isHidden = true
        permissionPanel.setViews([permissionTitle, permissionBody, permissionButton])
        permissionPanel.isHidden = true

        let vitals = NSStackView(views: [vitalStorage, vitalMemory, vitalEnergy])
        vitals.orientation = .horizontal
        vitals.distribution = .fillEqually
        vitals.spacing = 28
        vitals.translatesAutoresizingMaskIntoConstraints = false

        let journalRow = hstack([journalLabel, flexibleSpacer(), undoButton], spacing: 8)

        page.install([
            top,
            pulseMeter,
            heroPanel,
            clearPanel,
            scanPanel, // Keep results under the button — don't hide below the fold.
            permissionPanel,
            coachLabel,
            hairline(),
            vitals,
            journalRow
        ])

        coachLabel.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reload(state: AppState) {
        pill.set("Autopilot \(state.autopilotStatus.title)", color: Theme.autopilot(state.autopilotStatus))
        pulseMeter.apply(state.pulse, autopilot: state.autopilotStatus)
        coachLabel.stringValue = state.todayParagraph
        subtitle.stringValue = state.pulse.percent >= 100
            ? "Goal held — Pulse 100"
            : "One goal: Pulse 100"

        if let a = state.bundle.double(.storageAvailableBytes),
           let t = state.bundle.double(.storageContainerBytes) {
            vitalStorage.apply(
                title: "Storage",
                value: Formatters.bytes(UInt64(a)),
                detail: "of \(Formatters.bytes(UInt64(t))) free"
            )
        } else {
            vitalStorage.apply(title: "Storage", value: "…", detail: "Measuring")
        }
        vitalMemory.apply(
            title: "Memory",
            value: state.bundle.string(.memoryPressure) ?? "—",
            detail: "Unified pressure"
        )
        let source = state.bundle.string(.energyPowerSource) ?? "—"
        let sleep = state.bundle.int(.energyACSleepMinutes).map { Formatters.minutes($0) } ?? "—"
        vitalEnergy.apply(title: "Power", value: source, detail: "AC sleep \(sleep)")

        if state.pulse.percent < 100 {
            heroPanel.isHidden = false
            clearPanel.isHidden = true
            let lead = state.leadFindings().first
            let color = Theme.severity(lead?.severity ?? .attention)
            heroEyebrow.stringValue = "GOAL · PULSE 100"
            heroEyebrow.textColor = color
            heroTitle.stringValue = "Need +\(state.pulse.deficit)"
            if let lead {
                let dragPoints = state.pulse.drags.first(where: { $0.id == lead.id })?.points
                let reclaim = dragPoints.map { " About +\($0) from fixing this." } ?? ""
                heroBody.stringValue = "\(lead.title) — \(lead.summary)\(reclaim)"
            } else if let drag = state.pulse.drags.first {
                heroBody.stringValue = "Biggest drag: \(drag.title) (−\(drag.points)). Fighting every safe fix toward 100."
            } else {
                heroBody.stringValue = "Measuring what to fix next. Autopilot will apply every safe change it can."
            }
            if state.isScanningFolders {
                fixButton.title = "Scanning…"
                fixButton.isEnabled = false
            } else if state.isBusy {
                fixButton.title = "Fighting…"
                fixButton.isEnabled = false
            } else {
                fixButton.title = "Fight for 100"
                fixButton.isEnabled = true
            }
        } else {
            heroPanel.isHidden = true
            clearPanel.isHidden = false
            clearTitle.stringValue = "Pulse at 100"
            clearBody.stringValue = "Goal held. Autopilot keeps watching and will fight any slip back down."
        }

        let showAccess = state.needsFilesAccess || !state.isRunningFromApplications
        permissionPanel.isHidden = !showAccess
        if showAccess {
            permissionBody.stringValue = state.accessHelpText
        }

        if state.isScanningFolders {
            scanPanel.isHidden = false
            scanTitle.stringValue = "SCANNING STORAGE"
            scanSummary.stringValue = "Preferring old, unused, and regenerable files first…"
            scanBody.stringValue = "Working… usually a few seconds.\nNothing will be deleted."
        } else if state.didRunStorageScan, state.storageScan.candidates.isEmpty, state.largeFolders.isEmpty {
            scanPanel.isHidden = false
            scanTitle.stringValue = "SCAN RESULTS"
            scanSummary.stringValue = state.needsFilesAccess
                ? "macOS blocked the scan. Enable Full Disk Access, then try Show me again."
                : "No reclaim candidates found above the size threshold."
            scanBody.stringValue = "Try Full Disk Access for /Applications/PCOptopus.app if this looks wrong."
        } else if state.storageScan.candidates.isEmpty && state.largeFolders.isEmpty {
            scanPanel.isHidden = true
        } else {
            scanPanel.isHidden = false
            let scan = state.storageScan
            let rec = scan.recommended
            if scan.bytesNeeded > 0 {
                scanTitle.stringValue = "RECOMMENDED DELETIONS"
                let after = scan.availableBytes + scan.recommendedBytes
                scanSummary.stringValue =
                    "Need \(Formatters.bytes(scan.bytesNeeded)) to reach 80 GB free. " +
                    "Suggested reclaim \(Formatters.bytes(scan.recommendedBytes)) → ~\(Formatters.bytes(after)) free."
            } else {
                scanTitle.stringValue = "OPTIONAL CLEANUP"
                scanSummary.stringValue = "Already at the 80 GB target. Safest idle clutter below."
            }
            let lines = (rec.isEmpty ? scan.candidates : rec).prefix(10).map { item -> String in
                let mark = item.recommended ? "●" : "○"
                let size = Formatters.bytes(item.bytes)
                let pad = String(repeating: " ", count: max(0, 7 - size.count))
                return "\(mark) \(pad)\(size)  \(item.path)\n   \(item.reason)"
            }
            scanBody.stringValue = lines.joined(separator: "\n")
        }

        if let entry = state.journal.first {
            journalLabel.stringValue = "Last change · \(entry.title) · \(entry.beforeValue) → \(entry.afterValue)"
            undoButton.isHidden = entry.result != .applied
        } else {
            journalLabel.stringValue = "Last change · none yet"
            undoButton.isHidden = true
        }

        if state.isScanningFolders || state.didRunStorageScan {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.page.scrollToReveal(self.scanPanel)
            }
        }
    }

    @objc private func fixTapped() {
        fixButton.title = "Fighting…"
        fixButton.isEnabled = false
        scanPanel.isHidden = false
        scanTitle.stringValue = "FIGHTING FOR PULSE 100"
        scanSummary.stringValue = "Applying every safe fix — storage scan if needed…"
        scanBody.stringValue = "Nothing is deleted automatically.\nmacOS may ask for a password for power settings."
        onLeadAction?()
    }

    @objc private func undoTapped() { onUndo?() }
    @objc private func permissionsTapped() { onOpenPermissions?() }
}
