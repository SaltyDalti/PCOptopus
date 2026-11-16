import SwiftUI
import Model

enum PCTheme {
    static let accent = Color(red: 0.22, green: 0.48, blue: 0.78)
    static let steady = Color(red: 0.20, green: 0.55, blue: 0.40)
    static let attention = Color(red: 0.85, green: 0.55, blue: 0.15)
    static let act = Color(red: 0.78, green: 0.28, blue: 0.25)
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)

    static func color(for severity: Severity) -> Color {
        switch severity {
        case .steady: return steady
        case .attention: return attention
        case .act: return act
        }
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PCTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    func pcCard() -> some View {
        modifier(CardModifier())
    }
}
