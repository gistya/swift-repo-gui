import Ox0badf00dAVFoundation
import AppKit

struct SoundtrackDeckConfiguration {
    let nowPlaying: SoundtrackNowPlaying
    let isMuted: Bool
    let isPaused: Bool
    let volume: Double
    let insertSlots: [SoundtrackInsertSlot]
    let availableEffects: [AudioComponentRef]
    let audioError: String?
    let onToggleMute: () -> Void
    let onTogglePause: () -> Void
    let onPreviousTrack: () -> Void
    let onNextTrack: () -> Void
    let onVolumeChange: (Double) -> Void
    let onSetInsert: (Int, AudioComponentRef?) -> Void
    let onToggleBypass: (Int) -> Void
    let onOpenEffects: () -> Void
    let makeInsertEditor: (Int) async -> NSViewController?
}
