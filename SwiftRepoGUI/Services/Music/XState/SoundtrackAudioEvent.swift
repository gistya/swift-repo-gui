import SwiftXState

nonisolated enum SoundtrackAudioEvent: EventIdentifying {
    case requestTrack(TrackerModuleTrack, purpose: SoundtrackPurpose, generation: Int)
    case trackReady(moduleTitle: String?, generation: Int)
    case setVolume(Double)
    case setEffects(SoundtrackEffectsSettings)
    case play
    case pause
    case stop
    case fail(String)

    static var _blank: SoundtrackAudioEvent { .stop }
}
