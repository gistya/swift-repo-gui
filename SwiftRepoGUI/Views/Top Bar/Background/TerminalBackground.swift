import SwiftUI

struct TerminalBackground: View {
    var body: some View {
        ZStack {
            Color.terminalBlack
            RadialGradient(
                colors: [
                    Color.terminalGreen.opacity(0.14),
                    Color.terminalDimGreen.opacity(0.08),
                    .clear
                ],
                center: .topLeading,
                startRadius: 30,
                endRadius: 760
            )
            BrushedMetalLines()
                .opacity(0.045)
        }
    }
}


