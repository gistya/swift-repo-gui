nonisolated struct GradientPalette: Codable, Equatable, Sendable {
    /// Brushed-metal gradient of the top chrome bar.
    var metalStops: [GradientStop]
    /// Panel gradient of the LCD status display.
    var lcdStops: [GradientStop]

    init(metalStops: [GradientStop], lcdStops: [GradientStop]) {
        self.metalStops = metalStops
        self.lcdStops = lcdStops
    }

    // Tolerant decode: themes persisted before `lcdStops` existed omit it — fall back to the dark
    // default rather than discarding the whole saved theme.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metalStops = try c.decode([GradientStop].self, forKey: .metalStops)
        lcdStops = try c.decodeIfPresent([GradientStop].self, forKey: .lcdStops) ?? AppStyle.default.gradients.lcdStops
    }

    /// Randomize each metal stop's color while keeping the stop positions.
    nonisolated func randomized() -> GradientPalette {
        GradientPalette(
            metalStops: metalStops.map { GradientStop(color: .random(), location: $0.location) },
            lcdStops: lcdStops.map { GradientStop(color: .random(), location: $0.location) }
        )
    }
}


