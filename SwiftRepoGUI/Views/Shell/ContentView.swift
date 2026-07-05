import SwiftUI
import SwiftData
import SwiftXStateInspectorUI
import SwiftXStateSwiftUI

struct ContentView: View {
    let session: AppSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @FocusState private var keyboardFocus: Bool

    init(session: AppSession) {
        self.session = session
    }

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(
                build: session.build,
                soundtrackDeck: SoundtrackDeckConfiguration(
                    nowPlaying: session.soundtrack.context.nowPlaying,
                    isMuted: session.soundtrack.context.isMuted,
                    isPaused: session.soundtrack.matches(.paused),
                    volume: session.soundtrack.context.volume,
                    insertSlots: session.soundtrack.context.insertSlots,
                    availableEffects: session.availableAudioEffects,
                    audioError: session.soundtrack.context.lastError,
                    onToggleMute: { session.soundtrack.send(.toggleMute) },
                    onTogglePause: { session.soundtrack.send(.togglePause) },
                    onPreviousTrack: { session.soundtrack.send(.previousTrack) },
                    onNextTrack: { session.soundtrack.send(.nextTrack) },
                    onVolumeChange: { session.soundtrack.send(.setVolume($0)) },
                    onSetInsert: { index, component in
                        session.soundtrack.send(.setInsertSlot(index: index, component: component))
                    },
                    onToggleBypass: { index in
                        session.soundtrack.send(.toggleInsertBypass(index: index))
                    },
                    onOpenEffects: { session.ensureAudioEffectsLoaded() },
                    makeInsertEditor: { slot in await session.makeSoundtrackInsertEditor(slot: slot) }
                )
            )

            TerminalTabBar(
                selected: session.selectedSection,
                onSelect: { session.selectSection($0) },
                onDetach: { openWindow(value: $0) }
            )

            ZStack {
                TerminalBackground()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                AppSectionContent(session: session, section: session.selectedSection)
            }
        }
        .frame(minWidth: 1080, minHeight: 640)
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
            // `.launch` is owned by SoundtrackEffectDriver, which fires it only after the persisted
            // audio settings (volume / inserts) are live on the engine — so default playback can't
            // start before the saved volume lands. We only seed the current build stage here.
            session.soundtrack.send(.buildSnapshotChanged(SoundtrackBuildSnapshot(session.build.context)))
            // Warm the Toolchain tab's cold costs (SwiftData + preset parse) off the critical path so
            // its first open doesn't spike CPU/disk and glitch the soundtrack.
            session.warmUpToolchain()
            keyboardFocus = true
        }
        .onChange(of: session.settings.context) {
            session.persistLastUsedSettings()
        }
        // Bridge build → soundtrack on a narrow derived value, so this only fires when the stage /
        // running / exit actually changes — not on every unrelated BuildOperationsContext mutation.
        .onChange(of: SoundtrackBuildSnapshot(session.build.context)) { _, snapshot in
            session.soundtrack.send(.buildSnapshotChanged(snapshot))
        }
    }
}

#Preview {
    ContentView(session: .shared)
        .modelContainer(for: [BuildOperationRecord.self, SavedBuildProfile.self], inMemory: true)
}
