import SwiftUI
import Model

struct ActionDetailView: View {
    @EnvironmentObject private var state: AppState
    let finding: Finding
    let actionID: String

    private var definition: ActionDefinition? {
        ActionCatalog.definition(id: actionID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(definition?.title ?? actionID)
                    .font(.largeTitle.weight(.semibold))
                Text(definition?.risk.title ?? "")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Why")
                        .font(.headline)
                    Text(finding.summary)
                    Text("Setting")
                        .font(.headline)
                    Text(settingPreview)
                        .font(.system(.body, design: .monospaced))
                    Text("Undo path: journal stores the previous value and can restore it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .pcCard()

                Button(definition?.risk.primaryButtonTitle ?? "Continue") {
                    perform()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(definition?.risk.primaryButtonTitle ?? "Continue")

                if let error = state.lastError {
                    Text(error)
                        .foregroundStyle(PCTheme.act)
                }
            }
            .padding(24)
        }
        .navigationTitle("Action")
    }

    private var settingPreview: String {
        switch actionID {
        case "energy.ac.sleep.set":
            let before = state.bundle.int(.energyACSleepMinutes) ?? 0
            let target = Int(state.contract.grant(for: actionID)?.bounds.target ?? 30)
            return "pmset -c sleep  \(before) → \(target)"
        case "software.brew.path.native":
            return "~/.zprofile  prepend /opt/homebrew/bin"
        case "storage.scan.largeFolders":
            return "Read-only scan of known heavy roots"
        case "background.agent.disable":
            let label = state.contract.grant(for: actionID)?.bounds.agentLabel ?? "com.BlueStacks.AppPlayer.Service"
            return "launchctl bootout  \(label)"
        default:
            return actionID
        }
    }

    private func perform() {
        guard let definition else { return }
        switch definition.risk {
        case .autopilot:
            state.contract.setEnabled(actionID, enabled: true)
            if actionID == "background.agent.disable",
               state.contract.grant(for: actionID)?.bounds.agentLabel == nil {
                var bounds = state.contract.grant(for: actionID)?.bounds ?? ActionBounds()
                bounds.agentLabel = "com.BlueStacks.AppPlayer.Service"
                state.contract.setBounds(actionID, bounds: bounds)
            }
            state.saveContract()
            state.settings.autopilotMasterEnabled = true
            state.saveSettings()
        case .confirm:
            switch actionID {
            case "software.brew.path.native":
                state.applyConfirm(
                    actionID: actionID,
                    parameters: [:],
                    before: "PATH without native first",
                    after: "/opt/homebrew/bin first"
                )
            case "energy.assertion.quitApp":
                let name = state.bundle.string(.energyAssertionProcess) ?? ""
                state.applyConfirm(
                    actionID: actionID,
                    parameters: ["processName": name],
                    before: "running",
                    after: "quit requested"
                )
            default:
                let before = state.bundle.int(.energyACSleepMinutes).map(String.init) ?? "?"
                let after = String(Int(state.contract.grant(for: "energy.ac.sleep.set")?.bounds.target ?? 30))
                state.applyConfirm(
                    actionID: actionID,
                    parameters: [
                        "key": "sleep",
                        "powerSource": "AC",
                        "value": after
                    ],
                    before: before,
                    after: after
                )
            }
        case .manual:
            if actionID == "storage.scan.largeFolders" {
                state.scanLargeFolders()
            }
        }
    }
}
