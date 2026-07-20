import SwiftUI

struct LcdModuleDisplay: View {
    let text: String
    let stage: BuildStage

    private var panelStops: [Gradient.Stop] {
        SwiftBuilderStyle.current.gradients.lcdStops.map {
            .init(color: Color($0.color), location: $0.location)
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(stops: panelStops, startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(.black.opacity(0.78), lineWidth: 2)
                }
            ZStack {
                Text(text)
                    .font(.lcd(size: 29, weight: .heavy))
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .tracking(0)
                    .foregroundStyle(Color.lcdTextSecondary)
                    .offset(x: 3.5, y: 3.5)

                Text(text)
                    .font(.lcd(size: 29, weight: .heavy))
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .tracking(0)
                    .foregroundStyle(Color.lcdText)
                    .shadow(color: Color.lcdTextShadow, radius: 1.5, x: 0, y: 1)
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 54)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Build stage")
        .accessibilityValue("\(stage.title), \(text)")
    }
}

#Preview {
    LcdModuleDisplay(text: "READY", stage: .off)
}
