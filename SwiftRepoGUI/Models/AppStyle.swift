import AppKit
import Foundation
import SwiftUI

nonisolated struct AppStyle: Codable, Equatable, Sendable {
    var fonts: FontPalette
    var colors: ColorPalette
    var gradients: GradientPalette
    var sound: SoundPalette

    static let `default` = AppStyle(
        fonts: FontPalette(
            monospaceName: "Monaco",
            lcdName: "12SegmentDisplay",
            switcherName: "Monaco",
            defaultSize: 13,
            smallSize: 11,
            titleSize: 24
        ),
        colors: ColorPalette(
            swiftOrange: StyleColor(red: 0.96, green: 0.33, blue: 0.08),
            lcdGreen: StyleColor(red: 0.56, green: 0.95, blue: 0.45),
            terminalGreen: StyleColor(red: 0.37, green: 1.0, blue: 0.33),
            terminalDimGreen: StyleColor(red: 0.11, green: 0.36, blue: 0.10),
            terminalBlack: StyleColor(red: 0.008, green: 0.018, blue: 0.012),
            failureRed: StyleColor(red: 1.0, green: 0.16, blue: 0.12),
            buttonTop: StyleColor(red: 0.10, green: 0.13, blue: 0.11),
            buttonBottom: StyleColor(red: 0.02, green: 0.03, blue: 0.025),
            logoShadow: StyleColor(red: 0, green: 0, blue: 0, opacity: 0.9),
            tabBar: StyleColor(red: 0.008, green: 0.018, blue: 0.012),
            tab: StyleColor(red: 0, green: 0, blue: 0),
            styleSwitcher: StyleColor(red: 0.02, green: 0.03, blue: 0.025),
            ledBackground: StyleColor(red: 0, green: 0, blue: 0),
            controlSurface: StyleColor(red: 0, green: 0, blue: 0),
            toggleTint: StyleColor(red: 0.37, green: 1.0, blue: 0.33),
            toggleThumb: StyleColor(red: 0.0, green: 0.8, blue: 0.0),
        ),
        gradients: GradientPalette(
            metalStops: [
                GradientStop(color: StyleColor(red: 0.060, green: 0.074, blue: 0.064), location: 0.0),
                GradientStop(color: StyleColor(red: 0.018, green: 0.030, blue: 0.022), location: 0.24),
                GradientStop(color: StyleColor(red: 0.082, green: 0.096, blue: 0.084), location: 0.46),
                GradientStop(color: StyleColor(red: 0.010, green: 0.017, blue: 0.014), location: 0.74),
                GradientStop(color: StyleColor(red: 0.045, green: 0.060, blue: 0.048), location: 1.0),
            ]
        ),
        sound: SoundPalette(
            sampleRate: 44_100,
            masterVolume: 0.45,
            loopDuration: 8,
            startupCueDuration: 2.2,
            failureCueDuration: 1.7,
            successCueDuration: 1.0,
            buildingBPM: 142,
            testingBPM: 168,
            measuringBPM: 104,
            deployingBPM: 128,
            streamBufferFrames: 65_536,
            streamPrerollFrames: 16_384,
            streamRenderChunkFrames: 8_192,
            maxRenderedTrackDuration: 600,
            trackEndTailDuration: 2,
            trackerModuleDirectory: "TrackerModules",
            trackerModuleExtensions: ["mod", "xm", "it"]
        )
    )
}

nonisolated enum SwiftBuilderStyle {
    /// The live style. Now dynamic: it reads the observable `AppStyleStore`, so changing colors/fonts
    /// (or switching to the Light preset) re-themes the whole UI. `Color.terminalGreen` &c. and the
    /// `.monaco` fonts route through here, so nothing at the call sites had to change.
    static var current: AppStyle { AppStyleStore.shared.current }
}

nonisolated struct FontPalette: Codable, Equatable, Sendable {
    var monospaceName: String
    var lcdName: String
    /// Font for the Style tab's appearance switcher.
    var switcherName: String
    var defaultSize: Double
    var smallSize: Double
    var titleSize: Double

    init(monospaceName: String, lcdName: String, switcherName: String, defaultSize: Double, smallSize: Double, titleSize: Double) {
        self.monospaceName = monospaceName
        self.lcdName = lcdName
        self.switcherName = switcherName
        self.defaultSize = defaultSize
        self.smallSize = smallSize
        self.titleSize = titleSize
    }

    // Tolerant decode: themes persisted before `switcherName` existed omit it — fall back to the dark
    // default rather than discarding the whole saved theme.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monospaceName = try c.decode(String.self, forKey: .monospaceName)
        lcdName = try c.decode(String.self, forKey: .lcdName)
        switcherName = try c.decodeIfPresent(String.self, forKey: .switcherName) ?? AppStyle.default.fonts.switcherName
        defaultSize = try c.decode(Double.self, forKey: .defaultSize)
        smallSize = try c.decode(Double.self, forKey: .smallSize)
        titleSize = try c.decode(Double.self, forKey: .titleSize)
    }
}

