nonisolated struct PreparedTrackerStream: Sendable {
    let track: TrackerModuleTrack
    let succeeded: Bool
    let moduleTitle: String?
    let errorMessage: String?
}
