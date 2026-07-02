import Foundation
import SwiftUI
import SwiftXStateSwiftUI

extension Color {
    static let swiftOrange = Color(SwiftBuilderStyle.current.colors.swiftOrange)
    static let lcdGreen = Color(SwiftBuilderStyle.current.colors.lcdGreen)
    static let terminalGreen = Color(SwiftBuilderStyle.current.colors.terminalGreen)
    static let terminalDimGreen = Color(SwiftBuilderStyle.current.colors.terminalDimGreen)
    static let terminalBlack = Color(SwiftBuilderStyle.current.colors.terminalBlack)
    static let terminalFailureRed = Color(SwiftBuilderStyle.current.colors.failureRed)
    static let terminalButtonTop = Color(SwiftBuilderStyle.current.colors.buttonTop)
    static let terminalButtonBottom = Color(SwiftBuilderStyle.current.colors.buttonBottom)
}

extension Font {
    static func monaco(
        size: CGFloat = CGFloat(SwiftBuilderStyle.current.fonts.defaultSize),
        weight: Font.Weight = .regular
    ) -> Font {
        .custom(SwiftBuilderStyle.current.fonts.monospaceName, size: size).weight(weight)
    }
}

extension View {
    func terminalText(size: CGFloat = 13, weight: Font.Weight = .regular) -> some View {
        self
            .font(.monaco(size: size, weight: weight))
            .foregroundStyle(Color.terminalGreen)
    }
}

struct RetroTitleBar: View {
    let build: MachineStore<BuildOperationsMachine>
    let soundtrackDeck: SoundtrackDeckConfiguration?
    @State private var pulse = false

    private var stage: BuildStage { BuildStage.stage(for: build.context) }
    private var module: String { BuildStage.moduleDisplay(for: build.context) }
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
                    .frame(width: 216, alignment: .leading)

                Spacer(minLength: 10)