nonisolated struct ColorPalette: Codable, Equatable, Sendable {
    var swiftOrange: StyleColor
    var lcdGreen: StyleColor
    var terminalGreen: StyleColor
    var terminalDimGreen: StyleColor
    var terminalBlack: StyleColor
    var failureRed: StyleColor
    var buttonTop: StyleColor
    var buttonBottom: StyleColor
    /// Drop shadow behind the "SwiftBuild" wordmark.
    var logoShadow: StyleColor
    /// Background of the section tab bar strip.
    var tabBar: StyleColor
    /// Fill of the individual section tab buttons.
    var tab: StyleColor
    /// Background of the Style tab's appearance switcher.
    var styleSwitcher: StyleColor
    /// Backing panel behind the top-bar stage LEDs.
    var ledBackground: StyleColor
    /// Dark inset surface behind controls (dropdowns, the now-playing panel, text editors).
    var controlSurface: StyleColor
    /// Tint of the "on" state of settings toggles (faded for off).
    var toggleTint: StyleColor
    /// Tint of the thumb button for toggles.
    var toggleThumb: StyleColor

    init(swiftOrange: StyleColor, lcdGreen: StyleColor, terminalGreen: StyleColor, terminalDimGreen: StyleColor, terminalBlack: StyleColor, failureRed: StyleColor, buttonTop: StyleColor, buttonBottom: StyleColor, logoShadow: StyleColor, tabBar: StyleColor, tab: StyleColor, styleSwitcher: StyleColor, ledBackground: StyleColor, controlSurface: StyleColor, toggleTint: StyleColor, toggleThumb: StyleColor,) {
        self.swiftOrange = swiftOrange
        self.lcdGreen = lcdGreen
        self.terminalGreen = terminalGreen
        self.terminalDimGreen = terminalDimGreen
        self.terminalBlack = terminalBlack
        self.failureRed = failureRed
        self.buttonTop = buttonTop
        self.buttonBottom = buttonBottom
        self.logoShadow = logoShadow
        self.tabBar = tabBar
        self.tab = tab
        self.styleSwitcher = styleSwitcher
        self.ledBackground = ledBackground
        self.controlSurface = controlSurface
        self.toggleTint = toggleTint
        self.toggleThumb = toggleThumb
    }

    // Tolerant decode: themes persisted before these three colors existed omit them — fall back to the
    // dark default rather than discarding the whole saved theme.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppStyle.default.colors
        swiftOrange = try c.decode(StyleColor.self, forKey: .swiftOrange)
        lcdGreen = try c.decode(StyleColor.self, forKey: .lcdGreen)
        terminalGreen = try c.decode(StyleColor.self, forKey: .terminalGreen)
        terminalDimGreen = try c.decode(StyleColor.self, forKey: .terminalDimGreen)
        terminalBlack = try c.decode(StyleColor.self, forKey: .terminalBlack)
        failureRed = try c.decode(StyleColor.self, forKey: .failureRed)
        buttonTop = try c.decode(StyleColor.self, forKey: .buttonTop)
        buttonBottom = try c.decode(StyleColor.self, forKey: .buttonBottom)
        logoShadow = try c.decodeIfPresent(StyleColor.self, forKey: .logoShadow) ?? fallback.logoShadow
        tabBar = try c.decodeIfPresent(StyleColor.self, forKey: .tabBar) ?? fallback.tabBar
        tab = try c.decodeIfPresent(StyleColor.self, forKey: .tab) ?? fallback.tab
        styleSwitcher = try c.decodeIfPresent(StyleColor.self, forKey: .styleSwitcher) ?? fallback.styleSwitcher
        ledBackground = try c.decodeIfPresent(StyleColor.self, forKey: .ledBackground) ?? fallback.ledBackground
        controlSurface = try c.decodeIfPresent(StyleColor.self, forKey: .controlSurface) ?? fallback.controlSurface
        toggleTint = try c.decodeIfPresent(StyleColor.self, forKey: .toggleTint) ?? fallback.toggleTint
        toggleThumb = try c.decodeIfPresent(StyleColor.self, forKey: .toggleThumb) ?? fallback.toggleThumb
    }
}

nonisolated struct GradientPalette: Codable, Equatable, Sendable {
    var metalStops: [GradientStop]
}

nonisolated struct GradientStop: Codable, Equatable, Sendable {
    var color: StyleColor
    var location: Double
}

