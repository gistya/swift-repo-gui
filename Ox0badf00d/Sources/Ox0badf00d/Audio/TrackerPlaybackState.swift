/// The playback lifecycle of a tracker soundtrack, vended as a plain enum with **no** SwiftXState
/// dependency. A host that uses SwiftXState can adopt it as a machine `StateID` with a one-line
/// conformance extension (`extension TrackerPlaybackState: StateIdentifying { … }`), which is exactly
/// how SwiftRepoGUI drives its soundtrack machine — the audio engine stays framework-agnostic.
public enum TrackerPlaybackState: String, Sendable, Hashable, CaseIterable {
    case stopped
    case loading
    case playing
    case paused
    case failed
}
