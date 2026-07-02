import SwiftXState

nonisolated enum SoundtrackEvent: EventIdentifying {
    case restore(muted: Bool, volume: Double, effects: SoundtrackEffectsSettings)
    case setMuted(Bool)
    case setVolume(Double)
    case setEffects(SoundtrackEffectsSettings)
    case setPurpose(SoundtrackPurpose)
    case requestTrack(TrackerModuleTrack, purpose: SoundtrackPurpose, generation: Int)
    case trackReady(TrackerModuleTrack, moduleTitle: String?, generation: Int)
    case pause
    case resume
    case stop
    case fail(String)
    case finish

    static var _blank: SoundtrackEvent { .stop }
}
