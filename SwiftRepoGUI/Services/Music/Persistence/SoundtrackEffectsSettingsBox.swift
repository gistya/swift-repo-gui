import Foundation

nonisolated final class SoundtrackEffectsSettingsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: SoundtrackEffectsSettings

    init(_ settings: SoundtrackEffectsSettings) {
        storage = settings.normalized()
    }

    func get() -> SoundtrackEffectsSettings {
        lock.withLock { storage }
    }

    func set(_ settings: SoundtrackEffectsSettings) {
        lock.withLock {
            storage = settings.normalized()
        }
    }
}
