import SwiftUI

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
