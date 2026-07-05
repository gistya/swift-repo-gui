import SwiftUI

struct LcdModuleDisplay: View {
    let text: String
    let stage: BuildStage

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.48, green: 0.51, blue: 0.47),
                            Color(red: 0.64, green: 0.67, blue: 0.60),
                            Color(red: 0.39, green: 0.42, blue: 0.38)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
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
                    .foregroundStyle(.black.opacity(0.3))
                    .offset(x: 3.5, y: 3.5)

                Text(text)
                    .font(.lcd(size: 29, weight: .heavy))
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .tracking(0)
                    .foregroundStyle(.black.opacity(1.0))
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
