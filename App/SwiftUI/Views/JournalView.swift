import SwiftUI
import Model

struct JournalView: View {
    @EnvironmentObject private var state: AppState
    @State private var filter: JournalActor? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Journal")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Picker("Filter", selection: $filter) {
                    Text("All").tag(Optional<JournalActor>.none)
                    Text("You").tag(Optional.some(JournalActor.you))
                    Text("Autopilot").tag(Optional.some(JournalActor.autopilot))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }
            .padding(24)

            List {
                ForEach(filtered) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.title)
                                .font(.headline)
                            Spacer()
                            Text(entry.actor == .you ? "You" : "Autopilot")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(entry.beforeValue) → \(entry.afterValue)")
                            .font(.system(.body, design: .monospaced))
                        Text(entry.result.rawValue.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(entry.result == .failed ? PCTheme.act : .secondary)
                        if entry.result == .applied {
                            Button("Undo") { state.undo(entry: entry) }
                        }
                        if let error = entry.errorMessage {
                            Text(error).foregroundStyle(PCTheme.act).font(.caption)
                        }
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var filtered: [JournalEntry] {
        guard let filter else { return state.journal }
        return state.journal.filter { $0.actor == filter }
    }
}
