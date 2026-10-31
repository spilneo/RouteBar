import AppKit
import Observation
import SwiftUI

/// How the panel looks: the accent colour and whether the panel is translucent.
///
/// A shared object because `Theme.accent` is read from every view. SwiftUI
/// tracks those reads, so changing the accent restyles the panel at once.
@MainActor
@Observable
final class Appearance {
    /// Flat accent presets. Indigo is the brand colour of the app icon (`logo.svg`).
    enum Accent: String, CaseIterable, Identifiable {
        case indigo, blue, teal, green, orange, pink, red, graphite

        var id: String { rawValue }
        var name: String { rawValue.capitalized }

        var color: Color {
            switch self {
            case .indigo: Color(red: 0x5e / 255, green: 0x5c / 255, blue: 0xe6 / 255)
            case .blue: Color(red: 0x0a / 255, green: 0x84 / 255, blue: 0xff / 255)
            case .teal: Color(red: 0x14 / 255, green: 0xa3 / 255, blue: 0xb8 / 255)
            case .green: Color(red: 0x2f / 255, green: 0xa8 / 255, blue: 0x4f / 255)
            case .orange: Color(red: 0xf0 / 255, green: 0x7f / 255, blue: 0x1a / 255)
            case .pink: Color(red: 0xe6 / 255, green: 0x45 / 255, blue: 0x8f / 255)
            case .red: Color(red: 0xe0 / 255, green: 0x3e / 255, blue: 0x3e / 255)
            case .graphite: Color(red: 0x6e / 255, green: 0x6e / 255, blue: 0x78 / 255)
            }
        }
    }

    static let shared = Appearance()

    private enum Keys {
        static let accent = "accentColor"
        static let translucent = "translucentPanel"
    }

    private let defaults: UserDefaults

    var accent: Accent {
        didSet { defaults.set(accent.rawValue, forKey: Keys.accent) }
    }

    /// On: the standard frosted menu bar panel. Off: a solid window background.
    var isTranslucent: Bool {
        didSet { defaults.set(isTranslucent, forKey: Keys.translucent) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.translucent: true])
        accent = defaults.string(forKey: Keys.accent).flatMap(Accent.init(rawValue:)) ?? .indigo
        isTranslucent = defaults.bool(forKey: Keys.translucent)
    }
}
