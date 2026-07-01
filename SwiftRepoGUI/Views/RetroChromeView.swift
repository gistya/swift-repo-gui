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
    let isSoundMuted: Bool
    let audioError: String?
    let onToggleMute: () -> Void
    @State private var pulse = false

    private var stage: BuildStage { BuildStage.stage(for: build.context) }
    private var module: String { BuildStage.moduleDisplay(for: build.context) }

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
                    .frame(minWidth: 230, alignment: .leading)

                Spacer(minLength: 10)

                VStack(spacing: 6) {
                    LcdModuleDisplay(text: module, stage: stage)
                    StageLEDStrip(stage: stage)
                }
                .frame(maxWidth: 430)

                Spacer(minLength: 10)

                HStack(spacing: 10) {
                    progressReadout
                    if audioError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.monaco(size: 11, weight: .bold))
                            .foregroundStyle(Color.terminalFailureRed)
                            .help(audioError ?? "")
                    }
                    soundButton
                }
                .frame(minWidth: 260, alignment: .trailing)
            }
            .padding(.horizontal, 18)
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

    private var soundButton: some View {
        Button(action: onToggleMute) {
            Image(systemName: isSoundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isSoundMuted ? Color.terminalDimGreen : Color.terminalGreen)
                .frame(width: 32, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.terminalButtonBottom.opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    isSoundMuted ? Color.terminalDimGreen.opacity(0.55) : Color.terminalGreen.opacity(0.55),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: isSoundMuted ? .clear : Color.terminalGreen.opacity(0.42),
                            radius: isSoundMuted ? 0 : 6
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSoundMuted ? "Unmute soundtrack" : "Mute soundtrack")
        .help(isSoundMuted ? "Unmute soundtrack" : "Mute soundtrack")
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
