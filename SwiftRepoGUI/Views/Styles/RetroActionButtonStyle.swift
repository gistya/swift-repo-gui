import SwiftUI

struct RetroActionButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        // A ButtonStyle can't hold @State, so the hover-reactive chrome lives in a nested view.
        HoverBody(configuration: configuration)
    }

    private struct HoverBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        private var isHot: Bool { hovering && isEnabled && !configuration.isPressed }

        var body: some View {
            configuration.label
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: configuration.isPressed
                                    ? [.swiftOrange.opacity(0.45), .black.opacity(0.85), .swiftOrange.opacity(0.24)]
                                    : isHot
                                        ? [.terminalButtonTop, .terminalButtonBottom]
                                        : [.terminalButtonTop.opacity(0.88), .terminalButtonBottom.opacity(0.98)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.terminalGreen.opacity(isHot ? 0.7 : 0.24), lineWidth: isHot ? 1.4 : 1)
                        )
                        .shadow(
                            color: configuration.isPressed
                                ? Color.swiftOrange.opacity(0.95)
                                : isHot ? Color.terminalGreen.opacity(0.5) : .black.opacity(0.14),
                            radius: configuration.isPressed ? 12 : (isHot ? 9 : 3)
                        )
                }
                .scaleEffect(configuration.isPressed ? 0.975 : (isHot ? 1.015 : 1))
                .foregroundStyle(Color.terminalGreen)
                .animation(.spring(response: 0.18, dampingFraction: 0.72), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.14), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}
