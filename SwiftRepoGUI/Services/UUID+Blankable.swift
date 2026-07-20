import CompositionalInit
import Foundation

extension UUID: @retroactive Blankable {
    nonisolated public static var _blank: Self { UUID() }
}
