nonisolated struct SoundtrackAudioRequest: Sendable, Equatable {
    let id: Int
    let command: SoundtrackAudioCommand
}

nonisolated enum SoundtrackAudioCommand: Sendable, Equatable {
    case play(TrackerStreamRequest, generation: Int, startImmediately: Bool)
    case pause(generation: Int)
    case resume(generation: Int)
    case stop(generation: Int)
    case setVolume(Double)
    case setEffects(SoundtrackEffectsSettings)
}
