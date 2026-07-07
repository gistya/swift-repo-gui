import SwiftUI

// Computed (not `static let`) so they re-read the live `AppStyleStore` every time — reading one in a
// SwiftUI body subscribes that view to style changes, so editing colors or switching to the Light
// preset re-themes the UI without touching any of the ~170 call sites.
extension Color {
    static var swiftOrange: Color { Color(SwiftBuilderStyle.current.colors.swiftOrange) }
    static var lcdGreen: Color { Color(SwiftBuilderStyle.current.colors.lcdGreen) }
    static var terminalGreen: Color { Color(SwiftBuilderStyle.current.colors.terminalGreen) }
    static var terminalDimGreen: Color { Color(SwiftBuilderStyle.current.colors.terminalDimGreen) }
    static var terminalBlack: Color { Color(SwiftBuilderStyle.current.colors.terminalBlack) }
    static var terminalFailureRed: Color { Color(SwiftBuilderStyle.current.colors.failureRed) }
    static var terminalButtonTop: Color { Color(SwiftBuilderStyle.current.colors.buttonTop) }
    static var terminalButtonBottom: Color { Color(SwiftBuilderStyle.current.colors.buttonBottom) }
    static var logoShadow: Color { Color(SwiftBuilderStyle.current.colors.logoShadow) }
    static var tabBarBackground: Color { Color(SwiftBuilderStyle.current.colors.tabBar) }
    static var tabFill: Color { Color(SwiftBuilderStyle.current.colors.tab) }
    static var styleSwitcherBackground: Color { Color(SwiftBuilderStyle.current.colors.styleSwitcher) }
    static var ledBackground: Color { Color(SwiftBuilderStyle.current.colors.ledBackground) }
    static var controlSurface: Color { Color(SwiftBuilderStyle.current.colors.controlSurface) }
    static var toggleTint: Color { Color(SwiftBuilderStyle.current.colors.toggleTint) }
    static var toggleThumb: Color { Color(SwiftBuilderStyle.current.colors.toggleThumb) }
}
