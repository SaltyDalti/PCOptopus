import AppKit
import Combine
import Model

final class MainWindowController: NSWindowController {
    private let state: AppState

    private let rootStack = NSStackView()
    private let flashBanner = FlashBanner()
    private let split = NSSplitView()
    private let sidebarHost = NSView()
    private let sidebarStack = NSStackView()
    private let contentHost = NSView()
    private let statusStrip = StatusStrip()
    private var navButtons: [NSButton] = []

    private let today = TodayScreen()
    private let machine = MachineScreen()
    private let domains = DomainsScreen()
    private let contract = ContractScreen()
    private let journal = JournalScreen()
    private let week = WeekScreen()
    private let ask = AskScreen()
    private let settings = SettingsScreen()
    private let onboarding = OnboardingScreen()

    private let items: [SidebarItem] = [
        .init(id: "today", title: "Today", symbol: "sun.max"),
        .init(id: "machine", title: "Machine", symbol: "laptopcomputer"),
        .init(id: "domains", title: "Domains", symbol: "square.grid.2x2"),
        .init(id: "contract", title: "Contract", symbol: "checkmark.shield"),
        .init(id: "journal", title: "Journal", symbol: "list.bullet.rectangle"),
        .init(id: "week", title: "Week", symbol: "calendar"),
        .init(id: "ask", title: "Ask", symbol: "text.bubble"),
        .init(id: "settings", title: "Settings", symbol: "gearshape")
    ]

    private var selectedIndex = 0
    private var reloadScheduled = false

