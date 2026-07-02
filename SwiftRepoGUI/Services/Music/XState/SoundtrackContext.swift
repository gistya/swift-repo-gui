nonisolated struct SoundtrackContext: Sendable, Equatable {
    var phase: SoundtrackPhase = .stopped
    var isMuted = false
    var volume: Double = Double(SwiftBuilderStyle.current.sound.masterVolume)
    var effectsSettings: SoundtrackEffectsSettings = .default
    var currentTrack: TrackerModuleTrack?
    var nowPlaying: SoundtrackNowPlaying = .empty
    var activePurpose: SoundtrackPurpose = .startup
    var generation = 0
    var lastError: String?

    var isPaused: Bool { phase == .paused }
}
