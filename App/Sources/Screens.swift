import AppKit
import Model

// MARK: - Machine

final class MachineScreen: NSView {
    private let page = PageShell()
    private let titleLabel = label("Machine", font: Theme.title())
    private let subtitleLabel = label("This Mac’s identity", font: Theme.body(), color: Theme.secondaryLabel)
    private let nameLabel = label("", font: Theme.headline())
    private let detailLabel = label("", font: Theme.mono(), color: Theme.secondaryLabel)
    private let unifiedLabel = label("", font: Theme.body(), color: Theme.secondaryLabel)
    private let profileLabel = label("", font: Theme.body(), color: Theme.secondaryLabel)
    private let panel = SoftPanel()
    private let unifiedPanel = SoftPanel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        pin(page)
        panel.setViews([nameLabel, detailLabel])
        unifiedPanel.setViews([
            label("UNIFIED MEMORY", font: Theme.captionMedium(), color: Theme.tertiaryLabel),
            unifiedLabel
        ])
        page.install([
            vstack([titleLabel, subtitleLabel], spacing: 4),
            panel,
            unifiedPanel,
            profileLabel
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reload(state: AppState) {
        let m = state.identity
        nameLabel.stringValue = m.name
        detailLabel.stringValue = [
            m.modelIdentifier,
            m.chip,
            m.coreSplitLabel,
            "\(m.gpuCores) GPU cores",
            m.memoryGigabytesLabel,
            "macOS \(m.osVersion)",
            m.architecture,
            m.sipEnabled ? "SIP on" : "SIP off"
        ].joined(separator: "\n")
        unifiedLabel.stringValue = m.unifiedMemorySentence
        profileLabel.stringValue = "Profile · \(state.activeProfile.title) — \(state.activeProfile.detail)"
    }
}

// MARK: - Domains

final class DomainsScreen: NSView {
    private let page = PageShell()
    private let list = NSStackView()
    private var state: AppState?
    var onScan: (() -> Void)?
    var onDomainAction: ((Finding) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        pin(page)
        list.orientation = .vertical
        list.spacing = 12
        list.translatesAutoresizingMaskIntoConstraints = false
        page.install([
            vstack([
                label("Domains", font: Theme.title()),
                label("Eight quiet health checks", font: Theme.body(), color: Theme.secondaryLabel)
            ], spacing: 4),
            list
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reload(state: AppState) {
        self.state = state
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        for domain in Domain.allCases {
            let finding = state.findings.first { $0.domain == domain }
            let panel = SoftPanel()
            let title = label(domain.title, font: Theme.headline())
            let pill = Pill()
            pill.set(
                finding?.severity.title ?? "…",
                color: Theme.severity(finding?.severity ?? .steady)
            )
            let summary = label(
                finding?.summary ?? domain.whatGoodLooksLike,
                font: Theme.body(),
                color: Theme.secondaryLabel
            )
            var rows: [NSView] = [hstack([title, flexibleSpacer(), pill]), summary]
            if domain == .storage {
                let scan = secondaryButton(
                    state.isScanningFolders ? "Scanning…" : "Scan for reclaimable storage",
                    target: self,
                    action: #selector(scan)
                )
                scan.isEnabled = !state.isScanningFolders
                rows.append(scan)
                if !state.storageScan.candidates.isEmpty {
                    let need = state.storageScan.bytesNeeded
                    let plan = need > 0
                        ? "Plan: reclaim \(Formatters.bytes(state.storageScan.recommendedBytes)) toward 80 GB free"
                        : "Optional cleanup (already under target)"
                    rows.append(label(plan, font: Theme.caption(), color: Theme.secondaryLabel))
                }
                let items = state.storageScan.candidates.isEmpty
                    ? state.largeFolders.prefix(6).map { (true, $0.path, $0.bytes, "Large folder") }
                    : state.storageScan.candidates.prefix(8).map { ($0.recommended, $0.path, $0.bytes, $0.reason) }
                for (recommended, path, bytes, reason) in items {
                    let mark = recommended ? "● " : "○ "
                    rows.append(vstack([
                        hstack([
                            label(mark + path, font: Theme.mono(), wrap: false),
                            flexibleSpacer(),
                            label(Formatters.bytes(bytes), font: Theme.mono())
                        ]),
                        label(reason, font: Theme.caption(), color: Theme.tertiaryLabel)
                    ], spacing: 2))
                }
            }
            if let finding, finding.actionIDs.first != nil {
                let btn = linkButton("Fix this", target: self, action: #selector(act(_:)))
                btn.identifier = NSUserInterfaceItemIdentifier(finding.id)
                rows.append(btn)
            }
            panel.setViews(rows)
            list.addArrangedSubview(panel)
        }
    }

    @objc private func scan() { onScan?() }
    @objc private func act(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let finding = state?.findings.first(where: { $0.id == id }) else { return }
        onDomainAction?(finding)
    }
}

// MARK: - Contract

final class ContractScreen: NSView {
    private struct GrantControls {
        let toggle: NSButton
        let targetLabel: NSTextField?
        let slider: NSSlider?
        let agentField: NSTextField?
    }

    private let page = PageShell()
    private let list = NSStackView()
    private let masterToggle = NSButton(
        checkboxWithTitle: "Allow autopilot to run granted items",
        target: nil,
        action: nil
    )
    private var grantControls: [String: GrantControls] = [:]
    private var builtGrantIDs: [String] = []
    private var didBuildMaster = false
    private var state: AppState?
    /// Light refresh only — never tear down controls mid-click.
    var onChanged: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        pin(page)
        list.orientation = .vertical
        list.spacing = 12
        list.translatesAutoresizingMaskIntoConstraints = false
        masterToggle.target = self
        masterToggle.action = #selector(toggleMaster(_:))
        masterToggle.font = Theme.bodyMedium()
        page.install([
            vstack([
                label("Contract", font: Theme.title()),
                label("Nothing granted means nothing changes", font: Theme.body(), color: Theme.secondaryLabel)
            ], spacing: 4),
            list
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reload(state: AppState) {
        self.state = state
        let ids = state.contract.grants.map(\.actionID)
        if !didBuildMaster || ids != builtGrantIDs {
            rebuildStructure(state: state)
        }
        apply(state: state)
    }

    private func rebuildStructure(state: AppState) {
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        grantControls.removeAll()

        let masterPanel = SoftPanel()
        masterPanel.setViews([
            masterToggle,
            label("You still choose each grant below.", font: Theme.caption(), color: Theme.secondaryLabel)
        ])
        list.addArrangedSubview(masterPanel)
        didBuildMaster = true

        var ids: [String] = []
        for grant in state.contract.grants {
            ids.append(grant.actionID)
            let def = ActionCatalog.definition(id: grant.actionID)
            let toggle = NSButton(
                checkboxWithTitle: def?.title ?? grant.actionID,
                target: self,
                action: #selector(toggleGrant(_:))
            )
            toggle.identifier = NSUserInterfaceItemIdentifier(grant.actionID)
            toggle.font = Theme.bodyMedium()

            var rows: [NSView] = [
                toggle,
                label(def?.detail ?? "", font: Theme.caption(), color: Theme.secondaryLabel)
            ]
            var targetLabel: NSTextField?
            var slider: NSSlider?
            var agentField: NSTextField?

            if let minV = grant.bounds.min, let maxV = grant.bounds.max {
                let target = grant.bounds.target ?? minV
                let tl = label("Target \(Int(target)) min · \(Int(minV))–\(Int(maxV))", font: Theme.mono())
                targetLabel = tl
                rows.append(tl)
                let s = NSSlider(value: target, minValue: minV, maxValue: maxV, target: self, action: #selector(sliderMoved(_:)))
                s.identifier = NSUserInterfaceItemIdentifier(grant.actionID)
                s.isContinuous = false
                slider = s
                rows.append(s)
            }
            if grant.actionID == "background.agent.disable" {
                let field = NSTextField(string: grant.bounds.agentLabel ?? "")
                field.placeholderString = "LaunchAgent label"
                field.font = Theme.mono()
                field.identifier = NSUserInterfaceItemIdentifier(grant.actionID)
                field.target = self
                field.action = #selector(agentChanged(_:))
                field.bezelStyle = .roundedBezel
                agentField = field
                rows.append(field)
            }
            grantControls[grant.actionID] = GrantControls(
                toggle: toggle,
                targetLabel: targetLabel,
                slider: slider,
                agentField: agentField
            )
            let panel = SoftPanel()
            panel.setViews(rows)
            list.addArrangedSubview(panel)
        }
        builtGrantIDs = ids
    }

    private func apply(state: AppState) {
        masterToggle.state = state.settings.autopilotMasterEnabled ? .on : .off
        for grant in state.contract.grants {
            guard let controls = grantControls[grant.actionID] else { continue }
            controls.toggle.state = grant.enabled ? .on : .off
            if let minV = grant.bounds.min, let maxV = grant.bounds.max {
                let target = grant.bounds.target ?? minV
                controls.targetLabel?.stringValue = "Target \(Int(target)) min · \(Int(minV))–\(Int(maxV))"
                controls.slider?.minValue = minV
                controls.slider?.maxValue = maxV
                controls.slider?.doubleValue = target
            }
            if let field = controls.agentField, field.currentEditor() == nil {
                field.stringValue = grant.bounds.agentLabel ?? ""
            }
        }
    }

    @objc private func toggleMaster(_ s: NSButton) {
        state?.settings.autopilotMasterEnabled = s.state == .on
        state?.saveSettings()
        onChanged?()
    }
    @objc private func toggleGrant(_ s: NSButton) {
        guard let id = s.identifier?.rawValue else { return }
        state?.contract.setEnabled(id, enabled: s.state == .on)
        state?.saveContract()
        onChanged?()
    }
    @objc private func sliderMoved(_ s: NSSlider) {
        guard let id = s.identifier?.rawValue, var g = state?.contract.grant(for: id) else { return }
        g.bounds.target = s.doubleValue
        state?.contract.setBounds(id, bounds: g.bounds)
        state?.saveContract()
        if let controls = grantControls[id], let minV = g.bounds.min, let maxV = g.bounds.max {
            controls.targetLabel?.stringValue = "Target \(Int(s.doubleValue)) min · \(Int(minV))–\(Int(maxV))"
        }
        onChanged?()
    }
    @objc private func agentChanged(_ s: NSTextField) {
        guard let id = s.identifier?.rawValue, var g = state?.contract.grant(for: id) else { return }
        g.bounds.agentLabel = s.stringValue
        state?.contract.setBounds(id, bounds: g.bounds)
        state?.saveContract()
    }
}

// MARK: - Journal

final class JournalScreen: NSView {
    private let page = PageShell()
    private let filter = NSSegmentedControl(labels: ["All", "You", "Autopilot"], trackingMode: .selectOne, target: nil, action: nil)
    private let list = NSStackView()
    private var selected = 0
    private var state: AppState?
    var onUndo: ((JournalEntry) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        pin(page)
        filter.selectedSegment = 0
        filter.target = self
        filter.action = #selector(filterChanged)
        filter.segmentStyle = .rounded
        list.orientation = .vertical
        list.spacing = 10
        list.translatesAutoresizingMaskIntoConstraints = false
        page.install([
            vstack([
                label("Journal", font: Theme.title()),
                label("Every change, with undo", font: Theme.body(), color: Theme.secondaryLabel)
            ], spacing: 4),
            filter,
            list
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reload(state: AppState) {
        self.state = state
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        let entries: [JournalEntry]
        switch selected {
        case 1: entries = state.journal.filter { $0.actor == .you }
        case 2: entries = state.journal.filter { $0.actor == .autopilot }
        default: entries = state.journal
        }
        if entries.isEmpty {
            let empty = SoftPanel()
            empty.setViews([
                label("No changes yet", font: Theme.headline()),
                label("When something is applied, it shows up here.", font: Theme.body(), color: Theme.secondaryLabel)
            ])
            list.addArrangedSubview(empty)
            return
        }
        for entry in entries.prefix(40) {
            let panel = SoftPanel()
            var rows: [NSView] = [
                label(entry.title, font: Theme.headline()),
                label(
                    "\(entry.actor == .you ? "You" : "Autopilot") · \(entry.result.rawValue)",
                    font: Theme.caption(),
                    color: Theme.secondaryLabel
                ),
                label("\(entry.beforeValue)  →  \(entry.afterValue)", font: Theme.mono())
            ]
            if entry.result == .applied {
                let undo = linkButton("Undo", target: self, action: #selector(undo(_:)))
                undo.identifier = NSUserInterfaceItemIdentifier(entry.id.uuidString)
                rows.append(undo)
            }
            panel.setViews(rows)
            list.addArrangedSubview(panel)
        }
    }

    @objc private func filterChanged() {
        selected = filter.selectedSegment
        if let state { reload(state: state) }
    }
    @objc private func undo(_ s: NSButton) {
        guard let raw = s.identifier?.rawValue,
              let id = UUID(uuidString: raw),
              let entry = state?.journal.first(where: { $0.id == id }) else { return }
        onUndo?(entry)
    }
}

// MARK: - Week

final class WeekScreen: NSView {
    private let page = PageShell()
    private let summary = label("", font: Theme.body(), color: Theme.secondaryLabel)
    private let list = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        pin(page)
        list.orientation = .vertical
        list.spacing = 10
        list.translatesAutoresizingMaskIntoConstraints = false
        page.install([
            vstack([
                label("Week", font: Theme.title()),
                label("Practices — not a score", font: Theme.body(), color: Theme.secondaryLabel)
            ], spacing: 4),
            SoftPanel().then {
                $0.setViews([summary])
            },
            list
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reload(state: AppState) {
        let count = state.journal.filter { $0.actor == .autopilot && $0.result == .applied }.count
        summary.stringValue = state.coach.weekSummary(
            practices: state.practices,
            autopilotCount: count,
            pulse: state.pulse
        )
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        for practice in state.practices {
            let panel = SoftPanel()
            let status = Pill()
            status.set(practice.holding ? "Holding" : "Slipping", color: practice.holding ? Theme.steady : Theme.attention)
            panel.setViews([
                hstack([label(practice.title, font: Theme.headline()), flexibleSpacer(), status]),
                label(practice.detail, font: Theme.body(), color: Theme.secondaryLabel),
                label(practice.evidence.isEmpty ? "Waiting on samples" : practice.evidence, font: Theme.mono(), color: Theme.secondaryLabel)
            ])
            list.addArrangedSubview(panel)
        }
    }
}

// MARK: - Ask

final class AskScreen: NSView {
    private let page = PageShell()
    private let field = NSTextField()
    private let askButton = primaryButton("Ask", target: nil, action: nil)
    private let answer = label("", font: Theme.body())
    private let related = label("", font: Theme.mono(), color: Theme.secondaryLabel)
    private let answerPanel = SoftPanel()
    var onAsk: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        pin(page)
        field.placeholderString = "Storage, sleep, Homebrew, memory…"
        field.font = Theme.body()
        field.bezelStyle = .roundedBezel
        field.target = self
        field.action = #selector(ask)
        askButton.target = self
        askButton.action = #selector(ask)
        answerPanel.isHidden = true
        answerPanel.setViews([
            label("ANSWER", font: Theme.captionMedium(), color: Theme.tertiaryLabel),
            answer,
            related
        ])
        let input = SoftPanel()
        input.setViews([
            label("Answers use measured numbers only — never invented shell.", font: Theme.body(), color: Theme.secondaryLabel),
            hstack([field, askButton], spacing: 10)
        ])
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        page.install([
            vstack([
                label("Ask", font: Theme.title()),
                label("Quick questions about this Mac", font: Theme.body(), color: Theme.secondaryLabel)
            ], spacing: 4),
            input,
            answerPanel
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reload(state: AppState) {
        if let a = state.askAnswer {
            answer.stringValue = a.prose
            related.stringValue = a.actionIDs.isEmpty ? "" : "Related: \(a.actionIDs.joined(separator: ", "))"
            related.isHidden = a.actionIDs.isEmpty
            answerPanel.isHidden = false
        }
    }

    @objc private func ask() { onAsk?(field.stringValue) }
}

// MARK: - Settings

final class SettingsScreen: NSView {
    private let page = PageShell()
    private var state: AppState?
    private let safetyPanel = SoftPanel()
    private let accessPanel = SoftPanel()
    private let diagPanel = SoftPanel()
    private let dbLabel = label("", font: Theme.mono(), color: Theme.secondaryLabel)
    private let accessHelp = label("", font: Theme.body(), color: Theme.secondaryLabel)
    private let killSwitch = NSButton(checkboxWithTitle: "Kill switch — block privileged changes", target: nil, action: nil)
    private let pauseBattery = NSButton(checkboxWithTitle: "Pause autopilot on battery", target: nil, action: nil)
    private let pauseAssert = NSButton(checkboxWithTitle: "Pause during prevent-sleep assertions", target: nil, action: nil)
    private let quietHours = NSButton(checkboxWithTitle: "Quiet hours 22:00–07:00", target: nil, action: nil)
    private let fdaButton = secondaryButton("Open Full Disk Access", target: nil, action: nil)
    private let exportButton = secondaryButton("Export redacted diagnostic", target: nil, action: nil)
    private var didInstallPanels = false
    var onChanged: (() -> Void)?
    var onExport: (() -> Void)?
    var onOpenPermissions: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        pin(page)

        for box in [killSwitch, pauseBattery, pauseAssert, quietHours] {
            box.target = self
            box.font = Theme.body()
        }
        killSwitch.action = #selector(toggleKill(_:))
        pauseBattery.action = #selector(toggleBattery(_:))
        pauseAssert.action = #selector(toggleAssert(_:))
        quietHours.action = #selector(toggleQuiet(_:))
        fdaButton.target = self
        fdaButton.action = #selector(openPermissions)
        exportButton.target = self
        exportButton.action = #selector(exportTapped)

        page.install([
            vstack([
                label("Settings", font: Theme.title()),
                label("Safety fences", font: Theme.body(), color: Theme.secondaryLabel)
            ], spacing: 4),
            safetyPanel,
            accessPanel,
            diagPanel,
            SoftPanel().then {
                $0.setViews([
                    label("DATABASE", font: Theme.captionMedium(), color: Theme.tertiaryLabel),
                    dbLabel
                ])
            }
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reload(state: AppState) {
        self.state = state
        if !didInstallPanels {
            safetyPanel.setViews([
                label("SAFETY", font: Theme.captionMedium(), color: Theme.tertiaryLabel),
                killSwitch,
                pauseBattery,
                pauseAssert,
                quietHours
            ])
            accessPanel.setViews([
                label("FULL DISK ACCESS", font: Theme.captionMedium(), color: Theme.tertiaryLabel),
                accessHelp,
                label(
                    "Use /Applications/PCOptopus.app. Folder toggles alone won’t stick across rebuilds.",
                    font: Theme.caption(),
                    color: Theme.tertiaryLabel
                ),
                fdaButton
            ])
            diagPanel.setViews([
                label("DIAGNOSTICS", font: Theme.captionMedium(), color: Theme.tertiaryLabel),
                label("Export strips serials and private paths.", font: Theme.caption(), color: Theme.secondaryLabel),
                exportButton
            ])
            didInstallPanels = true
        }
        killSwitch.state = state.settings.killSwitch ? .on : .off
        pauseBattery.state = state.settings.pauseOnBattery ? .on : .off
        pauseAssert.state = state.settings.pauseDuringPreventSleepAssertions ? .on : .off
        quietHours.state = state.settings.quietHoursStart != nil ? .on : .off
        accessHelp.stringValue = state.accessHelpText
        dbLabel.stringValue = state.store.databasePath.path
    }

    @objc private func toggleKill(_ s: NSButton) {
        state?.settings.killSwitch = s.state == .on
        state?.saveSettings()
        onChanged?()
    }
    @objc private func toggleBattery(_ s: NSButton) {
        state?.settings.pauseOnBattery = s.state == .on
        state?.saveSettings()
        onChanged?()
    }
    @objc private func toggleAssert(_ s: NSButton) {
        state?.settings.pauseDuringPreventSleepAssertions = s.state == .on
        state?.saveSettings()
        onChanged?()
    }
    @objc private func toggleQuiet(_ s: NSButton) {
        if s.state == .on {
            state?.settings.quietHoursStart = 22
            state?.settings.quietHoursEnd = 7
        } else {
            state?.settings.quietHoursStart = nil
            state?.settings.quietHoursEnd = nil
        }
        state?.saveSettings()
        onChanged?()
    }
    @objc private func exportTapped() { onExport?() }
    @objc private func openPermissions() { onOpenPermissions?() }
}

// MARK: - Onboarding

final class OnboardingScreen: NSView {
    private let page = PageShell()
    private let titleLabel = label("PCOptopus", font: Theme.display())
    private let bodyLabel = label("", font: Theme.body(), color: Theme.secondaryLabel)
    private let statusLabel = label("", font: Theme.caption(), color: Theme.secondaryLabel)
    private let progress = NSProgressIndicator()
    private let button = primaryButton("Open Today", target: nil, action: nil)
    var onContinue: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        pin(page)
        button.target = self
        button.action = #selector(cont)
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.heightAnchor.constraint(equalToConstant: 4).isActive = true
        let panel = SoftPanel()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "PCOptopus")
            ?? NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "PCOptopus")
        icon.contentTintColor = Theme.accent
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        panel.setViews([icon, titleLabel, bodyLabel, statusLabel, progress, button])
        page.install([panel])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reload(state: AppState) {
        let leads = state.leadFindings().prefix(3)
        if state.baselineComplete {
            if leads.isEmpty {
                bodyLabel.stringValue = "\(state.identity.chip) · \(state.identity.memoryGigabytesLabel)\n\nPulse \(state.pulse.percent). Open Today — Autopilot fights to keep Pulse at 100 and won’t change settings until you ask."
            } else {
                bodyLabel.stringValue = "\(state.identity.chip) · \(state.identity.memoryGigabytesLabel)\n\nPulse \(state.pulse.percent) — fighting for +\(state.pulse.deficit).\n" + leads.map { "• \($0.title)" }.joined(separator: "\n") + "\n\nRaise Pulse on Today handles the top drag."
            }
            statusLabel.stringValue = "Ready"
            progress.doubleValue = 1
            button.title = "Open Today"
        } else {
            bodyLabel.stringValue = "\(state.identity.chip) · \(state.identity.memoryGigabytesLabel)\n\nMeasuring in the background. The window stays responsive."
            statusLabel.stringValue = state.statusMessage
            progress.doubleValue = state.baselineProgress
            button.title = "Open Today anyway"
        }
    }

    @objc private func cont() { onContinue?() }
}

// MARK: - Helpers

private extension NSView {
    func pin(_ child: NSView) {
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.trailingAnchor.constraint(equalTo: trailingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
            child.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

private protocol Then {}
extension Then where Self: AnyObject {
    func then(_ block: (Self) -> Void) -> Self {
        block(self)
        return self
    }
}
extension SoftPanel: Then {}
