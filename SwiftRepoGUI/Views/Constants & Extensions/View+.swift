import SwiftUI

extension View {
    func terminalText(size: CGFloat = 13, weight: Font.Weight = .regular) -> some View {
        self
            .font(.monaco(size: size, weight: weight))
            .foregroundStyle(Color.terminalGreen)
    }
}