                VStack(spacing: 6) {
                    LcdModuleDisplay(text: module, stage: stage)
                    StageLEDStrip(stage: stage)
                }
                .frame(maxWidth: 390)
                .layoutPriority(1)

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 7) {
                    HStack(spacing: 10) {
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
                .frame(width: soundtrackDeck == nil ? 260 : 318, alignment: .trailing)
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
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .black.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.55), lineWidth: 1))
                    .shadow(color: .white.opacity(0.65), radius: 1, x: -1, y: -1)
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 1, y: 1)

                Image(systemName: "swift")
                    .font(.system(size: 25, weight: .black))
                    .foregroundStyle(Color.swiftOrange)
                    .shadow(color: .white.opacity(0.7), radius: 0.5, x: -1, y: -1)
                    .shadow(color: .black.opacity(0.65), radius: 1, x: 1, y: 1)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 0) {
                Text("SwiftBuilder")
                    .font(.monaco(size: 24, weight: .bold))
                    .foregroundStyle(Color.terminalGreen)
                    .shadow(color: Color.terminalGreen.opacity(0.75), radius: 4)
                    .shadow(color: .black.opacity(0.9), radius: 1, x: 1, y: 1)

                Text("swift-project control surface")
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

struct SoundtrackDeckConfiguration {
    let nowPlaying: SoundtrackNowPlaying
    let isMuted: Bool
    let isPaused: Bool
    let volume: Double
    let effectsSettings: SoundtrackEffectsSettings
    let audioError: String?
    let onToggleMute: () -> Void
    let onTogglePause: () -> Void
    let onPreviousTrack: () -> Void
    let onNextTrack: () -> Void
    let onVolumeChange: (Double) -> Void
    let onEffectsChange: (SoundtrackEffectsSettings) -> Void
    let onResetEffects: () -> Void
}

private struct SoundtrackDeckView: View {
    let deck: SoundtrackDeckConfiguration
    @State private var isShowingEffects = false

    private var hasTrack: Bool {
        !deck.nowPlaying.detail.isEmpty
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 7) {
                trackReadout

                SoundtrackIconButton(
                    systemName: "backward.fill",
                    help: "Previous track",
                    isActive: false,
                    isDisabled: deck.isMuted || !hasTrack,
                    action: deck.onPreviousTrack
                )
                SoundtrackIconButton(
                    systemName: deck.isPaused ? "play.fill" : "pause.fill",
                    help: deck.isPaused ? "Resume soundtrack" : "Pause soundtrack",
                    isActive: deck.isPaused,
                    isDisabled: deck.isMuted || !hasTrack,
                    action: deck.onTogglePause
                )
                SoundtrackIconButton(
                    systemName: "forward.fill",
                    help: "Next track",
                    isActive: false,
                    isDisabled: deck.isMuted || !hasTrack,
                    action: deck.onNextTrack
                )
                SoundtrackIconButton(
                    systemName: "slider.horizontal.3",
                    help: "Tube rack",
                    isActive: deck.effectsSettings.isEnabled,
                    isDisabled: false,
                    action: { isShowingEffects.toggle() }
                )
                .popover(isPresented: $isShowingEffects, arrowEdge: .bottom) {
                    TubeRackPopup(
                        settings: deck.effectsSettings,
                        onChange: deck.onEffectsChange,
                        onReset: deck.onResetEffects
                    )
                }
                SoundtrackIconButton(
                    systemName: deck.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    help: deck.isMuted ? "Unmute soundtrack" : "Mute soundtrack",
                    isActive: !deck.isMuted,
                    isDisabled: false,
                    action: deck.onToggleMute
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.1.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(deck.isMuted ? Color.terminalDimGreen : Color.terminalGreen)
                Slider(
                    value: Binding(
                        get: { deck.volume },
                        set: deck.onVolumeChange
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .tint(deck.isMuted ? Color.terminalDimGreen : Color.terminalGreen)
                .frame(width: 184)
                Text("\(Int((deck.volume * 100).rounded()))")
                    .font(.monaco(size: 9, weight: .bold))
                    .foregroundStyle(deck.isMuted ? Color.terminalDimGreen : Color.terminalGreen)
                    .frame(width: 28, alignment: .trailing)
            }
            .opacity(deck.isMuted ? 0.55 : 1)
            .help("Soundtrack volume")
        }
    }

    private var trackReadout: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(deck.nowPlaying.title.uppercased())
                .font(.monaco(size: 10, weight: .black))
                .foregroundStyle(deck.isMuted ? Color.terminalDimGreen : Color.lcdGreen)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 5) {
                Text(deck.nowPlaying.artist.uppercased())
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !deck.nowPlaying.detail.isEmpty {
                    Text(deck.nowPlaying.detail.uppercased())
                        .foregroundStyle(deck.isMuted ? Color.terminalDimGreen : Color.swiftOrange)
                }
            }
            .font(.monaco(size: 8, weight: .bold))
            .foregroundStyle(deck.isMuted ? Color.terminalDimGreen : Color.terminalGreen.opacity(0.78))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: 150, height: 34, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.black.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke((deck.isMuted ? Color.terminalDimGreen : Color.lcdGreen).opacity(0.45), lineWidth: 1)
                )
                .shadow(color: deck.isMuted ? .clear : Color.lcdGreen.opacity(0.25), radius: 4)
        }
        .accessibilityLabel("\(deck.nowPlaying.artist), \(deck.nowPlaying.title)")
    }
}

private struct TubeRackPopup: View {
    let settings: SoundtrackEffectsSettings
    let onChange: (SoundtrackEffectsSettings) -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(settings.isEnabled ? Color.swiftOrange : Color.terminalDimGreen)
                    .shadow(color: settings.isEnabled ? Color.swiftOrange.opacity(0.8) : .clear, radius: 6)

                Text("TUBE RACK")
                    .font(.monaco(size: 15, weight: .black))
                    .foregroundStyle(Color.terminalGreen)

                Spacer()

