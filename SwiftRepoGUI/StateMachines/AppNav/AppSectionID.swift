import SwiftXState
import Foundation

nonisolated public enum AppSectionID: String, StateIdentifying, CaseIterable, Identifiable, Codable {
    case build
    case settings
    case toolchain
    case history
    case logs
    case inspector
    case style

    public var id: String { rawValue }
    public static var _blank: AppSectionID { .build }

    public var title: String {
        switch self {
        case .build: coreLocalized("Build")
        case .settings: coreLocalized("Settings")
        case .toolchain: coreLocalized("Toolchain")
        case .history: coreLocalized("History")
        case .logs: coreLocalized("Logs")
        case .inspector: coreLocalized("Inspector")
        case .style: coreLocalized("Style")
        }
    }

    public var symbolName: String {
        switch self {
        case .build: "hammer"
        case .settings: "slider.horizontal.3"
        case .toolchain: "shippingbox"
        case .history: "clock.arrow.circlepath"
        case .logs: "doc.text"
        case .inspector: "waveform.path.ecg.rectangle"
        case .style: "paintpalette"
        }
    }

    public var next: AppSectionID {
        let sections = Self.allCases
        guard let index = sections.firstIndex(of: self) else { return .build }
        return sections[sections.index(after: index) == sections.endIndex ? sections.startIndex : sections.index(after: index)]
    }

    public var previous: AppSectionID {
        let sections = Self.allCases
        guard let index = sections.firstIndex(of: self) else { return .build }
        if index == sections.startIndex {
            return sections[sections.index(before: sections.endIndex)]
        }
        return sections[sections.index(before: index)]
    }
}
