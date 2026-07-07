import SwiftXState

nonisolated enum AppSectionID: String, StateIdentifying, CaseIterable, Identifiable, Codable {
    case build
    case settings
    case toolchain
    case history
    case logs
    case inspector
    case style

    var id: String { rawValue }
    static var _blank: AppSectionID { .build }

    var title: String {
        switch self {
        case .build: String(localized: "Build")
        case .settings: String(localized: "Settings")
        case .toolchain: String(localized: "Toolchain")
        case .history: String(localized: "History")
        case .logs: String(localized: "Logs")
        case .inspector: String(localized: "Inspector")
        case .style: String(localized: "Style")
        }
    }

    var symbolName: String {
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

    var next: AppSectionID {
        let sections = Self.allCases
        guard let index = sections.firstIndex(of: self) else { return .build }
        return sections[sections.index(after: index) == sections.endIndex ? sections.startIndex : sections.index(after: index)]
    }

    var previous: AppSectionID {
        let sections = Self.allCases
        guard let index = sections.firstIndex(of: self) else { return .build }
        if index == sections.startIndex {
            return sections[sections.index(before: sections.endIndex)]
        }
        return sections[sections.index(before: index)]
    }
}
