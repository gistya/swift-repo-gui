/// An outbound notification from ``TrackerAudioEngine``. The engine takes imperative commands and
/// reports their observable outcome here, so a host can fold results back into its own state model
/// (e.g. a SwiftXState machine) instead of reading engine internals. `generation` echoes the value
/// the host passed to `play(...)`, letting stale results from a superseded track be ignored.
public enum TrackerAudioEvent: Sendable, Equatable {
    /// Enough audio is scheduled to begin; `started` is false when prepared into a paused state.
    case prepared(moduleTitle: String?, generation: Int, started: Bool)
    case paused(generation: Int)
    case resumed(generation: Int)
    case stopped(generation: Int)
    /// The track played to its natural end.
    case finished(generation: Int)
    case failed(message: String, generation: Int)
}
