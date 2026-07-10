import Foundation
import Ox0badf00dAVFoundation

/// An imperative audio instruction the machine hands to ``SoundtrackEffectDriver``, which forwards it
/// to the `TrackerAudioEngine`. Enqueued into context (``SoundtrackContext/enqueue(_:)``) so the
/// machine's intent stays part of its observable state; the driver executes it and folds the outcome
/// back in as an event.
nonisolated struct SoundtrackAudioRequest: Sendable, Equatable {
    let id: Int
    let command: SoundtrackAudioCommand
}

nonisolated enum SoundtrackAudioCommand: Sendable, Equatable {
    case play(url: URL, generation: Int, startImmediately: Bool)
    case pause(generation: Int)
    case resume(generation: Int)
    case stop(generation: Int)
    case setVolume(Double)
    case setInsert(index: Int, component: AudioComponentRef?)
    case setInsertBypass(index: Int, bypassed: Bool)
}
