import SwiftUI
import Model
import Charts

struct WeekView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Week")
                    .font(.largeTitle.weight(.semibold))

                Text(state.coach.weekSummary(
                    practices: state.practices,
                    autopilotCount: state.journal.filter { $0.actor == .autopilot && $0.result == .applied }.count
                ))
                .pcCard()

                ForEach(state.practices) { practice in
                    HStack(alignment: .top) {
                        Image(systemName: practice.holding ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(practice.holding ? PCTheme.steady : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(practice.title).font(.headline)
                            Text(practice.detail).font(.caption).foregroundStyle(.secondary)
                            Text(practice.evidence)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .pcCard()
                    .accessibilityLabel("\(practice.title). \(practice.holding ? "Holding" : "Slipping"). \(practice.evidence)")
                }

                if let available = state.bundle.double(.storageAvailableBytes) {
                    VStack(alignment: .leading) {
                        Text("Storage available now")
                            .font(.headline)
                        Text(Formatters.bytes(available))
                            .font(.title2.monospacedDigit())
                        Chart {
                            BarMark(
                                x: .value("Metric", "Available GB"),
                                y: .value("GB", available / 1_073_741_824)
                            )
                            .foregroundStyle(PCTheme.accent)
                        }
                        .frame(height: 120)
                    }
                    .pcCard()
                }
            }
            .padding(24)
        }
    }
}
