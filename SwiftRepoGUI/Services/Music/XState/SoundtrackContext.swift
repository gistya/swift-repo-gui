import Foundation

nonisolated enum SoundtrackDefaults {
    static let mutedKey = "SwiftBuilder.soundtrackMuted"
    static let volumeKey = "SwiftBuilder.soundtrackVolume"
}

nonisolated struct SoundtrackBuildSnapshot: Sendable, Equatable, Hashable {
    var stage: BuildStage
    var isRunning: Bool
    var succeeded: Bool

    init(stage: BuildStage = .off, isRunning: Bool = false, succeeded: Bool = false) {
        self.stage = stage
        self.isRunning = isRunning
        self.succeeded = succeeded
    }

    init(_ context: BuildOperationsContext) {
        stage = BuildStage.stage(for: context)
        isRunning = context.isRunning
        succeeded = !context.isRunning && context.lastExitCode == 0
    }
}

nonisolated struct SoundtrackContext: Sendable, Equatable {
    static let insertSlotCount = 2

    var playbackPhase: SoundtrackPlaybackPhase = .stopped
    var isMuted: Bool
    var tracks: [TrackerModuleTrack]
    var currentTrack: TrackerModuleTrack?
    var activePurpose: SoundtrackPurpose = .startup
    var moduleTitle: String?
    var generation = 0
    var volume: Double
    var insertSlots: [SoundtrackInsertSlot] = []
    var lastError: String?
    var currentStage: BuildStage = .off
    var wasBuildRunning = false
    var startupPlayed = false
    var commandCounter = 0
    var pendingAudioRequest: SoundtrackAudioRequest?
    var soundStyle: SoundPalette

    static func initial(
        style: SoundPalette,
        tracks: [TrackerModuleTrack],
        defaults: UserDefaults = .standard
    ) -> SoundtrackContext {
        let savedVolume = defaults.object(forKey: SoundtrackDefaults.volumeKey) as? Double
        return SoundtrackContext(
            isMuted: defaults.bool(forKey: SoundtrackDefaults.mutedKey),
            tracks: tracks,
            volume: Self.clampedVolume(savedVolume ?? Double(style.masterVolume)),
            insertSlots: SoundtrackInsertSlotsStore.load(slotCount: Self.insertSlotCount, from: defaults),
            soundStyle: style
        )
    }

    var isPaused: Bool { playbackPhase == .paused }

    var nowPlaying: SoundtrackNowPlaying {
        currentTrack?.nowPlaying(moduleTitle: moduleTitle) ?? .empty
    }

    var canSelectTrack: Bool {
        !isMuted && !tracks.isEmpty
    }

    mutating func enqueue(_ command: SoundtrackAudioCommand) {
        commandCounter += 1
        pendingAudioRequest = SoundtrackAudioRequest(id: commandCounter, command: command)
    }

    static func clampedVolume(_ volume: Double) -> Double {
        min(1, max(0, volume))
    }
}
