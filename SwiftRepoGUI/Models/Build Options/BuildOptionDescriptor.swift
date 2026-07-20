public struct BuildOptionDescriptor: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let practicalAdvice: String
    public let category: BuildOptionCategory
}
