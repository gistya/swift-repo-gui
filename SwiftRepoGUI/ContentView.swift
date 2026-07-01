import SwiftUI
import SwiftData
import SwiftXStateSwiftUI

struct ContentView: View {
    let session: AppSession
    @StateObject private var soundtrack = TrackerSoundtrackController()
    @AppStorage("SwiftBuilder.soundtrackMuted") private var soundtrackMuted = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @FocusState private var keyboardFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(
                build: session.build,
                isSoundMuted: soundtrackMuted,
                audioError: soundtrack.lastError,
                onToggleMute: { soundtrackMuted.toggle() }
            )

            TerminalTabBar(
                selected: session.selectedSection,
                onSelect: { session.selectSection($0) },
                onDetach: { openWindow(value: $0) }
            )

            ZStack {
                TerminalBackground()
                    .ignoresSafeArea()
                AppSectionContent(session: session, section: session.selectedSection)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(TerminalBackground().ignoresSafeArea())
        .terminalText()
        .tint(.terminalGreen)
        .buttonStyle(RetroMetalButtonStyle())
        .focusable()
        .focused($keyboardFocus)
        .onMoveCommand { direction in
            switch direction {
            case .left:
                session.selectSection(session.selectedSection.previous)
            case .right:
                session.selectSection(session.selectedSection.next)
            default:
                break
            }
        }
        .onAppear {
            session.attach(modelContext: modelContext)
            soundtrack.setMuted(soundtrackMuted)
            soundtrack.start()
            soundtrack.update(for: session.build.context)
            keyboardFocus = true
        }
        .onChange(of: soundtrackMuted) {
            soundtrack.setMuted(soundtrackMuted)
        }
        .onChange(of: session.settings.context) {
            session.persistLastUsedSettings()
        }
        .onChange(of: session.build.context) {
            soundtrack.update(for: session.build.context)
        }
    }
}

struct DetachedSectionWindow: View {
    let session: AppSession
    let section: AppSectionID
    @AppStorage("SwiftBuilder.soundtrackMuted") private var soundtrackMuted = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(
                build: session.build,
                isSoundMuted: soundtrackMuted,
                audioError: nil,
                onToggleMute: { soundtrackMuted.toggle() }
            )
            ZStack {
                TerminalBackground()
                    .ignoresSafeArea()
                AppSectionContent(session: session, section: section)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(TerminalBackground().ignoresSafeArea())
        .terminalText()
        .tint(.terminalGreen)
        .buttonStyle(RetroMetalButtonStyle())
        .onAppear {
            session.attach(modelContext: modelContext)
        }
    }
}

struct AppSectionContent: View {
    let session: AppSession
    let section: AppSectionID

    var body: some View {
        switch section {
        case .build:
            DashboardView(
                session: session,
                project: session.project,
                settings: session.settings,
                build: session.build
            )
        case .settings:
            BuildSettingsView(settings: session.settings)
        case .history:
            HistoryView(session: session)
        case .logs:
            LiveLogView(build: session.build)
        }
    }
}

struct TerminalTabBar: View {
    let selected: AppSectionID
    let onSelect: (AppSectionID) -> Void
    let onDetach: (AppSectionID) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppSectionID.allCases) { section in
                TerminalTabButton(
                    section: section,
                    isSelected: section == selected,
                    onSelect: onSelect,
                    onDetach: onDetach
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 0)
        .background(TerminalBackground())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.terminalGreen.opacity(0.35))
                .frame(height: 1)
        }
    }
}

struct TerminalTabButton: View {
    let section: AppSectionID
    let isSelected: Bool
    let onSelect: (AppSectionID) -> Void
    let onDetach: (AppSectionID) -> Void
    @State private var dragArmed = false
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        Button {
            onSelect(section)
        } label: {
            Label(section.title.uppercased(), systemImage: section.symbolName)
                .font(.monaco(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? Color.terminalGreen : Color.terminalGreen.opacity(0.42))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minWidth: 118)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 7)
                        .fill(isSelected ? Color.black.opacity(0.72) : Color.black.opacity(0.42))
                        .overlay {
                            UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 7)
                                .stroke(isSelected ? Color.terminalGreen.opacity(0.9) : Color.terminalGreen.opacity(0.25), lineWidth: 1)
                        }
                        .shadow(color: isSelected ? Color.terminalGreen.opacity(0.45) : .clear, radius: 8)
                }
        }
        .buttonStyle(.plain)
        .offset(dragOffset)
        .overlay(alignment: .topLeading) {
            if dragArmed {
                detachedWindowPreview
                    .offset(x: dragOffset.width + 8, y: dragOffset.height + 48)
                    .transition(.opacity.combined(with: .scale(scale: 0.72, anchor: .topLeading)))
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(dragArmed ? 1.04 : 1)
        .zIndex(dragArmed ? 10 : 0)
        .animation(.spring(response: 0.22, dampingFraction: 0.74), value: dragArmed)
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.78), value: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    dragOffset = value.translation
                    dragArmed = abs(value.translation.height) > 18
                }
                .onEnded { value in
                    let shouldDetach = abs(value.translation.height) > 44 || abs(value.translation.width) > 160
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        dragArmed = false
                        dragOffset = .zero
                    }
                    if shouldDetach {
                        onDetach(section)
                    }
                }
        )
        .help("Drag away to open \(section.title) in a separate window")
    }

    private var detachedWindowPreview: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                LinearGradient(
                    colors: [
                        Color.terminalButtonTop.opacity(0.96),
                        Color.terminalBlack.opacity(0.98)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.terminalGreen.opacity(0.82), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Image(systemName: section.symbolName)
                    Text(section.title.uppercased())
                }
                .font(.monaco(size: 11, weight: .bold))
                .foregroundStyle(Color.terminalGreen)
                .padding(10)
            }
            .shadow(color: Color.swiftOrange.opacity(0.35), radius: 16)
            .shadow(color: Color.terminalGreen.opacity(0.32), radius: 12)
            .frame(width: dragArmed ? 190 : 120, height: dragArmed ? 126 : 42)
    }
}

#Preview {
    ContentView(session: AppSession())
        .modelContainer(for: [BuildOperationRecord.self, SavedBuildProfile.self], inMemory: true)
}
