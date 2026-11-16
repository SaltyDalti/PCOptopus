import SwiftUI

struct AskView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ask")
                .font(.largeTitle.weight(.semibold))
            Text("Answers use the last measured findings and samples. The coach never invents shell commands.")
                .foregroundStyle(.secondary)

            HStack {
                TextField("Ask about storage, sleep, Homebrew, memory…", text: $state.askQuestion)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { state.submitAsk() }
                    .accessibilityLabel("Question")
                Button("Ask") { state.submitAsk() }
                    .buttonStyle(.borderedProminent)
            }

            if let answer = state.askAnswer {
                VStack(alignment: .leading, spacing: 8) {
                    Text(answer.prose)
                    if !answer.actionIDs.isEmpty {
                        Text("Related actions: \(answer.actionIDs.joined(separator: ", "))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .pcCard()
            }

            Spacer()
        }
        .padding(24)
    }
}
