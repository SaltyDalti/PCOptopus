import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("Safety") {
                Toggle("Kill switch", isOn: Binding(
                    get: { state.settings.killSwitch },
                    set: {
                        state.settings.killSwitch = $0
                        state.saveSettings()
                    }
                ))
                .accessibilityLabel("Kill switch")
                Toggle("Pause autopilot on battery", isOn: Binding(
                    get: { state.settings.pauseOnBattery },
                    set: {
                        state.settings.pauseOnBattery = $0
                        state.saveSettings()
                    }
                ))
                Toggle("Pause during prevent-sleep assertions", isOn: Binding(
                    get: { state.settings.pauseDuringPreventSleepAssertions },
                    set: {
                        state.settings.pauseDuringPreventSleepAssertions = $0
                        state.saveSettings()
                    }
                ))
            }

            Section("Quiet hours") {
                Toggle("Enable quiet hours (22–07)", isOn: Binding(
                    get: { state.settings.quietHoursStart != nil },
                    set: { enabled in
                        if enabled {
                            state.settings.quietHoursStart = 22
                            state.settings.quietHoursEnd = 7
                        } else {
                            state.settings.quietHoursStart = nil
                            state.settings.quietHoursEnd = nil
                        }
                        state.saveSettings()
                    }
                ))
            }

            Section("Diagnostics") {
                Button("Export redacted diagnostic") {
                    if let url = state.exportDiagnostic() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Text("Export strips serials, home usernames in paths, and process arguments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("App", value: "PCOptopus")
                LabeledContent("Database", value: state.store.databasePath.path)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Settings")
    }
}
