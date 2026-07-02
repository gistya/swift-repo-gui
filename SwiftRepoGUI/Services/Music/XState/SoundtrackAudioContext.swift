nonisolated struct SoundtrackAudioContext: Sendable, Equatable {
    var phase: SoundtrackAudioPhase = .stopped
    var currentTrack: TrackerModuleTrack?
    var activePurpose: SoundtrackPurpose = .startup
    var moduleTitle: String?
    var generation = 0
    var volume: Double = Double(SwiftBuilderStyle.current.sound.masterVolume)
    var effectsSettings: SoundtrackEffectsSettings = .default
    var lastError: String?
}
