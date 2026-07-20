import Foundation

/// Bridges typed errors into machine `onError` strings. SwiftXState reports `String(describing:)`,
/// so this type makes that string user-facing.
nonisolated public struct PresentableError: Error, CustomStringConvertible, Sendable {
    public let message: String

    public init(_ error: any Error) {
        if let presentable = error as? PresentableError {
            message = presentable.message
        } else if let localized = error as? any LocalizedError,
                  let description = localized.errorDescription,
                  !description.isEmpty {
            message = description
        } else {
            message = String(describing: error)
        }
    }

    public var description: String { message }
}
