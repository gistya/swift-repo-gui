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
    /// Main (foreground) text of the LCD status display.
    var lcdText: StyleColor
    /// Soft drop shadow of the LCD status display's main text.
    var lcdTextShadow: StyleColor
    /// Offset duplicate of the LCD text that fakes a hard, extruded shadow.
    var lcdTextSecondary: StyleColor

    init(swiftOrange: StyleColor, lcdGreen: StyleColor, terminalGreen: StyleColor, terminalDimGreen: StyleColor, terminalBlack: StyleColor, failureRed: StyleColor, buttonTop: StyleColor, buttonBottom: StyleColor, logoShadow: StyleColor, tabBar: StyleColor, tab: StyleColor, styleSwitcher: StyleColor, ledBackground: StyleColor, controlSurface: StyleColor, toggleTint: StyleColor, toggleThumb: StyleColor, lcdText: StyleColor, lcdTextShadow: StyleColor, lcdTextSecondary: StyleColor) {
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
        self.lcdText = lcdText
        self.lcdTextShadow = lcdTextShadow
        self.lcdTextSecondary = lcdTextSecondary
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
        lcdText = try c.decodeIfPresent(StyleColor.self, forKey: .lcdText) ?? fallback.lcdText
        lcdTextShadow = try c.decodeIfPresent(StyleColor.self, forKey: .lcdTextShadow) ?? fallback.lcdTextShadow
        lcdTextSecondary = try c.decodeIfPresent(StyleColor.self, forKey: .lcdTextSecondary) ?? fallback.lcdTextSecondary
    }
    
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
            lcdText: .random(),
            lcdTextShadow: .random(),
            lcdTextSecondary: .random()
        )
    }
}
