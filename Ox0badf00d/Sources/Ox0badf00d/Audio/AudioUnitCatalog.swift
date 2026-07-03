import AVFoundation

/// Discovers installed AudioUnit effects the user can drop into an insert slot. Wraps
/// `AVAudioUnitComponentManager` and returns `Sendable` ``AudioComponentRef`` values (not the live
/// component objects), so the result can cross actor/isolation boundaries freely.
public enum AudioUnitCatalog {
    /// All installed effect and music-effect AudioUnits, sorted by display name.
    public static func effects() -> [AudioComponentRef] {
        let manager = AVAudioUnitComponentManager.shared()
        let effectTypes: [OSType] = [
            kAudioUnitType_Effect,
            kAudioUnitType_MusicEffect,
        ]
        var seen = Set<String>()
        var refs: [AudioComponentRef] = []
        for type in effectTypes {
            let description = AudioComponentDescription(
                componentType: type,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            for component in manager.components(matching: description) {
                let ref = AudioComponentRef(component)
                if seen.insert(ref.id).inserted {
                    refs.append(ref)
                }
            }
        }
        return refs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
