nonisolated enum SoundtrackPurpose: Sendable, Equatable, Hashable {
    case startup
    case stage(BuildStage)
    case success
    case failure
    case test
}
