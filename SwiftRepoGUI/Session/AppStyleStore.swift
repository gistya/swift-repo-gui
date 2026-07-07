import Foundation
import Observation
import SwiftUI

/// Which appearance the Style tab is previewing/editing.
nonisolated enum StylePreview: String, CaseIterable, Identifiable, Sendable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "Follow System")
        case .dark: String(localized: "Dark")
        case .light: String(localized: "Light")
        }
    }
}

/// The live, editable app theme.
///
/// Holds a Dark style and a Light style; `current` picks one based on the OS appearance (fed in from
/// the view layer) so Light mode auto-applies. `SwiftBuilderStyle.current`, `Color.terminalGreen`,
/// and the `.monaco` fonts all read `current`, so mutating a style here re-themes the whole UI live.
/// Mutations happen on the main actor (the Style tab / appearance changes); `@unchecked Sendable`
/// lets it be a global read from anywhere.
@Observable
nonisolated final class AppStyleStore: @unchecked Sendable {
    static let shared = AppStyleStore()

    private enum Keys {
        static let dark = "appStyle.dark"
        static let light = "appStyle.light"
        static let preview = "appStyle.preview"
    }

    var darkStyle: AppStyle { didSet { persist(darkStyle, key: Keys.dark) } }
    var lightStyle: AppStyle { didSet { persist(lightStyle, key: Keys.light) } }

    /// Whether the OS is currently in Light appearance (set from the view layer's `colorScheme`).
    var systemIsLight: Bool = false

    /// The chosen appearance (Follow System / Dark / Light). Restored on launch and re-persisted on
    /// every change so the choice survives a restart. The `AppearanceMachine` in `AppSession` is the
    /// statechart mirror of this; all mutations funnel through `AppSession.selectAppearance`.
    var preview: StylePreview { didSet { defaults.set(preview.rawValue, forKey: Keys.preview) } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // didSet doesn't fire for these initial assignments, so nothing persists until an edit.
        darkStyle = Self.load(key: Keys.dark, from: defaults) ?? .default
        lightStyle = Self.load(key: Keys.light, from: defaults) ?? .lightPreset
        preview = (defaults.string(forKey: Keys.preview)).flatMap(StylePreview.init(rawValue:)) ?? .system
    }

    /// The appearance shown right now.
    var effectiveLight: Bool {
        switch preview {
        case .system: systemIsLight
        case .light: true
        case .dark: false
        }
    }

    /// The style the whole app renders with.
    var current: AppStyle { effectiveLight ? lightStyle : darkStyle }

    /// The style the Style tab edits — whichever appearance is currently previewed.
    var activeStyle: AppStyle {
        get { effectiveLight ? lightStyle : darkStyle }
        set {
            if effectiveLight { lightStyle = newValue } else { darkStyle = newValue }
        }
    }

    /// Randomize every color (palette + brushed-metal gradient) of the active appearance.
    func randomizeActiveColors() {
        var style = activeStyle
        style.colors = .randomized()
        style.gradients = style.gradients.randomized()
        activeStyle = style
    }

    /// Reset the active appearance to its built-in preset (Light → `lightPreset`, Dark → `default`).
    func resetActiveToPreset() {
        activeStyle = effectiveLight ? .lightPreset : .default
    }

    private func persist(_ style: AppStyle, key: String) {
        if let data = try? JSONEncoder().encode(style) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load(key: String, from defaults: UserDefaults) -> AppStyle? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppStyle.self, from: data)
    }
}
