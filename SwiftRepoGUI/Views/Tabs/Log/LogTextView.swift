import AppKit
import SwiftRepoCore
import SwiftUI

/// Shared `NSTextView`-backed log renderer.
///
/// SwiftUI `Text` lays out its entire string synchronously on the main thread with no
/// virtualization — dumping a few-hundred-KB build log (with the long, unwrapped lines typical of
/// compiler invocations) into one `Text` freezes the run loop while TextKit lays out every glyph.
/// `NSTextView` lays out incrementally and stays responsive, so both the live tail (`LogFileView`)
/// and the completed-log viewer (`HistoryLogFileView`) render through this instead.
struct LogTextView: NSViewRepresentable {
    /// How the view repositions when `text` changes.
    enum Scroll {
        /// Jump to the top — a completed log opened once.
        case top
        /// Pin to the newest output — live tailing with auto-scroll on.
        case tail
        /// Keep the user's current scroll position — live tailing with auto-scroll off.
        case preserve
    }

    let text: String
    var scroll: Scroll = .top
    // Theme as reactive inputs (defaulted from the live style). When the theme changes the parent
    // re-renders, these re-evaluate, and `updateNSView` re-colors the text view — so the log panel
    // follows Light/Dark and custom colors like the rest of the UI.
    var background: Color = .terminalBlack
    var foreground: Color = .terminalGreen
    var fontName: String = SwiftBuilderStyle.current.fonts.monospaceName

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .lineBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(background)

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(background)
        textView.textColor = NSColor(foreground)
        textView.insertionPointColor = NSColor(foreground)
        textView.font = NSFont(name: fontName, size: 11)
            ?? .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.attributes = [
            .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: textView.textColor ?? NSColor(foreground),
        ]
        context.coordinator.currentBackground = background
        context.coordinator.currentForeground = foreground
        context.coordinator.currentFontName = fontName
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        applyThemeIfNeeded(scrollView, context: context)
        let previous = context.coordinator.currentText
        guard previous != text else { return }
        context.coordinator.currentText = text
        guard let textView = context.coordinator.textView else { return }

        // Fast path: the log grew by appending (the overwhelmingly common case while tailing). Mutate
        // ONLY the newly-added tail instead of replacing the whole string. A full `textView.string =`
        // tears down and relays out every glyph, resets the scroll origin, and drops the selection —
        // which is exactly the mid-scroll "glitch". Appending touches nothing above, so the user's
        // scroll position and selection are preserved with no work.
        if !previous.isEmpty, text.hasPrefix(previous), let storage = textView.textStorage {
            let delta = String(text[text.index(text.startIndex, offsetBy: previous.count)...])
            if !delta.isEmpty {
                storage.append(NSAttributedString(string: delta, attributes: context.coordinator.attributes))
            }
            switch scroll {
            case .tail:
                textView.scrollToEndOfDocument(nil)
            case .top, .preserve:
                break // content added below the viewport → position already preserved
            }
            return
        }

        // Slow path: reset or front-trim (the 256 KB cap dropped leading bytes), so the text is no
        // longer a pure extension. Replace, then keep the viewport a constant distance from the
        // bottom — with the top trimmed and the tail extended, that holds the user roughly in place.
        let clip = scrollView.contentView
        let bottomGap = max(0, textView.frame.height - (clip.bounds.origin.y + clip.bounds.height))
        textView.string = text

        switch scroll {
        case .top:
            clip.scroll(to: .zero)
            scrollView.reflectScrolledClipView(clip)
        case .tail:
            textView.scrollToEndOfDocument(nil)
        case .preserve:
            if let layoutManager = textView.layoutManager, let container = textView.textContainer {
                layoutManager.ensureLayout(for: container)
            }
            let targetY = max(0, textView.frame.height - clip.bounds.height - bottomGap)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: targetY))
            scrollView.reflectScrolledClipView(clip)
        }
    }

    /// Re-color the text view when the theme inputs change (Light/Dark switch or custom colors).
    private func applyThemeIfNeeded(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        guard coord.currentBackground != background
            || coord.currentForeground != foreground
            || coord.currentFontName != fontName else { return }
        coord.currentBackground = background
        coord.currentForeground = foreground
        coord.currentFontName = fontName

        let bg = NSColor(background)
        let fg = NSColor(foreground)
        let font = NSFont(name: fontName, size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .regular)
        scrollView.backgroundColor = bg
        guard let textView = coord.textView else { return }
        textView.backgroundColor = bg
        textView.textColor = fg
        textView.insertionPointColor = fg
        textView.font = font
        if let storage = textView.textStorage, storage.length > 0 {
            let whole = NSRange(location: 0, length: storage.length)
            storage.addAttribute(.foregroundColor, value: fg, range: whole)
            storage.addAttribute(.font, value: font, range: whole)
        }
        coord.attributes = [.font: font, .foregroundColor: fg]
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var currentText = ""
        var attributes: [NSAttributedString.Key: Any] = [:]
        var currentBackground: Color?
        var currentForeground: Color?
        var currentFontName: String?
    }
}

private extension NSColor {
    convenience init(_ styleColor: StyleColor) {
        self.init(
            calibratedRed: styleColor.red,
            green: styleColor.green,
            blue: styleColor.blue,
            alpha: styleColor.opacity
        )
    }
}
