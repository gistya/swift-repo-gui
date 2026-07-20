nonisolated public struct SoundtrackNowPlaying: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let detail: String

    public var isEmpty: Bool {
        title.isEmpty && artist.isEmpty
    }

    public static let empty = SoundtrackNowPlaying(
        title: "NO TRACK",
        artist: "TRACKER OFFLINE",
        detail: ""
    )
}
