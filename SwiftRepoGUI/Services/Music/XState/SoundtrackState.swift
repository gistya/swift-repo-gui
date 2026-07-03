import SwiftXState

nonisolated enum SoundtrackState: String, StateIdentifying {
    case stopped
    case loading
    case playing
    case paused
    case failed

    static var _blank: SoundtrackState { .stopped }
}
