import SwiftRepoCore
import SwiftUI

struct StageLEDStrip: View {
    let stage: BuildStage

    var body: some View {
        HStack(spacing: 8) {
            ForEach([BuildStage.off, .building, .testing, .measuring, .deploying, .failed], id: \.self) { item in
                LEDIndicator(title: item.title, color: color(for: item), isOn: stage == item)
                    .background(alignment: .leading) {
                        Rectangle().fill(Color.black)
                    }
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Build stage")
        .accessibilityValue(stage.title)
    }

    private func color(for stage: BuildStage) -> Color {
        switch stage {
        case .building: .orange
        case .testing: .yellow
        case .measuring: .blue
        case .deploying: .cyan
        case .failed: .red
        case .off: .white
        }
    }
}

#Preview {
    StageLEDStrip(stage: .building)
}
