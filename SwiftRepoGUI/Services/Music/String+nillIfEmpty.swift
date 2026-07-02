extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
