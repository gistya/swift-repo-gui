nonisolated struct TrackerStreamRequest: Sendable, Equatable {
    let track: TrackerModuleTrack
    let purpose: SoundtrackPurpose
    let sampleRate: Double
    let streamBufferFrames: Int
    let streamPrerollFrames: Int
    let streamRenderChunkFrames: Int
    let maxDuration: Double
    let tailDuration: Double
}
