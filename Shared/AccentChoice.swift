import Foundation

/// The app's single accent, chosen in Settings → Appearance. Sand by default. Each is a muted mid
/// tone like sand, so white still reads on top of it and the palette stays restrained.
///
/// Kept in the App Group's defaults, which the widget extension reads too (the `Shared` folder).
nonisolated enum AccentChoice: String, CaseIterable, Identifiable, Sendable {
    static let storageKey = "accentColor"

    case sand, clay, rose, sage, sky, lilac, ash

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sand: "Sand"
        case .clay: "Clay"
        case .rose: "Rose"
        case .sage: "Sage"
        case .sky: "Sky"
        case .lilac: "Lilac"
        case .ash: "Ash"
        }
    }

    var hex: UInt32 {
        switch self {
        case .sand: 0xDEAA73
        case .clay: 0xC98B6B
        case .rose: 0xD69A9E
        case .sage: 0x98AE8E
        case .sky: 0x88A8C8
        case .lilac: 0xA99BCB
        // Warm like stone, a step lighter so it isn't the meta text's grey.
        case .ash: 0xA3A09A
        }
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: WidgetSnapshot.appGroup) ?? .standard }

    static var current: AccentChoice {
        defaults.string(forKey: storageKey).flatMap(AccentChoice.init(rawValue:)) ?? .sand
    }

    func save() {
        Self.defaults.set(rawValue, forKey: Self.storageKey)
    }
}
