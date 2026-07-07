import SwiftUI

extension Font {
    static func monaco(
        size: CGFloat = CGFloat(SwiftBuilderStyle.current.fonts.defaultSize),
        weight: Font.Weight = .regular
    ) -> Font {
        .custom(SwiftBuilderStyle.current.fonts.monospaceName, size: size).weight(weight)
    }
    
    static func lcd(
        size: CGFloat = CGFloat(SwiftBuilderStyle.current.fonts.defaultSize),
        weight: Font.Weight = .regular
    ) -> Font {
        .custom(SwiftBuilderStyle.current.fonts.lcdName, size: size).weight(weight)
    }

    static func switcher(
        size: CGFloat = CGFloat(SwiftBuilderStyle.current.fonts.defaultSize),
        weight: Font.Weight = .regular
    ) -> Font {
        .custom(SwiftBuilderStyle.current.fonts.switcherName, size: size).weight(weight)
    }
}
