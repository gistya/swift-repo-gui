import SwiftXStateSwiftUI

extension MachineStore<BuildOperationsMachine> {
    /// The build phase for the retro title-bar LEDs/LCD.
    ///
    /// This deliberately derives from `context.progress.stage` (parsed from authoritative phase
    /// banners) rather than `matches(.deploying)` etc. `matches(_ id:)` is intentionally
    /// **non-descending**: for a compound config `running.deploying` it only checks the top-level
    /// keys (`[running]`), so `matches(.deploying)` is `false` while `matches(.running)` is `true` —
    /// which pinned the LEDs to `.building` no matter the real substate. `stage(for:)` reads the
    /// substate the machine actually entered (the inspector agrees), so the two can't diverge.
    var currentStage: BuildStage {
        BuildStage.stage(for: context)
    }
}
