nonisolated public struct GradientStop: Codable, Equatable, Sendable {
    public var color: StyleColor
    public var location: Double
    
    public init(color: StyleColor, location: Double) {
        self.color = color
        self.location = location
    }
}
