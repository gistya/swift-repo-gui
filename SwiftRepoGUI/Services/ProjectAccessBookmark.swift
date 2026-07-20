import Foundation

/// Persists a security-scoped bookmark to the user-chosen project root.
///
/// Under the App Sandbox, picking a folder in an `NSOpenPanel` grants access only for the current
/// launch. To reach the project again next launch — anywhere on disk, not just under `~/` — we save
/// a security-scoped bookmark and re-open it at startup. The scope is started once and deliberately
/// left open for the whole app lifetime so the `git` / `ninja` / `build-script` subprocesses the
/// build spawns inherit that access too.
///
/// Security-scoped bookmarks are an Apple-sandbox concept and don't exist in swift-corelibs-foundation
/// on Linux, so the real implementation is Darwin-only. Linux has no sandbox — a chosen folder is
/// reachable by path directly — so the Linux build gets a no-op stub until a Linux front-end wires up
/// plain-path persistence.
public final class ProjectAccessBookmark {
    private let defaultsKey = "projectRootBookmark"
    private let defaults: UserDefaults

    /// The directory whose security scope is currently held open (nil until stored/restored).
    private(set) var activeURL: URL?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

#if canImport(Darwin)
    /// Save a bookmark for a freshly picked directory and begin accessing it. `url` must come from
    /// the powerbox (`NSOpenPanel`) so it carries a security scope. Returns whether access started.
    @discardableResult
    public func store(pickedURL url: URL) -> Bool {
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return false
        }
        defaults.set(data, forKey: defaultsKey)
        return beginAccessing(url)
    }

    /// Resolve the stored bookmark and begin accessing it. Returns the resolved URL (the folder may
    /// have moved since it was picked — the bookmark tracks it), or nil if there is no bookmark or it
    /// can't be resolved, in which case the user must pick the folder again.
    @discardableResult
    public func restore() -> URL? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        guard beginAccessing(url) else { return nil }
        // Now that the scope is held, refresh a stale bookmark so it keeps resolving.
        if isStale, let refreshed = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(refreshed, forKey: defaultsKey)
        }
        return url
    }

    private func beginAccessing(_ url: URL) -> Bool {
        if let active = activeURL {
            if active == url { return true }
            active.stopAccessingSecurityScopedResource()
            activeURL = nil
        }
        guard url.startAccessingSecurityScopedResource() else { return false }
        activeURL = url
        return true
    }
#else
    /// Linux stub: no sandbox, so the picked folder is reachable directly. We simply remember it for
    /// this launch; cross-launch persistence (plain path) is the Linux front-end's job to add.
    @discardableResult
    public func store(pickedURL url: URL) -> Bool {
        activeURL = url
        return true
    }

    /// Linux stub: no bookmark to resolve.
    @discardableResult
    public func restore() -> URL? { nil }
#endif
}
