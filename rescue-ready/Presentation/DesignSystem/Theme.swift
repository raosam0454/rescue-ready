import SwiftUI

/// Shared spacing, shapes and semantic colours.
///
/// Colours come from system or asset-catalogue colours, so every screen adapts to
/// Light Mode, Dark Mode and Increase Contrast automatically. Never hard-code
/// `.white` or `.black` for backgrounds or text.
enum Theme {
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }

    /// Corner radius for cards and buttons.
    static let cornerRadius: CGFloat = 12

    /// Apple's minimum touch target.
    static let minimumTouchTarget: CGFloat = 44
}

extension Color {
    /// Screen background behind cards.
    static let screenBackground = Color(uiColor: .systemGroupedBackground)
    /// Card surface that sits on `screenBackground`.
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)

    // Status colours. Always pair with an icon or text, never colour alone.
    static let statusSuccess = Color.green
    static let statusWarning = Color.orange
    static let statusDanger = Color.red
    static let statusInfo = Color.blue
}

/// Rounded card used for grouped content on dashboards.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

extension View {
    /// Places the view on a rounded card surface.
    func card() -> some View {
        modifier(CardModifier())
    }
}
