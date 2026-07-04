import SwiftUI
import SwiftXStateSwiftUI

struct RetroTitleBar: View {
    let build: MachineStore<BuildOperationsMachine>
    let soundtrackDeck: SoundtrackDeckConfiguration?
    @State private var pulse = false

    private var stage: BuildStage { build.currentStage }
    private var module: String { BuildStage.moduleDisplay(for: stage, context: build.context) }
    private var audioError: String? { soundtrackDeck?.audioError }

    var body: some View {
        ZStack {
            BrushedMetalBackground()
            if build.matches(.running) {
                Color.swiftOrange
                    .opacity(pulse ? 0.22 : 0.06)
                    .blendMode(.plusLighter)
                    .animation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true), value: pulse)
            }

            HStack(spacing: 18) {
                brand
                    .frame(minWidth: 250, alignment: .leading)
                    .layoutPriority(2)

                VStack(spacing: 6) {
                    LcdModuleDisplay(text: module, stage: stage)
                    StageLEDStrip(stage: stage)
                }
                .frame(maxWidth: 390)
                .layoutPriority(1)

                VStack(alignment: .trailing, spacing: 7) {
                    HStack(spacing: 10) {
                        Text("Ox0badf00d MOD tracker")
                            .font(.monaco(size: 10, weight: .semibold))
                            .foregroundStyle(Color.terminalGreen.opacity(0.65))
                            .alignmentGuide(HorizontalAlignment.leading) { _ in 0.5 }
                        
                        Spacer(minLength: 0)

                        progressReadout
                        if audioError != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.monaco(size: 11, weight: .bold))
                                .foregroundStyle(Color.terminalFailureRed)
                                .help(audioError ?? "")
                        }
                    }
                    if let soundtrackDeck {
                        SoundtrackDeckView(deck: soundtrackDeck)
                    }
                }
                .frame(minWidth: soundtrackDeck == nil ? 260 : 318, alignment: .trailing)
                .layoutPriority(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(height: 104)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.black.opacity(0.38))
                .frame(height: 1)
        }
        .onAppear { pulse = true }
    }

    private var brand: some View {
        HStack() {
            ZStack {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-20.0))
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("SwiftBuild")
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .font(.monaco(size: 24, weight: .bold))
                    .foregroundStyle(Color.terminalGreen)
                    .shadow(color: Color.terminalGreen.opacity(0.75), radius: 4)
                    .shadow(color: .black.opacity(0.9), radius: 3, x: 3, y: 3)

                Text("swift-project control surface")
                    .font(.monaco(size: 10, weight: .semibold))
                    .foregroundStyle(Color.terminalGreen.opacity(0.65))
                
                Text("made with SwiftXState")
                    .font(.monaco(size: 10, weight: .semibold))
                    .foregroundStyle(Color.terminalGreen.opacity(0.65))
            }
        }
    }

    @ViewBuilder
    private var progressReadout: some View {
        if build.matches(.running), build.context.progress.totalSteps > 0 {
            Text("\(build.context.progress.completedSteps)/\(build.context.progress.totalSteps)  \(Int(build.context.progress.fraction * 100))%")
                .font(.monaco(size: 12, weight: .bold))
                .foregroundStyle(Color.lcdGreen)
                .shadow(color: Color.lcdGreen.opacity(0.75), radius: 4)
        } else if let message = build.context.statusMessage, stage == .failed {
            Text(message.uppercased())
                .font(.monaco(size: 10, weight: .bold))
                .foregroundStyle(Color.terminalGreen)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text(Date.now, style: .time)
                .font(.monaco(size: 12, weight: .bold))
                .foregroundStyle(Color.terminalGreen.opacity(0.72))
        }
    }
}

#Preview {
    RetroTitleBar(build: .init(.init()), soundtrackDeck: .none)
}
