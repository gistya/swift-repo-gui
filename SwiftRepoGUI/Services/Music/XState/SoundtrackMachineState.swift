import SwiftXState

nonisolated enum SoundtrackMachineState: String, StateIdentifying {
    case playback
    case playing
    case notPlaying
    case tubeRack
    case tubeRackOn
    case tubeRackOff
    static var _blank: SoundtrackMachineState { .playback }
}
