import AVFoundation

/// A persistable, `Sendable` identity for an AudioUnit — the four-char-code triple that uniquely
/// names a component plus its display name. `AudioComponentDescription` itself is neither `Codable`
/// nor a stable persistence format, so hosts save/restore this instead (together with the AU's opaque
/// `fullState`, which ``TrackerAudioEngine`` exchanges as `Data`).
public struct AudioComponentRef: Sendable, Hashable, Codable, Identifiable {
    public var type: UInt32
    public var subType: UInt32
    public var manufacturer: UInt32
    public var name: String

    public var id: String { "\(type)-\(subType)-\(manufacturer)" }

    public init(type: UInt32, subType: UInt32, manufacturer: UInt32, name: String) {
        self.type = type
        self.subType = subType
        self.manufacturer = manufacturer
        self.name = name
    }

    public init(_ component: AVAudioUnitComponent) {
        let description = component.audioComponentDescription
        self.type = description.componentType
        self.subType = description.componentSubType
        self.manufacturer = description.componentManufacturer
        let manufacturerName = component.manufacturerName
        self.name = manufacturerName.isEmpty ? component.name : "\(manufacturerName): \(component.name)"
    }

    public var audioComponentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: type,
            componentSubType: subType,
            componentManufacturer: manufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }
}

/// A single automatable AudioUnit parameter, flattened out of the AU's parameter tree as a `Sendable`
/// value so a host UI can render sliders without touching the (non-`Sendable`) live AU objects.
public struct TrackerAUParameter: Sendable, Hashable, Identifiable {
    public var address: UInt64
    public var identifier: String
    public var displayName: String
    public var minValue: Float
    public var maxValue: Float
    public var value: Float
    public var unitName: String?

    public var id: UInt64 { address }
}
