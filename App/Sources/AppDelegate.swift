import AppKit
import Combine
import Model

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var statusItem: NSStatusItem?
    private var windowController: MainWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = AppState(startLoops: true)
        windowController = MainWindowController(state: state)
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupStatusItem()

        // Only redraw when AppState explicitly bumps uiGeneration — not every CPU sample.
        state.$uiGeneration
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
                self?.windowController?.reload()
            }
            .store(in: &cancellables)

        // First paint shortly after launch even if baseline is still running.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.state.bumpUI()
        }

    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController?.showWindow(nil)
        }
        return true
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "PCOptopus")
                ?? NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "PCOptopus")
            button.imagePosition = .imageOnly
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open PCOptopus", action: #selector(openWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Scan storage…", action: #selector(scanStorage), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Toggle Kill Switch", action: #selector(toggleKill), keyEquivalent: "k"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit PCOptopus", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
        refreshStatusItem()
    }

    @objc private func scanStorage() {
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        state.scanLargeFolders()
        state.bumpUI()
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button, let state else { return }
        button.title = " \(state.pulse.percent)"
        button.toolTip = "PCOptopus Pulse \(state.pulse.percent) — \(state.pulse.headline). Autopilot \(state.autopilotStatus.title)"
    }

    @objc private func openWindow() {
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleKill() {
        state.settings.killSwitch.toggle()
        state.saveSettings()
        refreshStatusItem()
        state.bumpUI()
    }

    @objc private func quit() {
        state.stop()
        NSApp.terminate(nil)
    }
}
