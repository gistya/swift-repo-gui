nonisolated public enum MusicSettings {
    public static let current: SoundPalette = SoundPalette(
        sampleRate: 44_100,
        masterVolume: 0.45,
        scheduleAheadBuffers: 4,
//        TODO: Implement the sound cues
//        startupCueDuration: 2.2,
//        failureCueDuration: 1.7,
//        successCueDuration: 1.0,
        bufferSize: 2048,
        maxRenderedTrackDuration: 600,
        trackEndTailDuration: 2,
        trackerModuleDirectory: "TrackerModules",
        trackerModuleExtensions: ["mod", "xm", "it"],
    )
}
