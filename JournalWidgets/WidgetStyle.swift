import SwiftUI
import UIKit

/// The app's palette and type for the widgets (the extension can't reach `Theme`, which also sets up
/// the app's bars): the same tokens, by role.
enum WidgetStyle {
    private static func color(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let background = color(light: 0xF3F3F3, dark: 0x121212)
    static let primaryText = color(light: 0x343434, dark: 0xF3F3F3)
    static let secondaryText = Color(uiColor: UIColor(hex: 0x8E8B82))
    static let accent = Color(uiColor: UIColor(hex: 0xDEAA73))
    static let hairline = secondaryText.opacity(0.25)
    static let activityFilled = primaryText.opacity(0.8)
    static let activityEmpty = primaryText.opacity(0.08)

    static let meta = Font.system(.caption2).weight(.semibold)
    static let metaTracking: CGFloat = 1.2
    static let note = Font.system(.footnote)
    static let body = Font.system(.subheadline)
    static let rowTitle = Font.system(.subheadline).weight(.semibold)
    static let bigNumber = Font.system(size: 52, weight: .black)
    static let dayNumber = Font.system(size: 46, weight: .bold)
    static let mediaDay = Font.system(size: 34, weight: .bold)
    static let mediaMonth = Font.system(.caption).weight(.semibold)
}

/// A small spaced-out uppercase label, as the app's `MetaLabel`.
struct WidgetLabel: View {
    let text: String
    var systemImage: String?
    var color = WidgetStyle.secondaryText

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text.uppercased())
                .tracking(WidgetStyle.metaTracking)
                .lineLimit(1)
        }
        .font(WidgetStyle.meta)
        .foregroundStyle(color)
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
}
