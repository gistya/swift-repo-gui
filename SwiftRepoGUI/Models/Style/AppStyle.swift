import AppKit
import Foundation
import SwiftRepoCore

nonisolated struct AppStyle: Codable, Equatable, Sendable {
    var fonts: FontPalette
    var colors: ColorPalette
    var gradients: GradientPalette

    static let `default` = darkPreset
    
    nonisolated static let darkPreset = AppStyle(
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
            lcdText: StyleColor(red: 0, green: 0, blue: 0, opacity: 1.0),
            lcdTextShadow: StyleColor(red: 0, green: 0, blue: 0, opacity: 0.45),
            lcdTextSecondary: StyleColor(red: 0, green: 0, blue: 0, opacity: 0.3)
        ),
        gradients: GradientPalette(
            metalStops: [
                GradientStop(color: StyleColor(red: 0.060, green: 0.074, blue: 0.064), location: 0.0),
                GradientStop(color: StyleColor(red: 0.018, green: 0.030, blue: 0.022), location: 0.24),
                GradientStop(color: StyleColor(red: 0.082, green: 0.096, blue: 0.084), location: 0.46),
                GradientStop(color: StyleColor(red: 0.010, green: 0.017, blue: 0.014), location: 0.74),
                GradientStop(color: StyleColor(red: 0.045, green: 0.060, blue: 0.048), location: 1.0),
            ],
            lcdStops: [
                GradientStop(color: StyleColor(red: 0.48, green: 0.51, blue: 0.47), location: 0.0),
                GradientStop(color: StyleColor(red: 0.64, green: 0.67, blue: 0.60), location: 0.5),
                GradientStop(color: StyleColor(red: 0.39, green: 0.42, blue: 0.38), location: 1.0),
            ]
        )
    )

    /// A Light-mode starting point. Tuned in the app's Style tab and baked in from those settings.
    nonisolated static let lightPreset = AppStyle(
        fonts: FontPalette(
            monospaceName: "Monaco",
            lcdName: "12 Segment Display",
            switcherName: "Monaco",
            defaultSize: 12,
            smallSize: 12,
            titleSize: 24
        ),
        colors: ColorPalette(
            swiftOrange: StyleColor(red: 0.983, green: 0.607, blue: 0.0),
            lcdGreen: StyleColor(red: 1.0, green: 1.0, blue: 1.0),
            terminalGreen: StyleColor(red: 0.0, green: 0.0, blue: 0.0),
            terminalDimGreen: StyleColor(red: 0.795, green: 0.795, blue: 0.795),
            terminalBlack: StyleColor(red: 1.0, green: 1.0, blue: 1.0),
            failureRed: StyleColor(red: 1.0, green: 0.072, blue: 0.102),
            buttonTop: StyleColor(red: 1.0, green: 1.0, blue: 1.0),
            buttonBottom: StyleColor(red: 0.795, green: 0.795, blue: 0.795),
            logoShadow: StyleColor(red: 1.0, green: 1.0, blue: 1.0),
            tabBar: StyleColor(red: 1.0, green: 1.0, blue: 1.0),
            tab: StyleColor(red: 1.0, green: 1.0, blue: 1.0),
            styleSwitcher: StyleColor(red: 1.0, green: 1.0, blue: 1.0),
            ledBackground: StyleColor(red: 0.552, green: 0.552, blue: 0.552),
            controlSurface: StyleColor(red: 0.437, green: 0.437, blue: 0.437),
            toggleTint: StyleColor(red: 0.0, green: 0.0, blue: 0.0),
            toggleThumb: StyleColor(red: 1.0, green: 1.0, blue: 1.0),
            lcdText: StyleColor(red: 0.0, green: 0.0, blue: 0.0, opacity: 1.0),
            lcdTextShadow: StyleColor(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.45),
            lcdTextSecondary: StyleColor(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.3)
        ),
        gradients: GradientPalette(
            metalStops: [
                GradientStop(color: StyleColor(red: 1.0, green: 1.0, blue: 1.0), location: 0.0),
                GradientStop(color: StyleColor(red: 0.75, green: 0.75, blue: 0.75), location: 0.24),
                GradientStop(color: StyleColor(red: 0.5, green: 0.5, blue: 0.5), location: 0.46),
                GradientStop(color: StyleColor(red: 1.0, green: 1.0, blue: 1.0), location: 0.74),
                GradientStop(color: StyleColor(red: 1.0, green: 1.0, blue: 1.0), location: 1.0),
            ],
            lcdStops: [
                GradientStop(color: StyleColor(red: 1.0, green: 0.576, blue: 0.0), location: 0.0),
                GradientStop(color: StyleColor(red: 1.0, green: 0.576, blue: 0.0), location: 0.5),
                GradientStop(color: StyleColor(red: 1.0, green: 0.576, blue: 0.0), location: 1.0),
            ]
        )
    )
}
