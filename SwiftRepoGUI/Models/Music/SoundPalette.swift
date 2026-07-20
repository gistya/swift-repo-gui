nonisolated public struct SoundPalette: Codable, Equatable, Hashable, Sendable {
    public var sampleRate: Double
    public var masterVolume: Float
    public var scheduleAheadBuffers: Int
//    TODO: Implement the sound cues
//    public var startupCueDuration: Double
//    public var failureCueDuration: Double
//    public var successCueDuration: Double
    public var bufferSize: UInt32
    /// Limit of how long a track can be rendered.
    /// Avoids a situation where a track of infiinite length breaks us.
    public var maxRenderedTrackDuration: Double
    public var trackEndTailDuration: Double
    public var trackerModuleDirectory: String
    public var trackerModuleExtensions: [String]
}
