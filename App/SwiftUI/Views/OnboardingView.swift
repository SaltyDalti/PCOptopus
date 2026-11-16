import SwiftUI
import Model

struct OnboardingView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "octopus.fill")
                .font(.system(size: 48))
                .foregroundStyle(PCTheme.accent)
                .accessibilityHidden(true)

            switch state.onboardingStep {
            case 1:
                step(
                    title: "This is your Mac",
                    body: "\(state.identity.name) · \(state.identity.chip) · \(state.identity.memoryGigabytesLabel). PCOptopus watches this machine only."
                ) {
                    state.onboardingStep = 2
                    state.refreshSlow()
                    state.refreshMedium()
                }
            case 2:
                VStack(spacing: 12) {
                    Text("Baseline read")
                        .font(.title.weight(.semibold))
                    ForEach(Domain.allCases) { domain in
                        HStack {
                            Image(systemName: state.findings.contains(where: { $0.domain == domain }) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(PCTheme.steady)
                            Text(domain.title)
                            Spacer()
                        }
                    }
                    .frame(maxWidth: 360)
                    Button("Continue") { state.onboardingStep = 3 }
                        .buttonStyle(.borderedProminent)
                }
            case 3:
                VStack(alignment: .leading, spacing: 12) {
                    Text("Lead findings")
                        .font(.title.weight(.semibold))
                    ForEach(state.leadFindings().prefix(3)) { finding in
                        FindingRow(finding: finding)
                    }
                    if state.leadFindings().isEmpty {
                        Text("No attention items yet — measurements are still settling.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Review contract") { state.onboardingStep = 4 }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: 560)
            default:
                VStack(alignment: .leading, spacing: 12) {
                    Text("Contract starts empty")
                        .font(.title.weight(.semibold))
                    Text("Nothing granted, so nothing will change. You can enable AC sleep and other autopilot keys later.")
                        .foregroundStyle(.secondary)
                    Button("Open Today") {
                        state.completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: 480)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(title: String, body: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.title.weight(.semibold))
            Text(body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480)
            Button("Continue", action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}
