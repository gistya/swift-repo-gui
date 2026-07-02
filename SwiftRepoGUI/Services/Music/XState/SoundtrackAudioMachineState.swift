import SwiftXState

nonisolated enum SoundtrackAudioMachineState: String, StateIdentifying {
    case playback
    case playing
    case notPlaying
    case tubeRack
    case tubeRackOn
    case tubeRackOff
    static var _blank: SoundtrackAudioMachineState { .playback }
}
