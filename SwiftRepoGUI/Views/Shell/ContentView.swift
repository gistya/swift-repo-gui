import AppKit
import SwiftRepoCore
import SwiftUI
import SwiftData
import SwiftXStateInspectorUI
import SwiftXStateSwiftUI

struct ContentView: View {
    let session: AppSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
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
                sections: session.attachedSections,
                selected: session.selectedSection,
                onSelect: { session.selectSection($0) },
                onDetach: { section in
                    session.markDetached(section)
                    openWindow(value: section)
                }
            )
            // Keep the tab row above the content so a tab dragged downward to tear off stays visible
            // over the section area instead of being painted under it.
            .zIndex(1)

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
            // Warm the Toolchain tab's cold costs (SwiftData + preset parse) off the critical path so
            // its first open doesn't spike CPU/disk and glitch the soundtrack.
            session.warmUpToolchain()
            keyboardFocus = true
        }
        .onChange(of: session.settings.context) {
            session.persistLastUsedSettings()
        }
        // Feed the OS appearance into the theme store so the Light preset auto-applies in Light Mode.
        .onChange(of: colorScheme, initial: true) { _, scheme in
            AppStyleStore.shared.systemIsLight = (scheme == .light)
        }
        // Re-resolve the project when the app regains focus so a git branch switched in the terminal
        // is reflected in the checkout scheme (the branch is only read at validation time).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            session.refreshProjectOnActivation()
        }
        // NOTE: the build → soundtrack bridge and the initial stage seed live in AppSession (an
        // off-view snapshot consumer), NOT here. Reading `session.build.context` in this body — e.g.
        // to compute a SoundtrackBuildSnapshot for an onChange — subscribed the whole ContentView to
        // every build progress tick, recreating the title bar / tab bar / content on each one.
    }
}

#Preview {
    ContentView(session: .shared)
        .modelContainer(for: [BuildOperationRecord.self, SavedBuildProfile.self], inMemory: true)
}
