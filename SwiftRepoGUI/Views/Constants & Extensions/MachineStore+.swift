import SwiftXStateSwiftUI

extension MachineStore<BuildOperationsMachine> {
    var currentStage: BuildStage {
        if matches(.testing) { return .testing }
        if matches(.measuring) { return .measuring }
        if matches(.deploying) { return .deploying }
        if matches(.building) || matches(.running) { return .building }
        if matches(.error) { return .failed }
        return BuildStage.stage(for: context)
    }
}
