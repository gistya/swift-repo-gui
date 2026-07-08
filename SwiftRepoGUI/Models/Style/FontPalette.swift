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
