import AVFoundation

/// All the tunables ``TrackerAudioEngine`` needs, in one Sendable value. This is the "session
/// properties" surface: sample rate, the engine render quantum (there is no `AVAudioSession` on
/// macOS, so buffer sizing goes through the output unit's `maximumFramesToRender`), how far ahead to
/// schedule, how many user insert slots to expose, and the module-render parameters.
public struct AudioSessionConfig: Sendable, Equatable {
    /// Output sample rate in Hz. Drives both the engine format and the module renderer.
    public var sampleRate: Double
    /// Output channel count (tracker output is stereo).
    public var channelCount: AVAudioChannelCount
    /// Upper bound on the output unit's render quantum — the macOS analog of an IO buffer size.
    /// Preroll/chunk sizes are derived from this so producer and consumer agree.
    public var maximumFramesToRender: AVAudioFrameCount
    /// Frames rendered per scheduled buffer.
    public var renderChunkFrames: Int
    /// How many buffers to keep scheduled ahead of playback (completion-driven refill target).
    public var scheduleAheadBuffers: Int
    /// Number of user-assignable AudioUnit insert slots between the player and the master limiter.
    public var insertSlotCount: Int
    /// Insert a fixed Apple `PeakLimiter` as a master safety node at the end of the chain.
    public var enableMasterLimiter: Bool
    /// Hard cap on rendered track length (seconds), so a non-terminating module cannot render forever.
    public var maxTrackDuration: Double
    /// Fade-out/tail rendered after the song's natural end (seconds).
    public var tailDuration: Double
    /// Linear gain applied by the renderer before the engine graph.
    public var gain: Double
    /// Spatialization mode passed through to the module renderer.
    public var spatialization: SpatializationMode

    public init(
        sampleRate: Double = 44_100,
        channelCount: AVAudioChannelCount = 2,
        maximumFramesToRender: AVAudioFrameCount = 4_096,
        renderChunkFrames: Int = 4_096,
        scheduleAheadBuffers: Int = 3,
        insertSlotCount: Int = 2,
        enableMasterLimiter: Bool = true,
        maxTrackDuration: Double = 600,
        tailDuration: Double = 2,
        gain: Double = 1,
        spatialization: SpatializationMode = .psychoacoustic3D(.spacious)
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.maximumFramesToRender = maximumFramesToRender
        self.renderChunkFrames = max(256, renderChunkFrames)
        self.scheduleAheadBuffers = max(2, scheduleAheadBuffers)
        self.insertSlotCount = max(0, insertSlotCount)
        self.enableMasterLimiter = enableMasterLimiter
        self.maxTrackDuration = maxTrackDuration
        self.tailDuration = tailDuration
        self.gain = gain
        self.spatialization = spatialization
    }
}
