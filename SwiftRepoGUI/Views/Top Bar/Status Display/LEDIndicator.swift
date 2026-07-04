import SwiftUI

struct LEDIndicator: View {
    let title: String
    let color: Color
    let isOn: Bool

    var body: some View {
        Text(title)
            .font(.monaco(size: 8, weight: .black))
            .tracking(0)
            .foregroundStyle(isOn ? color : color.opacity(0.16))
            .shadow(color: isOn ? color.opacity(0.95) : .clear, radius: 5)
            .shadow(color: isOn ? .white.opacity(0.24) : .clear, radius: 0, x: -0.5, y: -0.5)
            .frame(minWidth: 48)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
