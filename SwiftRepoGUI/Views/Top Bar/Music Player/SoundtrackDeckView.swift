import SwiftUI

struct SoundtrackDeckView: View {
    let deck: SoundtrackDeckConfiguration
    
    // TODO: this is getting recreated over and over during a build... figure out why and fix it.
    @State private var isShowingEffects = false

    private var hasTrack: Bool {
        !deck.nowPlaying.detail.isEmpty
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 7) {
                trackReadout
                
                Spacer(minLength: 0)

                SoundtrackIconButton(
                    systemName: "backward.fill",
                    help: "Previous track",
                    isNotEngaged: false,
                    isDisabled: deck.isMuted || !hasTrack,
                    action: deck.onPreviousTrack
                )
                SoundtrackIconButton(
                    systemName: deck.isPaused ? "play.fill" : "pause.fill",
                    help: deck.isPaused ? "Resume soundtrack" : "Pause soundtrack",
                    isNotEngaged: deck.isPaused,
                    isDisabled: deck.isMuted || !hasTrack,
                    action: deck.onTogglePause
                )
                SoundtrackIconButton(
                    systemName: "forward.fill",
                    help: "Next track",
                    isNotEngaged: false,
                    isDisabled: deck.isMuted || !hasTrack,
                    action: deck.onNextTrack
                )
                SoundtrackIconButton(
                    systemName: "pianokeys",
                    help: "Effect inserts",
                    isNotEngaged: !(deck.insertSlots.contains { !$0.isEmpty && !$0.isBypassed }),
                    isDisabled: false,
                    action: {
                        // Kick off AU enumeration on first open (idempotent) — never at launch.
                        deck.onOpenEffects()
                        isShowingEffects.toggle()
                    }
                )
                .popover(isPresented: $isShowingEffects, arrowEdge: .bottom) {
                    InsertRackPopup(
                        slots: deck.insertSlots,
                        availableEffects: deck.availableEffects,
                        onSetInsert: deck.onSetInsert,
                        onToggleBypass: deck.onToggleBypass,
                        makeInsertEditor: deck.makeInsertEditor
                    )
                }
                SoundtrackIconButton(
                    systemName: deck.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    help: deck.isMuted ? "Unmute soundtrack" : "Mute soundtrack",
                    isNotEngaged: deck.isMuted,
                    isDisabled: false,
                    action: deck.onToggleMute
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.1.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(deck.isMuted ? Color.terminalDimGreen : Color.terminalGreen)
                    .accessibilityHidden(true)

                Slider(
                    value: Binding(
                        get: { deck.volume },
                        set: deck.onVolumeChange
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .tint(deck.isMuted ? Color.terminalDimGreen : Color.terminalGreen)
                .frame(maxWidth: 300)
                .accessibilityLabel("Soundtrack volume")
                .accessibilityValue("\(Int((deck.volume * 100).rounded()))%")

                Text("\(Int((deck.volume * 100).rounded()))")
                    .font(.monaco(size: 9, weight: .bold))
                    .foregroundStyle(deck.isMuted ? Color.terminalDimGreen : Color.terminalGreen)
                    .frame(width: 28, alignment: .trailing)
                    .accessibilityHidden(true)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nowPlayingLabel)
    }

    private var nowPlayingLabel: String {
        guard hasTrack else { return String(localized: "No track") }
        return String(
            format: NSLocalizedString(
                "Now playing: %@, %@",
                comment: "Soundtrack now-playing readout: track title, artist"
            ),
            deck.nowPlaying.title,
            deck.nowPlaying.artist
        )
    }
}
