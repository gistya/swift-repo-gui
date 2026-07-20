import Foundation

nonisolated public func localizedErrorMessage(for error: any Error) -> String {
    if let presentable = error as? PresentableError {
        return presentable.message
    }
    if let localized = error as? any LocalizedError,
       let description = localized.errorDescription,
       !description.isEmpty
    {
        return description
    }
    return String(describing: error)
}


