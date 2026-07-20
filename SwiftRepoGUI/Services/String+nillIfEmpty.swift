extension String {
    nonisolated public  var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
