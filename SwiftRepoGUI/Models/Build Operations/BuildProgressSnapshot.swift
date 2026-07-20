import CompositionalInit

nonisolated public struct BuildProgressSnapshot: Sendable, Equatable, Hashable, Blankable {
    public var completedSteps: Int
    public var totalSteps: Int
    public var fraction: Double
    public var etaSeconds: Double?
    public var message: String?
    /// The build phase this snapshot belongs to. Parsed from authoritative, line-anchored
    /// phase banners emitted by `build-script` (`--- Running tests for swift ---`, etc.) and
    /// carried forward between banners — NOT guessed from substrings of compiler output.
    public var stage: BuildStage = .building
    /// The target/module to show on the LCD (e.g. "libcxx", "swift", "Extracting symbols"). Only
    /// updated when a line yields a confident target or phase name; junk lines (warnings, `ld:`,
    /// shell `&&`) leave it untouched, so the display holds the last real target instead of flashing
    /// garbage. `nil` until the first real target is seen.
    public var moduleLabel: String? = nil

    public static let zero = Self(completedSteps: 0, totalSteps: 0, fraction: 0, etaSeconds: nil, message: nil, stage: .building, moduleLabel: nil)

    public static var _blank: Self { zero }
}
