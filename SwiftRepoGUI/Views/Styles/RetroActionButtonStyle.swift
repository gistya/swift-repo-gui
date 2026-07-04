import SwiftUI

struct RetroActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed
                                ? [.swiftOrange.opacity(0.45), .black.opacity(0.85), .swiftOrange.opacity(0.24)]
                                : [.terminalButtonTop.opacity(0.88), .terminalButtonBottom.opacity(0.98)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.terminalGreen.opacity(0.24), lineWidth: 1))
                    .shadow(color: configuration.isPressed ? Color.swiftOrange.opacity(0.95) : .black.opacity(0.14), radius: configuration.isPressed ? 12 : 3)
            }
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .foregroundStyle(Color.terminalGreen)
            .animation(.spring(response: 0.18, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
