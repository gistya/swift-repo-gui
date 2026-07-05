import CompositionalInit
import Foundation

extension URL: @retroactive Blankable {
    nonisolated public static var _blank: Self { URL(string: "/")! }
}