                Toggle(isOn: boolBinding(\.isEnabled)) {
                    Text(settings.isEnabled ? "ON" : "BYP")
                        .font(.monaco(size: 10, weight: .black))
                        .foregroundStyle(settings.isEnabled ? Color.swiftOrange : Color.terminalDimGreen)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.swiftOrange)
                .help(settings.isEnabled ? "Bypass tube rack" : "Enable tube rack")
            }

            VStack(alignment: .leading, spacing: 10) {
                TubeRackSlider(
                    title: "DRIVE",
                    value: doubleBinding(\.drive),
                    range: 0...1,
                    valueText: { "\(Int(($0 * 100).rounded()))%" }
                )
                TubeRackSlider(
                    title: "LOW",
                    value: doubleBinding(\.lowGainDB),
                    range: -12...12,
                    valueText: Self.formattedDB
                )
                TubeRackSlider(
                    title: "MID",
                    value: doubleBinding(\.midGainDB),
                    range: -12...12,
                    valueText: Self.formattedDB
                )
                TubeRackSlider(
                    title: "AIR",
                    value: doubleBinding(\.highGainDB),
                    range: -12...12,
                    valueText: Self.formattedDB
                )
                TubeRackSlider(
                    title: "COMP",
                    value: doubleBinding(\.compression),
                    range: 0...1,
                    valueText: { "\(Int(($0 * 100).rounded()))%" }
                )
                TubeRackSlider(
                    title: "LIMIT",
                    value: doubleBinding(\.limiterCeilingDB),
                    range: -18...0,
                    valueText: Self.formattedDB
                )
                TubeRackSlider(
                    title: "OUT",
                    value: doubleBinding(\.outputGainDB),
                    range: -12...12,
                    valueText: Self.formattedDB
                )
            }
            .opacity(settings.isEnabled ? 1 : 0.56)

            HStack {
                Button(action: onReset) {
                    Text("RESET")
                        .font(.monaco(size: 10, weight: .black))
                        .foregroundStyle(Color.terminalGreen)
                        .frame(width: 68, height: 24)
                        .background {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.terminalButtonBottom.opacity(0.95))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.terminalGreen.opacity(0.35), lineWidth: 1))
                        }
                }
                .buttonStyle(.plain)
                .help("Reset tube rack")

                Spacer()

                Text("OX0BADF00D")
                    .font(.monaco(size: 9, weight: .black))
                    .foregroundStyle(Color.terminalDimGreen)
            }
        }
        .padding(14)
        .frame(width: 340)
        .background {
            ZStack {
                Color.terminalBlack
                LinearGradient(
                    colors: [
                        Color.swiftOrange.opacity(settings.isEnabled ? 0.16 : 0.04),
                        Color.terminalGreen.opacity(0.07),
                        Color.black.opacity(0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                BrushedMetalLines()
                    .opacity(0.07)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke((settings.isEnabled ? Color.swiftOrange : Color.terminalDimGreen).opacity(0.55), lineWidth: 1)
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<SoundtrackEffectsSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { update(keyPath, to: $0) }
        )
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<SoundtrackEffectsSettings, Double>) -> Binding<Double> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { update(keyPath, to: $0) }
        )
    }

    private func update<Value>(_ keyPath: WritableKeyPath<SoundtrackEffectsSettings, Value>, to value: Value) {
        var next = settings
        next[keyPath: keyPath] = value
        onChange(next.normalized())
    }

    nonisolated private static func formattedDB(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded > 0 {
            return "+\(String(format: "%.1f", rounded)) dB"
        }
        return "\(String(format: "%.1f", rounded)) dB"
    }
}

private struct TubeRackSlider: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let valueText: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.monaco(size: 10, weight: .black))
                    .foregroundStyle(Color.terminalGreen)
                    .frame(width: 46, alignment: .leading)

                Slider(value: value, in: range)
                    .tint(.swiftOrange)
                    .controlSize(.small)

                Text(valueText(value.wrappedValue))
                    .font(.monaco(size: 9, weight: .bold))
                    .foregroundStyle(Color.lcdGreen)
                    .frame(width: 62, alignment: .trailing)
            }

            Rectangle()
                .fill(Color.terminalGreen.opacity(0.12))
                .frame(height: 1)
        }
    }
}

