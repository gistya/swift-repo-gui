import SwiftUI
#if canImport(AppKit)
import AppKit

/// Presents an AudioUnit's own editor in a real, free-floating macOS window — standard title bar,
/// close box, minimize, and resize — instead of an embedded sheet. Plugin UIs then get their natural
/// size and normal window chrome. One window per insert slot; re-opening a slot reveals the window
/// that's already up rather than spawning duplicates.
@MainActor
final class AudioUnitEditorWindowManager {
    static let shared = AudioUnitEditorWindowManager()

    private var windows: [Int: NSWindow] = [:]
    private var delegates: [Int: WindowClosingDelegate] = [:]

    /// Brings the editor window for `slot` to the front if one is already open. Returns whether there
    /// was a window to reveal — lets a caller skip building a fresh AU view controller needlessly.
    @discardableResult
    func reveal(slot: Int) -> Bool {
        guard let window = windows[slot] else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// Opens (or reveals) the editor window for `slot`, hosting `controller` — the AU's own view
    /// controller, or a fallback for AUs with no custom UI. Sized to the controller's natural size.
    func show(slot: Int, title: String, controller: NSViewController) {
        if reveal(slot: slot) { return }

        let window = NSWindow(contentViewController: controller)
        // Standard free-floating window chrome: title bar, close box, minimize, resize.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = title
        // We own the lifetime via `windows`; closing must not release it out from under us.
        window.isReleasedWhenClosed = false
        window.setContentSize(preferredSize(for: controller))
        window.setFrameAutosaveName("AudioUnitEditor.slot\(slot)")
        window.center()

        let delegate = WindowClosingDelegate { [weak self] in
            self?.windows[slot] = nil
            self?.delegates[slot] = nil
        }
        window.delegate = delegate
        windows[slot] = window
        delegates[slot] = delegate
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the editor window for `slot` if open — e.g. the insert was changed or cleared, which
    /// makes the hosted AU view stale.
    func close(slot: Int) {
        windows[slot]?.close()
    }

    private func preferredSize(for controller: NSViewController) -> NSSize {
        let candidates = [controller.preferredContentSize, controller.view.frame.size, controller.view.fittingSize]
        for size in candidates where size.width > 1 && size.height > 1 {
            return size
        }
        return NSSize(width: 480, height: 320)
    }
}

private final class WindowClosingDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}

/// Shown when an AudioUnit exposes no custom view controller, so the editor window still opens with
/// something meaningful instead of silently doing nothing.
struct NoPluginInterfaceView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text("This AudioUnit has no custom interface.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(width: 360, height: 200)
    }
}
#endif
