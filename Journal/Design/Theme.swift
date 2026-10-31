import SwiftUI
import UIKit

/// Raw palette — https://colorhunt.co/palette/3434348e8b82e9dcbef3f3f3
/// plus `night`, a deeper canvas for dark mode. Views use the semantic tokens below.
nonisolated enum Palette {
    static let ink: UInt32 = 0x343434
    static let stone: UInt32 = 0x8E8B82
    static let sand: UInt32 = 0xD4B48C
    static let paper: UInt32 = 0xF3F3F3
    /// Dark-mode background: near-black, a shade deeper than ink.
    static let night: UInt32 = 0x121212
}

/// Semantic colors for UIKit (the Markdown text view, navigation bar, lock window).
enum UITheme {
    static let background = UIColor(light: Palette.paper, dark: Palette.night)
    static let primaryText = UIColor(light: Palette.ink, dark: Palette.paper)
    static let secondaryText = UIColor(hex: Palette.stone)
    static let accent = UIColor(hex: Palette.sand)
    /// Quiet fill: a wash of sand on paper, a lift of stone on night.
    static let surface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: Palette.stone).withAlphaComponent(0.14)
            : UIColor(hex: Palette.sand).withAlphaComponent(0.45)
    }
}

/// Semantic colors. Light mode is ink on paper; dark mode is paper on night.
/// Sand is the single accent, used for fills (buttons, highlights) with white on top.
enum Theme {
    static let background = Color(uiColor: UITheme.background)
    static let primaryText = Color(uiColor: UITheme.primaryText)
    static let secondaryText = Color(uiColor: UITheme.secondaryText)
    static let accent = Color(uiColor: UITheme.accent)
    static let onAccent = Color.white
    /// Fill for delete swipe actions: the app-wide tint (primary text) would make them near-white in
    /// dark mode, hiding their white icon.
    static let destructive = Color.red
    static let hairline = Color(uiColor: UITheme.secondaryText).opacity(0.25)
    static let surface = Color(uiColor: UITheme.surface)

    /// Activity heatmap: a day was written or it wasn't.
    static let activityFilled = primaryText.opacity(0.8)
    static let activityEmpty = primaryText.opacity(0.07)

    /// Bar titles (sheets: Settings, Set Location, Entry Date) are sans, like nearly everything else.
    static func applyNavigationBarAppearance() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: UIFont.sans(.largeTitle, bold: true),
            .foregroundColor: UITheme.primaryText,
        ]
        bar.titleTextAttributes = [
            .font: UIFont.sans(.headline, bold: true),
            .foregroundColor: UITheme.primaryText,
        ]
    }
}

enum Typography {
    /// Everything is sans but the journal's name (`LargePageTitle`, the lock screen), the day numbers
    /// in entry lists and the Insights tiles' numbers.
    static let entryTitle = Font.system(.title3).weight(.semibold)
    static let entryExcerpt = Font.system(.subheadline)
    /// Empty-state and explanatory notes ("Nothing written on this day.").
    static let note = Font.system(.footnote)
    static let dayNumber = Font.system(.title2, design: .serif)
    /// Small uppercase labels (dates, section headers). Pair with `.tracking(Typography.metaTracking)`.
    static let meta = Font.system(.caption2).weight(.semibold)
    static let metaTracking: CGFloat = 1.2
    static let bodyLineSpacing: CGFloat = 6
}

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    /// Horizontal margin for reading/writing surfaces.
    static let page: CGFloat = 24
}

extension Color {
    nonisolated init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor(light: light, dark: dark))
    }
}

extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    nonisolated convenience init(light: UInt32, dark: UInt32) {
        self.init { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }
}

extension UIFont {
    static func sans(_ style: UIFont.TextStyle, bold: Bool = false) -> UIFont {
        var descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        if bold {
            descriptor = descriptor.withSymbolicTraits(.traitBold) ?? descriptor
        }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