private struct SoundtrackIconButton: View {
    let systemName: String
    let help: String
    let isActive: Bool
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
                        .shadow(color: glow, radius: isActive && !isDisabled ? 6 : 0)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(help)
        .help(help)
    }

    private var foreground: Color {
        if isDisabled { return .terminalDimGreen }
        return isActive ? .swiftOrange : .terminalGreen
    }

    private var border: Color {
        isActive ? .swiftOrange : .terminalGreen
    }

    private var glow: Color {
        isActive ? Color.swiftOrange.opacity(0.72) : Color.terminalGreen.opacity(0.36)
    }
}

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
                .overlay {
                    LcdScanlines()
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .opacity(0.16)
                }
                .shadow(color: .white.opacity(0.35), radius: 1, x: -1, y: -1)
                .shadow(color: .black.opacity(0.8), radius: 4, x: 2, y: 3)

            ZStack {
                Text(text)
                    .font(.monaco(size: 29, weight: .heavy))
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .tracking(0)
                    .foregroundStyle(.black.opacity(stage == .off ? 0.18 : 0.28))
                    .offset(x: 1.6, y: 1.8)

                Text(text)
                    .font(.monaco(size: 29, weight: .heavy))
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .tracking(0)
                    .foregroundStyle(.black.opacity(stage == .off ? 0.32 : 0.88))
                    .shadow(color: .white.opacity(0.18), radius: 0, x: -0.8, y: -0.8)
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 54)
    }
}

private struct LcdScanlines: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var y: CGFloat = 2
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += 4
            }
            context.stroke(path, with: .color(.black), lineWidth: 0.7)
        }
    }
}

struct StageLEDStrip: View {
    let stage: BuildStage

    var body: some View {
        HStack(spacing: 8) {
            ForEach([BuildStage.building, .testing, .measuring, .deploying, .failed], id: \.self) { item in
                LEDIndicator(title: item.title, color: color(for: item), isOn: stage == item)
            }
        }
    }

    private func color(for stage: BuildStage) -> Color {
        switch stage {
        case .building: .swiftOrange
        case .testing: .yellow
        case .measuring: .blue
        case .deploying: .cyan
        case .failed: .red
        case .off: .gray
        }
    }
}

struct LEDIndicator: View {
    let title: String
    let color: Color
    let isOn: Bool

    var body: some View {
        Text(title)
            .font(.monaco(size: 8, weight: .black))
            .tracking(0)
            .foregroundStyle(isOn ? color : color.opacity(0.16))
            .shadow(color: isOn ? color.opacity(0.95) : .clear, radius: 5)
            .shadow(color: isOn ? .white.opacity(0.24) : .clear, radius: 0, x: -0.5, y: -0.5)
            .frame(minWidth: 48)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

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

private struct BrushedMetalLines: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += 3
            }
            context.stroke(path, with: .color(.white), lineWidth: 0.55)
        }
    }
}

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

struct RetroMetalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed
                                ? [.swiftOrange.opacity(0.55), .black.opacity(0.78), .swiftOrange.opacity(0.35)]
                                : [.terminalButtonTop.opacity(0.92), .terminalButtonBottom.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.terminalGreen.opacity(0.28), lineWidth: 1))
                    .shadow(
                        color: configuration.isPressed ? Color.swiftOrange.opacity(0.8) : .black.opacity(0.55),
                        radius: configuration.isPressed ? 8 : 2
                    )
            }
            .foregroundStyle(Color.terminalGreen)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct RetroActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed
                                ? [.swiftOrange.opacity(0.45), .black.opacity(0.85), .swiftOrange.opacity(0.24)]
                                : [.terminalButtonTop.opacity(0.88), .terminalButtonBottom.opacity(0.98)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.terminalGreen.opacity(0.24), lineWidth: 1))
                    .shadow(color: configuration.isPressed ? Color.swiftOrange.opacity(0.95) : .black.opacity(0.14), radius: configuration.isPressed ? 12 : 3)
            }
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .foregroundStyle(Color.terminalGreen)
            .animation(.spring(response: 0.18, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
