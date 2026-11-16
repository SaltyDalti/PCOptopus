import SwiftUI
import Model

struct ContractView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Contract")
                    .font(.largeTitle.weight(.semibold))
                Text("Nothing granted means nothing will change. Autopilot stays inside these bounds.")
                    .foregroundStyle(.secondary)

                Toggle("Enable autopilot master switch", isOn: Binding(
                    get: { state.settings.autopilotMasterEnabled },
                    set: {
                        state.settings.autopilotMasterEnabled = $0
                        state.saveSettings()
                    }
                ))
                .pcCard()

                ForEach(state.contract.grants) { grant in
                    grantCard(grant)
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func grantCard(_ grant: ContractGrant) -> some View {
        let def = ActionCatalog.definition(id: grant.actionID)
        VStack(alignment: .leading, spacing: 10) {
            Toggle(def?.title ?? grant.actionID, isOn: Binding(
                get: { grant.enabled },
                set: { enabled in
                    state.contract.setEnabled(grant.actionID, enabled: enabled)
                    state.saveContract()
                }
            ))
            Text(def?.detail ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)

            if grant.bounds.min != nil, grant.bounds.max != nil {
                let minV = grant.bounds.min ?? 10
                let maxV = grant.bounds.max ?? 60
                let target = grant.bounds.target ?? 30
                VStack(alignment: .leading) {
                    Text("Target \(Int(target)) minutes (bounds \(Int(minV))–\(Int(maxV)))")
                        .font(.system(.caption, design: .monospaced))
                    Slider(
                        value: Binding(
                            get: { grant.bounds.target ?? 30 },
                            set: { newValue in
                                var bounds = grant.bounds
                                bounds.target = newValue
                                state.contract.setBounds(grant.actionID, bounds: bounds)
                                state.saveContract()
                            }
                        ),
                        in: minV...maxV,
                        step: 1
                    )
                    .accessibilityLabel("Target minutes for \(def?.title ?? grant.actionID)")
                }
            }

            if grant.actionID == "background.agent.disable" {
                TextField(
                    "LaunchAgent label",
                    text: Binding(
                        get: { grant.bounds.agentLabel ?? "" },
                        set: { label in
                            var bounds = grant.bounds
                            bounds.agentLabel = label
                            state.contract.setBounds(grant.actionID, bounds: bounds)
                            state.saveContract()
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            }
        }
        .pcCard()
    }
}
