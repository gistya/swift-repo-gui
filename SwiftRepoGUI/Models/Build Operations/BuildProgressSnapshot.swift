import CompositionalInit

nonisolated struct BuildProgressSnapshot: Sendable, Equatable, Hashable, Blankable {
    var completedSteps: Int
    var totalSteps: Int
    var fraction: Double
    var etaSeconds: Double?
    var message: String?

    static let zero = Self(completedSteps: 0, totalSteps: 0, fraction: 0, etaSeconds: nil, message: nil)
    
    static var _blank: Self { zero }
}
