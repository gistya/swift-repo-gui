import SwiftRepoCore
import SwiftUI
import SwiftXStateSwiftUI

struct RetroTitleBar: View {
    let build: MachineStore<BuildOperationsMachine>
    let soundtrackDeck: SoundtrackDeckConfiguration?

    @State private var pulse = false

    // NOTE: this view's body must NOT read `build.context` / `build.currentStage`. Those change
    // ~10×/sec during a build, and reading them here would rebuild the ENTIRE title bar (brushed
    // metal, rotated app icon, brand, soundtrack deck) on every tick. The live-updating bits live in
    // `BuildStatusReadout` / `BuildProgressReadout` subviews so only they re-render per tick. The
    // `matches(.running)` glow below reads `configuration`, which only changes on state transitions
    // (a handful of times per build), so it's fine to keep here.
    private var audioError: String? { soundtrackDeck?.audioError }

    var body: some View {
        ZStack {
            BrushedMetalBackground()
                .accessibilityHidden(true)
            if build.matches(.running) {
                Color.swiftOrange
                    .opacity(pulse ? 0.22 : 0.06)
                    .blendMode(.plusLighter)
                    .animation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true), value: pulse)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 18) {
                brand
                    .frame(minWidth: 250, alignment: .leading)
                    .layoutPriority(2)

                BuildStatusReadout(build: build)
                    .layoutPriority(3)

                VStack(alignment: .trailing, spacing: 7) {
                    HStack(spacing: 10) {
                        Text("Ox0badf00d MOD tracker")
                            .font(.monaco(size: 10, weight: .semibold))
                            .foregroundStyle(Color.terminalGreen.opacity(0.65))
                        
                        Spacer(minLength: 0)

                        BuildProgressReadout(build: build)

                        if let audioError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.monaco(size: 11, weight: .bold))
                                .foregroundStyle(Color.terminalFailureRed)
                                .help(audioError)
                                .accessibilityLabel("Soundtrack error")
                                .accessibilityValue(audioError)
                        }
                    }

                    if let soundtrackDeck {
                        SoundtrackDeckView(deck: soundtrackDeck)
                    }
                }
                .frame(minWidth: soundtrackDeck == nil ? 260 : 318, alignment: .trailing)
                .layoutPriority(1)
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
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("SwiftBuild")
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .font(.monaco(size: 24, weight: .bold))
                    .foregroundStyle(Color.terminalGreen)
                    .shadow(color: Color.terminalGreen.opacity(0.75), radius: 4)
                    .shadow(color: Color.logoShadow, radius: 3, x: 3, y: 3)

                Text("swift-project control surface")
                    .font(.monaco(size: 10, weight: .semibold))
                    .foregroundStyle(Color.terminalGreen.opacity(0.65))
                
                Text("made with SwiftXState")
                    .font(.monaco(size: 10, weight: .semibold))
                    .foregroundStyle(Color.terminalGreen.opacity(0.65))
            }
        }
    }

}

/// The LCD module name + stage LEDs. Isolated so its ~10 Hz updates during a build don't rebuild the
/// rest of the title bar — only this small view reads `currentStage`/`context` and re-renders.
private struct BuildStatusReadout: View {
    let build: MachineStore<BuildOperationsMachine>

    private var stage: BuildStage { build.currentStage }
    private var module: String { BuildStage.moduleDisplay(for: stage, context: build.context) }

    var body: some View {
        VStack(spacing: 6) {
            LcdModuleDisplay(text: module, stage: stage)
            StageLEDStrip(stage: stage)
        }
    }
}

/// The step counter / status / clock readout. Isolated for the same reason as `BuildStatusReadout`.
private struct BuildProgressReadout: View {
    let build: MachineStore<BuildOperationsMachine>

    @ViewBuilder
    var body: some View {
        if build.matches(.running), build.context.progress.totalSteps > 0 {
            Text("\(build.context.progress.completedSteps)/\(build.context.progress.totalSteps)  \(Int(build.context.progress.fraction * 100))%")
                .font(.monaco(size: 12, weight: .bold))
                .foregroundStyle(Color.lcdGreen)
                .shadow(color: Color.lcdGreen.opacity(0.75), radius: 4)
        } else if let message = build.context.statusMessage, build.currentStage == .failed {
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
    RetroTitleBar(build: .init(.init()), soundtrackDeck: SoundtrackDeckConfiguration(nowPlaying: .empty, isMuted: false, isPaused: false, volume: 0.5, insertSlots: [], availableEffects: [], audioError: nil, onToggleMute: {}, onTogglePause: {}, onPreviousTrack: {}, onNextTrack: {}, onVolumeChange: {_ in }, onSetInsert: { _, _ in }, onToggleBypass: { _ in }, onOpenEffects: {}, makeInsertEditor: { _ in return nil}))
        .frame(width: 1200)
}
