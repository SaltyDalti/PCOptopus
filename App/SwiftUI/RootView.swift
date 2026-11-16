import SwiftUI
import Model
import AppKit

enum SidebarItem: String, CaseIterable, Identifiable {
    case today, machine, domains, contract, journal, week, ask, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .machine: return "Machine"
        case .domains: return "Domains"
        case .contract: return "Contract"
        case .journal: return "Journal"
        case .week: return "Week"
        case .ask: return "Ask"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max"
        case .machine: return "laptopcomputer"
        case .domains: return "square.grid.2x2"
        case .contract: return "checkmark.shield"
        case .journal: return "list.bullet.rectangle"
        case .week: return "calendar"
        case .ask: return "text.bubble"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var selection: SidebarItem = .today

    var body: some View {
        Group {
            if state.onboardingStep > 0 && !state.settings.hasCompletedOnboarding {
                OnboardingView()
            } else {
                NavigationSplitView {
                    List(SidebarItem.allCases, selection: $selection) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                            .accessibilityLabel(item.title)
                    }
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                    .listStyle(.sidebar)
                } detail: {
                    switch selection {
                    case .today: TodayView()
                    case .machine: MachineView()
                    case .domains: DomainsView()
                    case .contract: ContractView()
                    case .journal: JournalView()
                    case .week: WeekView()
                    case .ask: AskView()
                    case .settings: SettingsView()
                    }
                }
            }
        }
        .tint(PCTheme.accent)
    }
}
