import SwiftXState

nonisolated enum SoundtrackState: String, StateIdentifying {
    case playback
    case stopped
    case loading
    case playing
    case paused
    case failed
    case tubeRack
    case tubeRackOn
    case tubeRackOff

    static var _blank: SoundtrackState { .playback }
}
