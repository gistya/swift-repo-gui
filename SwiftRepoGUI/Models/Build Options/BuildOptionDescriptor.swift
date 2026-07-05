struct BuildOptionDescriptor: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let practicalAdvice: String
    let category: BuildOptionCategory
}
