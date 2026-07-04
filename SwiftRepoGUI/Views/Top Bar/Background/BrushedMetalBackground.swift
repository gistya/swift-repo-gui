import SwiftUI

struct BrushedMetalBackground: View {
    private var metalStops: [Gradient.Stop] {
        SwiftBuilderStyle.current.gradients.metalStops.map {
            .init(color: Color($0.color), location: $0.location)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                stops: metalStops,
                startPoint: .top,
                endPoint: .bottom
            )
            BrushedMetalLines()
                .opacity(0.10)
            LinearGradient(
                colors: [Color.terminalGreen.opacity(0.08), .clear, .black.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
