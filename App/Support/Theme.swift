import SwiftUI

/// Centralized design tokens so spacing, corner radius, and card styling are
/// consistent across every screen instead of scattered magic numbers.
enum Theme {
    /// Spacing scale (4-pt grid).
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// Corner radii used for cards, buttons, and pills.
    enum Radius {
        static let card: CGFloat = 14
        static let control: CGFloat = 10
    }
}

extension View {
    /// Standard card surface used across dashboard sections.
    func cardStyle() -> some View {
        self
            .padding(Theme.Spacing.lg)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    /// Applies the iOS 26 / macOS Tahoe prominent glass button style where
    /// available, gracefully falling back to `.borderedProminent` elsewhere.
    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(iOS 26, macOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Secondary glass button style with a bordered fallback.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(iOS 26, macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
