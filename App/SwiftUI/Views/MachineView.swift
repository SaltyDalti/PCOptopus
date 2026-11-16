import SwiftUI
import Model

struct MachineView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Machine")
                    .font(.largeTitle.weight(.semibold))

                VStack(alignment: .leading, spacing: 12) {
                    Text(state.identity.name)
                        .font(.title2.weight(.semibold))
                    LabeledContent("Model", value: state.identity.modelIdentifier)
                    LabeledContent("Chip", value: state.identity.chip)
                    LabeledContent("CPU", value: state.identity.coreSplitLabel)
                    LabeledContent("GPU", value: "\(state.identity.gpuCores) cores")
                    LabeledContent("Memory", value: state.identity.memoryGigabytesLabel)
                    LabeledContent("Storage container", value: Formatters.bytes(state.identity.storageContainerBytes))
                    LabeledContent("macOS", value: "\(state.identity.osVersion) (\(state.identity.osBuild))")
                    LabeledContent("Architecture", value: state.identity.architecture)
                    LabeledContent("SIP", value: state.identity.sipEnabled ? "Enabled" : "Disabled")
                }
                .pcCard()

                Text(state.identity.unifiedMemorySentence)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .pcCard()
                    .accessibilityLabel(state.identity.unifiedMemorySentence)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Active profile")
                        .font(.headline)
                    Text(state.activeProfile.title)
                        .font(.title3)
                    Text(state.activeProfile.detail)
                        .foregroundStyle(.secondary)
                }
                .pcCard()
            }
            .padding(24)
        }
    }
}
