import SwiftUI

struct SoundtrackIconButton: View {
    let systemName: String
    let help: String
    let isNotEngaged: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(foreground)
                .frame(width: 24, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.terminalButtonBottom.opacity(isDisabled ? 0.58 : 0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(border.opacity(isDisabled ? 0.34 : 0.72), lineWidth: 1)
                        )
                        .shadow(color: glow, radius: isNotEngaged && !isDisabled ? 6 : 0)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(help)
        .help(help)
    }
    
    private var foreground: Color {
        if isDisabled { return .terminalDimGreen }
        return isNotEngaged ? .swiftOrange : .terminalGreen
    }

    private var border: Color {
        isNotEngaged ? .swiftOrange : .terminalGreen
    }

    private var glow: Color {
        isNotEngaged ? Color.swiftOrange.opacity(0.72) : Color.terminalGreen.opacity(0.36)
    }
}
