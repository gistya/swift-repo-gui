import Foundation
import Ox0badf00d

/// One user-assignable AudioUnit insert slot in the soundtrack signal chain. Pure context data (no
/// engine objects), so it lives in the machine's context and persists across launches. The chosen
/// AU is identified by its `Sendable`, `Codable` ``AudioComponentRef``; the live AU instance is owned
/// by the `TrackerAudioEngine` behind the scenes.
nonisolated struct SoundtrackInsertSlot: Sendable, Equatable, Codable {
    var component: AudioComponentRef?
    var isBypassed: Bool

    init(component: AudioComponentRef? = nil, isBypassed: Bool = false) {
        self.component = component
        self.isBypassed = isBypassed
    }

    var isEmpty: Bool { component == nil }
}

nonisolated enum SoundtrackInsertSlotsStore {
    static let defaultsKey = "SwiftBuilder.soundtrackInsertSlots"

    static func load(slotCount: Int, from defaults: UserDefaults = .standard) -> [SoundtrackInsertSlot] {
        var slots = Array(repeating: SoundtrackInsertSlot(), count: slotCount)
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([SoundtrackInsertSlot].self, from: data) {
            for (index, slot) in decoded.prefix(slotCount).enumerated() {
                slots[index] = slot
            }
        }
        return slots
    }

    static func save(_ slots: [SoundtrackInsertSlot], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(slots) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
