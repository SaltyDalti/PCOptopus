import SwiftUI
import Model

@main
struct PCOptopusApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
        } label: {
            MenuBarLabel(status: state.autopilotStatus, hasAction: !state.leadFindings().isEmpty || state.settings.killSwitch)
        }

        WindowGroup("PCOptopus") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct MenuBarLabel: View {
    let status: AutopilotStatus
    let hasAction: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "octopus.fill")
            if hasAction || status == .stopped {
                Circle()
                    .fill(status == .stopped ? PCTheme.act : PCTheme.attention)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("PCOptopus, autopilot \(status.title)")
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PCOptopus")
                .font(.headline)
            Text(state.todayParagraph)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: 280, alignment: .leading)
            Divider()
            Text("Autopilot: \(state.autopilotStatus.title)")
            Toggle("Kill switch", isOn: Binding(
                get: { state.settings.killSwitch },
                set: {
                    state.settings.killSwitch = $0
                    state.saveSettings()
                }
            ))
            Button("Open PCOptopus") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.title == "PCOptopus" {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Button("Quit") {
                state.stop()
                NSApp.terminate(nil)
            }
        }
        .padding(12)
    }
}
