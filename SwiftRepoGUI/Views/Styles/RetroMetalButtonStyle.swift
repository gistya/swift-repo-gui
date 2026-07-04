import SwiftUI

struct RetroMetalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed
                                ? [.swiftOrange.opacity(0.55), .black.opacity(0.78), .swiftOrange.opacity(0.35)]
                                : [.terminalButtonTop.opacity(0.92), .terminalButtonBottom.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.terminalGreen.opacity(0.28), lineWidth: 1))
                    .shadow(
                        color: configuration.isPressed ? Color.swiftOrange.opacity(0.8) : .black.opacity(0.55),
                        radius: configuration.isPressed ? 8 : 2
                    )
            }
            .foregroundStyle(Color.terminalGreen)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
