import SwiftUI
import Model

struct DomainsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            List {
                ForEach(Domain.allCases) { domain in
                    NavigationLink {
                        DomainDetailView(domain: domain)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(domain.title)
                                    .font(.headline)
                                Text(domainSummary(domain))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if let finding = state.findings.first(where: { $0.domain == domain }) {
                                Text(finding.severity.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PCTheme.color(for: finding.severity))
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("Domains")
        }
    }

    private func domainSummary(_ domain: Domain) -> String {
        if let finding = state.findings.first(where: { $0.domain == domain }) {
            return finding.summary
        }
        return domain.whatGoodLooksLike
    }
}

struct DomainDetailView: View {
    @EnvironmentObject private var state: AppState
    let domain: Domain

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(domain.title)
                    .font(.largeTitle.weight(.semibold))
                Text(domain.whatGoodLooksLike)
                    .foregroundStyle(.secondary)

                if let finding = state.findings.first(where: { $0.domain == domain }) {
                    FindingRow(finding: finding)
                        .pcCard()
                    ForEach(finding.evidence, id: \.self) { line in
                        Text(line)
                            .font(.system(.body, design: .monospaced))
                    }
                    .pcCard()

                    let actions = finding.actionIDs.compactMap { ActionCatalog.definition(id: $0) }
                    actionSection("Can run on its own", actions.filter { $0.risk == .autopilot }, finding)
                    actionSection("Asks you", actions.filter { $0.risk == .confirm }, finding)
                    actionSection("For you to do by hand", actions.filter { $0.risk == .manual }, finding)
                }

                if domain == .storage {
                    Button(state.isScanningFolders ? "Scanning…" : "Scan large folders") {
                        state.scanLargeFolders()
                    }
                    .disabled(state.isScanningFolders)
                    .buttonStyle(.borderedProminent)

                    ForEach(state.largeFolders) { entry in
                        HStack {
                            Text(entry.path)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Text(Formatters.bytes(entry.bytes))
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func actionSection(_ title: String, _ actions: [ActionDefinition], _ finding: Finding) -> some View {
        if !actions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                ForEach(actions) { action in
                    NavigationLink {
                        ActionDetailView(finding: finding, actionID: action.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(action.title)
                            Text(action.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .pcCard()
        }
    }
}
