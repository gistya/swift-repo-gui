import CompositionalInit

nonisolated struct SoundtrackBuildSnapshot: Sendable, Equatable, Hashable, Blankable {
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
    
    static let _blank = Self(stage: .building, isRunning: false, succeeded: false)
}
