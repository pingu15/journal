import SwiftUI
import UIKit

/// Raw palette — https://colorhunt.co/palette/3434348e8b82e9dcbef3f3f3
/// plus `night`, a deeper canvas for dark mode. Views use the semantic tokens below.
nonisolated enum Palette {
    static let ink: UInt32 = 0x343434
    static let stone: UInt32 = 0x8E8B82
    static let sand: UInt32 = 0xDEAA73
    static let paper: UInt32 = 0xF3F3F3
    /// Dark-mode background: near-black, a shade deeper than ink.
    static let night: UInt32 = 0x121212
}

/// Semantic colors for UIKit (the Markdown text view, navigation bar, lock window).
enum UITheme {
    /// The map's current-location dot: Apple Maps' blue, outside the palette so it reads as the system's.
    static let userLocation = UIColor.systemBlue
    static let background = UIColor(light: Palette.paper, dark: Palette.night)
    static let primaryText = UIColor(light: Palette.ink, dark: Palette.paper)
    static let secondaryText = UIColor(hex: Palette.stone)
    static let accent = UIColor(hex: Palette.sand)
    /// Quiet fill (photos still loading, inline code): a wash of stone on paper, a lift of stone on
    /// night — never sand.
    static let surface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: Palette.stone).withAlphaComponent(0.14)
            : UIColor(hex: Palette.stone).withAlphaComponent(0.15)
    }
    /// Cards standing on the page (the onboarding's): white on paper, a lift of stone on night.
    static let card = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(hex: Palette.stone).withAlphaComponent(0.14)
            : .white
    }
    /// Over the page's card behind a sheet, on top of the system's dimming (`SheetBackdrop`).
    static let sheetBackdrop = UIColor.black.withAlphaComponent(0.5)
}

/// Semantic colors. Light mode is ink on paper; dark mode is paper on night.
/// Sand is the single accent, used for fills (buttons, highlights) with white on top.
enum Theme {
    static let background = Color(uiColor: UITheme.background)
    static let primaryText = Color(uiColor: UITheme.primaryText)
    static let secondaryText = Color(uiColor: UITheme.secondaryText)
    static let accent = Color(uiColor: UITheme.accent)
    static let onAccent = Color.white
    /// The one exception to white on sand: a written day's number in the Calendar, ink in light mode
    /// (white was faint on sand there), white in dark.
    static let calendarWrittenDay = Color(light: Palette.ink, dark: 0xFFFFFF)
    /// The outline round the day last opened in the Calendar (today until one is): ink in light
    /// mode, white in dark.
    static let calendarSelected = Color(light: Palette.ink, dark: 0xFFFFFF)
    /// Fill for delete swipe actions: the app-wide tint (primary text) would make them near-white in
    /// dark mode, hiding their white icon.
    static let destructive = Color.red
    static let hairline = Color(uiColor: UITheme.secondaryText).opacity(0.25)
    static let surface = Color(uiColor: UITheme.surface)
    /// A touched or swiped entry row: a wash of stone in both modes, never sand.
    static let rowHighlight = Color(uiColor: UITheme.secondaryText).opacity(0.15)
    static let card = Color(uiColor: UITheme.card)

    /// Activity heatmap: a day was written or it wasn't.
    static let activityFilled = primaryText.opacity(0.8)
    static let activityEmpty = primaryText.opacity(0.07)

    /// Bar titles (sheets: Settings, Set Location, Entry Date) keep the system's size.
    static func applyNavigationBarAppearance() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: UIFont.sans(.largeTitle, bold: true),
            .foregroundColor: UITheme.primaryText,
        ]
        bar.titleTextAttributes = [.foregroundColor: UITheme.primaryText]
    }
}

/// The app's type scale. Views take their fonts from here, never a size or style of their own, so
/// the same role reads the same everywhere. All of it follows Dynamic Type but the Insights numbers,
/// which are fixed and shrink to fit their tiles.
enum Typography {
    // Titles. Everything is sans but the page titles, the day numbers in entry lists and the Insights
    // tiles' numbers.
    static let pageTitle = Font.system(.largeTitle, design: .serif).weight(.bold)
    /// Popup titles (not sheets' bars, which keep the system's) and empty states.
    static let title = Font.system(.title2).weight(.bold)
    static let entryTitle = Font.system(.title3).weight(.semibold)
    /// The first-launch introduction's page titles: large, but sans, as they aren't page titles.
    static let onboardingTitle = Font.system(.title).weight(.bold)
    /// An option's name in the introduction, over its line in `note`.
    static let rowTitle = Font.system(.body).weight(.semibold)

    // Text.
    static let body = Font.system(.body)
    /// Buttons, and the small icons in rows and bars.
    static let action = Font.system(.body).weight(.medium)
    /// Secondary lines: the editor's date and place, list excerpts.
    static let detail = Font.system(.subheadline)
    static let entryExcerpt = detail
    /// Empty-state and explanatory notes ("Nothing written on this day.").
    static let note = Font.system(.footnote)
    /// An entry's time and place under its text; the words under a row's swipe buttons.
    static let caption = Font.system(.caption)
    /// Small uppercase labels (dates, section headers). Pair with `.tracking(Typography.metaTracking)`.
    static let meta = Font.system(.caption2).weight(.semibold)
    static let metaTracking: CGFloat = 1.2
    static let bodyLineSpacing: CGFloat = 6

    // Icons standing on their own.
    /// In a row's swipe buttons.
    static let smallIcon = Font.system(.subheadline).weight(.medium)
    static let icon = Font.system(.title2)

    // Numbers.
    static let dayNumber = Font.system(.title2, design: .serif)
    /// The date over a photo in Media: its day, with the month and year below (`mediaMonth`).
    static let mediaDay = Font.system(.largeTitle).weight(.bold)
    static let mediaMonth = Font.system(.caption).weight(.semibold)
    static let calendarDay = Font.system(.callout).weight(.semibold)
    static let statNumber = Font.system(size: 40, weight: .regular, design: .serif)
    static let largeStatNumber = Font.system(size: 52, weight: .regular, design: .serif)
    /// The Insights crest's streak ("12 Days"), sans like everything but the page titles.
    static let crestNumber = Font.system(size: 52, weight: .black)
    /// The crest's name over the number: "TODAY" bold, "JOURNAL" thin, very widely spaced.
    static let crestNameLight = Font.system(.subheadline).weight(.thin)
    static let crestNameBold = Font.system(.subheadline).weight(.bold)
    static let crestNameTracking: CGFloat = 6
}

enum Radius {
    /// Cards: Insights' tiles, the day sheet's sections, Set Location's map.
    static let card: CGFloat = 16
    /// The top of a page's card.
    static let page: CGFloat = 28
    /// Entry rows: their highlight.
    static let row: CGFloat = 12
}

nonisolated enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    /// Horizontal margin for reading/writing surfaces.
    static let page: CGFloat = 24
    /// How far in from the screen's edges a page's lists and grids sit: the journal's rows and
    /// labels, the Calendar's days, the Insights tiles, a popup's content.
    static let content: CGFloat = 20
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
