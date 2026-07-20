import Foundation

/// Cross-platform localized-string lookup.
///
/// `String(localized:)` isn't part of swift-corelibs-foundation on Linux yet, so calling it directly
/// in SwiftRepoCore broke the Linux build. On Apple platforms this forwards to the real localization
/// (String Catalog lookup, `Bundle.main` — unchanged behavior); elsewhere it returns the base value
/// so the package still compiles and runs (English base strings on Linux for now).
#if canImport(Darwin)
nonisolated public func coreLocalized(_ value: String.LocalizationValue) -> String {
    String(localized: value)
}
#else
public func coreLocalized(_ value: String) -> String {
    value
}
#endif
