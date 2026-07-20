import SwiftUI

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