nonisolated struct SoundPalette: Codable, Equatable, Sendable {
    var sampleRate: Double
    var masterVolume: Float
    var loopDuration: Double
    var startupCueDuration: Double
    var failureCueDuration: Double
    var successCueDuration: Double
    var buildingBPM: Double
    var testingBPM: Double
    var measuringBPM: Double
    var deployingBPM: Double
    var streamBufferFrames: Int
    var streamPrerollFrames: Int
    var streamRenderChunkFrames: Int
    var maxRenderedTrackDuration: Double
    var trackEndTailDuration: Double
    var trackerModuleDirectory: String
    var trackerModuleExtensions: [String]
}

nonisolated struct StyleColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
}

extension Color {
    init(_ styleColor: StyleColor) {
        self.init(
            red: styleColor.red,
            green: styleColor.green,
            blue: styleColor.blue,
            opacity: styleColor.opacity
        )
    }
}

extension StyleColor {
    /// Build a `StyleColor` from a SwiftUI `Color` (what `ColorPicker` produces), via sRGB.
    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        self.init(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent),
            opacity: Double(resolved.alphaComponent)
        )
    }

    nonisolated static func random() -> StyleColor {
        StyleColor(red: .random(in: 0...1), green: .random(in: 0...1), blue: .random(in: 0...1))
    }
}

extension ColorPalette {
    /// A fully random palette — deliberately unconstrained (the "Randomize Colors" button).
    nonisolated static func randomized() -> ColorPalette {
        ColorPalette(
            swiftOrange: .random(),
            lcdGreen: .random(),
            terminalGreen: .random(),
            terminalDimGreen: .random(),
            terminalBlack: .random(),
            failureRed: .random(),
            buttonTop: .random(),
            buttonBottom: .random(),
            logoShadow: .random(),
            tabBar: .random(),
            tab: .random(),
            styleSwitcher: .random(),
            ledBackground: .random(),
            controlSurface: .random(),
            toggleTint: .random(),
            toggleThumb: .random(),
        )
    }
}

extension GradientPalette {
    /// Randomize each metal stop's color while keeping the stop positions.
    nonisolated func randomized() -> GradientPalette {
        GradientPalette(metalStops: metalStops.map { GradientStop(color: .random(), location: $0.location) })
    }
}

extension AppStyle {
    /// A Light-mode starting point: ink-on-paper instead of green-on-black, with the same accent
    /// structure. Sane defaults meant to be tuned in the Style tab.
    nonisolated static let lightPreset = AppStyle(
        fonts: AppStyle.default.fonts,
        colors: ColorPalette(
            swiftOrange: StyleColor(red: 0.90, green: 0.35, blue: 0.06),
            lcdGreen: StyleColor(red: 0.15, green: 0.50, blue: 0.18),
            terminalGreen: StyleColor(red: 0.09, green: 0.42, blue: 0.13),
            terminalDimGreen: StyleColor(red: 0.34, green: 0.52, blue: 0.36),
            terminalBlack: StyleColor(red: 0.93, green: 0.92, blue: 0.88),
            failureRed: StyleColor(red: 0.78, green: 0.10, blue: 0.08),
            buttonTop: StyleColor(red: 0.97, green: 0.97, blue: 0.94),
            buttonBottom: StyleColor(red: 0.85, green: 0.85, blue: 0.82),
            logoShadow: StyleColor(red: 0.55, green: 0.55, blue: 0.50, opacity: 0.6),
            tabBar: StyleColor(red: 0.88, green: 0.87, blue: 0.83),
            tab: StyleColor(red: 0.99, green: 0.99, blue: 0.97),
            styleSwitcher: StyleColor(red: 0.82, green: 0.82, blue: 0.78),
            ledBackground: StyleColor(red: 0.12, green: 0.12, blue: 0.11),
            controlSurface: StyleColor(red: 0.74, green: 0.74, blue: 0.70),
            toggleTint: StyleColor(red: 0.09, green: 0.42, blue: 0.13),
            toggleThumb: StyleColor(red: 0.5, green: 0.5, blue: 0.5)
        ),
        gradients: GradientPalette(
            metalStops: [
                GradientStop(color: StyleColor(red: 0.91, green: 0.91, blue: 0.89), location: 0.0),
                GradientStop(color: StyleColor(red: 0.83, green: 0.83, blue: 0.81), location: 0.24),
                GradientStop(color: StyleColor(red: 0.95, green: 0.95, blue: 0.93), location: 0.46),
                GradientStop(color: StyleColor(red: 0.80, green: 0.80, blue: 0.78), location: 0.74),
                GradientStop(color: StyleColor(red: 0.89, green: 0.89, blue: 0.87), location: 1.0),
            ]
        ),
        sound: AppStyle.default.sound
    )
}
