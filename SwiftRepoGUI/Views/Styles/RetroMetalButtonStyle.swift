import SwiftUI

struct RetroMetalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        private var isHot: Bool { hovering && isEnabled && !configuration.isPressed }

        var body: some View {
            configuration.label
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: configuration.isPressed
                                    ? [.swiftOrange.opacity(0.55), .black.opacity(0.78), .swiftOrange.opacity(0.35)]
                                    : isHot
                                        ? [.terminalButtonTop, .terminalButtonBottom]
                                        : [.terminalButtonTop.opacity(0.92), .terminalButtonBottom.opacity(0.98)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.terminalGreen.opacity(isHot ? 0.75 : 0.28), lineWidth: isHot ? 1.3 : 1)
                        )
                        .shadow(
                            color: configuration.isPressed
                                ? Color.swiftOrange.opacity(0.8)
                                : isHot ? Color.terminalGreen.opacity(0.5) : .black.opacity(0.55),
                            radius: configuration.isPressed ? 8 : (isHot ? 6 : 2)
                        )
                }
                .foregroundStyle(Color.terminalGreen)
                .scaleEffect(configuration.isPressed ? 0.985 : (isHot ? 1.02 : 1))
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.14), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}
