import Ox0badf00dAVFoundation
import SwiftXState

nonisolated enum SoundtrackEvent: EventIdentifying {
    case launch
    case buildSnapshotChanged(SoundtrackBuildSnapshot)
    case toggleMute
    case togglePause
    case previousTrack
    case nextTrack
    case playTestCue
    case setVolume(Double)
    case setInsertSlot(index: Int, component: AudioComponentRef?)
    case toggleInsertBypass(index: Int)
    case playbackPrepared(moduleTitle: String?, generation: Int, started: Bool)
    case playbackPaused(generation: Int)
    case playbackResumed(generation: Int)
    case playbackStopped(generation: Int)
    case trackFinished(generation: Int)
    case audioFailed(String, generation: Int?)
    case audioRequestHandled(Int)

    static var _blank: SoundtrackEvent { .launch }
}
