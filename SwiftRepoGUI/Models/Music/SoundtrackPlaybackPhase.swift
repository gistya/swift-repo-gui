nonisolated public enum SoundtrackPlaybackPhase: String, Sendable, Equatable {
    case stopped
    case loading
    case playing
    case paused
    case failed
}
