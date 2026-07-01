import Foundation

nonisolated func localizedErrorMessage(for error: any Error) -> String {
    if let presentable = error as? PresentableError {
        return presentable.message
    }
    if let localized = error as? any LocalizedError,
       let description = localized.errorDescription,
       !description.isEmpty {
        return description
    }
    return String(describing: error)
}

/// Bridges typed errors into machine `onError` strings. SwiftXState reports `String(describing:)`,
/// so this type makes that string user-facing.
nonisolated struct PresentableError: Error, CustomStringConvertible, Sendable {
    let message: String

    init(_ error: any Error) {
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

    var description: String { message }
}