    init(state: AppState) {
        self.state = state
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PCOptopus"
        window.minSize = NSSize(width: 920, height: 600)
        window.toolbarStyle = .unified
        window.center()
        super.init(window: window)
        buildChrome()
        wireActions()
        showSelected()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.reloadScheduled = false
            self?.reloadNow()
        }
    }

    /// Update flash/status without rebuilding the active screen's controls.
    private func refreshChromeOnly() {
        flashBanner.apply(state.flashMessage)
        statusStrip.apply(
            message: state.statusMessage,
            busy: state.isBusy || state.isScanningFolders || !state.baselineComplete,
            progress: state.baselineProgress,
            baselineComplete: state.baselineComplete
        )
    }

    private func reloadNow() {
        refreshChromeOnly()

        if !state.settings.hasCompletedOnboarding {
            showOnly(onboarding)
            onboarding.reload(state: state)
            return
        }

        showSelected()
        refreshNavButtons()
        switch selectedIndex {
        case 0: today.reload(state: state)
        case 1: machine.reload(state: state)
        case 2: domains.reload(state: state)
        case 3: contract.reload(state: state) // in-place when grant set unchanged
        case 4: journal.reload(state: state)
        case 5: week.reload(state: state)
        case 6: ask.reload(state: state)
        case 7: settings.reload(state: state) // in-place after first install
        default: break
        }
    }

    private func buildChrome() {
        guard let content = window?.contentView else { return }

        rootStack.orientation = .vertical
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: content.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        let flashWrap = NSView()
        flashWrap.translatesAutoresizingMaskIntoConstraints = false
        flashWrap.addSubview(flashBanner)
        NSLayoutConstraint.activate([
            flashBanner.leadingAnchor.constraint(equalTo: flashWrap.leadingAnchor, constant: 20),
            flashBanner.trailingAnchor.constraint(equalTo: flashWrap.trailingAnchor, constant: -20),
            flashBanner.topAnchor.constraint(equalTo: flashWrap.topAnchor, constant: 8),
            flashBanner.bottomAnchor.constraint(equalTo: flashWrap.bottomAnchor, constant: -4)
        ])

        split.isVertical = true
        split.dividerStyle = .thin
        split.autosaveName = "PCOptopus.split.v3"
        split.translatesAutoresizingMaskIntoConstraints = false

        sidebarHost.translatesAutoresizingMaskIntoConstraints = false
        sidebarHost.wantsLayer = true
        sidebarHost.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 2
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarHost.addSubview(sidebarStack)
        NSLayoutConstraint.activate([
            sidebarHost.widthAnchor.constraint(equalToConstant: Layout.sidebarWidth),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebarHost.leadingAnchor, constant: 10),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebarHost.trailingAnchor, constant: -10),
            sidebarStack.topAnchor.constraint(equalTo: sidebarHost.topAnchor, constant: 12)
        ])

        navButtons = items.enumerated().map { index, item in
            let button = NSButton(title: item.title, target: self, action: #selector(navTapped(_:)))
            button.tag = index
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.imagePosition = .imageLeading
            button.alignment = .left
            button.font = Theme.body()
            button.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)
            button.imageHugsTitle = true
            button.contentTintColor = .secondaryLabelColor
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            button.widthAnchor.constraint(equalToConstant: Layout.sidebarWidth - 20).isActive = true
            sidebarStack.addArrangedSubview(button)
            return button
        }
        refreshNavButtons()

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        for screen in allScreens() {
            screen.translatesAutoresizingMaskIntoConstraints = false
            contentHost.addSubview(screen)
            NSLayoutConstraint.activate([
                screen.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
                screen.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
                screen.topAnchor.constraint(equalTo: contentHost.topAnchor),
                screen.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor)
            ])
            screen.isHidden = true
        }

        split.addSubview(sidebarHost)
        split.addSubview(contentHost)
        rootStack.addArrangedSubview(flashWrap)
        rootStack.addArrangedSubview(split)
        rootStack.addArrangedSubview(statusStrip)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let h = self.split.bounds.height
            let w = self.split.bounds.width
            self.sidebarHost.frame = NSRect(x: 0, y: 0, width: Layout.sidebarWidth, height: h)
            self.contentHost.frame = NSRect(x: Layout.sidebarWidth, y: 0, width: max(400, w - Layout.sidebarWidth), height: h)
            self.split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
            self.split.setPosition(Layout.sidebarWidth, ofDividerAt: 0)
            self.split.adjustSubviews()
        }
    }

    private func allScreens() -> [NSView] {
        [today, machine, domains, contract, journal, week, ask, settings, onboarding]
    }

    private func wireActions() {
        today.onLeadAction = { [weak self] in
            self?.state.fightForPulse100(userInitiated: true)
        }
        today.onUndo = { [weak self] in
            guard let self, let entry = self.state.journal.first else { return }
            self.state.undo(entry: entry)
            self.reload()
        }
        today.onOpenPermissions = { [weak self] in
            self?.selectedIndex = 7
            self?.refreshNavButtons()
            self?.showSelected()
            self?.reloadNow()
            self?.state.openFilesAndFoldersSettings()
        }
        domains.onScan = { [weak self] in
            self?.state.scanLargeFolders()
            self?.reload()
        }
        domains.onDomainAction = { [weak self] _ in
            self?.state.fightForPulse100(userInitiated: true)
            self?.reload()
        }
        // Do not full-reload on toggle — that recreates controls mid-click.
        // Status/Today can refresh lightly; Contract/Settings apply state in place.
        contract.onChanged = { [weak self] in
            self?.refreshChromeOnly()
        }
        journal.onUndo = { [weak self] entry in
            self?.state.undo(entry: entry)
            self?.reload()
        }
        ask.onAsk = { [weak self] question in
            guard let self else { return }
            self.state.askQuestion = question
            self.state.submitAsk()
            self.reload()
        }
        settings.onChanged = { [weak self] in
            self?.refreshChromeOnly()
        }
        settings.onExport = { [weak self] in
            if let url = self?.state.exportDiagnostic() {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            self?.refreshChromeOnly()
        }
        settings.onOpenPermissions = { [weak self] in
            self?.state.openFilesAndFoldersSettings()
        }
        onboarding.onContinue = { [weak self] in
            self?.state.acceptAndStart()
            self?.selectedIndex = 0
            self?.refreshNavButtons()
            self?.reload()
        }
    }

    private func showSelected() {
        let screens: [NSView] = [today, machine, domains, contract, journal, week, ask, settings]
        for (idx, screen) in screens.enumerated() {
            screen.isHidden = idx != selectedIndex
        }
        onboarding.isHidden = true
        sidebarHost.isHidden = false
    }

    private func showOnly(_ view: NSView) {
        for screen in allScreens() {
            screen.isHidden = screen !== view
        }
        sidebarHost.isHidden = true
    }

    private func refreshNavButtons() {
        for (index, button) in navButtons.enumerated() {
            let selected = index == selectedIndex
            button.font = selected ? Theme.bodyMedium() : Theme.body()
            button.contentTintColor = selected ? Theme.accent : .secondaryLabelColor
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.layer?.backgroundColor = selected
                ? Theme.accent.withAlphaComponent(0.12).cgColor
                : NSColor.clear.cgColor
        }
    }

    @objc private func navTapped(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < items.count else { return }
        selectedIndex = row
        refreshNavButtons()
        showSelected()
        reloadNow()
    }
}
