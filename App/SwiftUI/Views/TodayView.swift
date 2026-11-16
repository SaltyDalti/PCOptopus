import SwiftUI
import Model

struct TodayView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Today")
                        .font(.largeTitle.weight(.semibold))
                    Spacer()
                    AutopilotPill(status: state.autopilotStatus)
                }

                Text(state.todayParagraph)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .pcCard()
                    .accessibilityLabel("Today summary")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    VitalCard(
                        title: "Storage",
                        value: storageLabel,
                        detail: "Aim for 80 GB free"
                    )
                    VitalCard(
                        title: "Memory",
                        value: state.bundle.string(.memoryPressure) ?? "—",
                        detail: "Unified memory pressure"
                    )
                    VitalCard(
                        title: "Energy",
                        value: energyLabel,
                        detail: "Power source and AC sleep"
                    )
                }

                if let lead = state.leadFindings().first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next action")
                            .font(.headline)
                        FindingRow(finding: lead)
                        if let actionID = lead.actionIDs.first,
                           let def = ActionCatalog.definition(id: actionID) {
                            NavigationLink {
                                ActionDetailView(finding: lead, actionID: actionID)
                            } label: {
                                Text(def.risk.primaryButtonTitle)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .pcCard()
                }

                if let entry = state.journal.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last change")
                            .font(.headline)
                        Text(entry.title)
                            .font(.body)
                        Text("\(entry.beforeValue) → \(entry.afterValue)")
                            .font(.system(.body, design: .monospaced))
                        if entry.result == .applied {
                            Button("Undo") { state.undo(entry: entry) }
                        }
                    }
                    .pcCard()
                    .accessibilityElement(children: .contain)
                }
            }
            .padding(24)
        }
        .background(PCTheme.surface)
    }

    private var storageLabel: String {
        guard let a = state.bundle.double(.storageAvailableBytes),
              let t = state.bundle.double(.storageContainerBytes) else { return "—" }
        return Formatters.availableOfTotal(available: UInt64(a), total: UInt64(t))
    }

    private var energyLabel: String {
        let source = state.bundle.string(.energyPowerSource) ?? "—"
        let sleep = state.bundle.int(.energyACSleepMinutes).map { Formatters.minutes($0) } ?? "—"
        return "\(source) · AC sleep \(sleep)"
    }
}

struct VitalCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .pcCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(detail)")
    }
}

struct AutopilotPill: View {
    let status: AutopilotStatus

    var body: some View {
        Text("Autopilot \(status.title)")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(pillColor.opacity(0.15))
            .foregroundStyle(pillColor)
            .clipShape(Capsule())
            .accessibilityLabel("Autopilot \(status.title)")
    }

    private var pillColor: Color {
        switch status {
        case .off: return .secondary
        case .on: return PCTheme.steady
        case .paused: return PCTheme.attention
        case .stopped: return PCTheme.act
        }
    }
}

struct FindingRow: View {
    let finding: Finding

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(PCTheme.color(for: finding.severity))
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.title)
                    .font(.headline)
                Text(finding.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(finding.severity.title): \(finding.title). \(finding.summary)")
    }
}
