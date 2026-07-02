import Foundation
import SwiftUI

// TODO: Make this user-customizable from Settings and persist chosen style profiles.
nonisolated struct AppStyle: Codable, Equatable, Sendable {
    var fonts: FontPalette
    var colors: ColorPalette
    var gradients: GradientPalette
    var sound: SoundPalette

    static let `default` = AppStyle(
        fonts: FontPalette(
            monospaceName: "Monaco",
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
            buttonBottom: StyleColor(red: 0.02, green: 0.03, blue: 0.025)
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
            trackerModuleDirectory: "TrackerModules",
            trackerModuleExtensions: ["mod", "xm", "it"]
        )
    )
}

nonisolated enum SwiftBuilderStyle {
    static let current = AppStyle.default
}

nonisolated struct FontPalette: Codable, Equatable, Sendable {
    var monospaceName: String
    var defaultSize: Double
    var smallSize: Double
    var titleSize: Double
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
