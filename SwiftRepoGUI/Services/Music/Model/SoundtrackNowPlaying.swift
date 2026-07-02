nonisolated struct SoundtrackNowPlaying: Equatable, Sendable {
    let title: String
    let artist: String
    let detail: String

    var isEmpty: Bool {
        title.isEmpty && artist.isEmpty
    }

    static let empty = SoundtrackNowPlaying(
        title: "NO TRACK",
        artist: "TRACKER OFFLINE",
        detail: ""
    )
}
