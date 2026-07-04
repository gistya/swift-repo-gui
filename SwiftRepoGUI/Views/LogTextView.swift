import AppKit
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

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .lineBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(SwiftBuilderStyle.current.colors.terminalBlack)

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(SwiftBuilderStyle.current.colors.terminalBlack)
        textView.textColor = NSColor(SwiftBuilderStyle.current.colors.terminalGreen)
        textView.insertionPointColor = NSColor(SwiftBuilderStyle.current.colors.terminalGreen)
        textView.font = NSFont(name: SwiftBuilderStyle.current.fonts.monospaceName, size: 11)
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
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard context.coordinator.currentText != text else { return }
        context.coordinator.currentText = text
        guard let textView = context.coordinator.textView else { return }

        let previousOrigin = scrollView.contentView.bounds.origin
        textView.string = text

        switch scroll {
        case .top:
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        case .tail:
            textView.scrollToEndOfDocument(nil)
        case .preserve:
            scrollView.contentView.scroll(to: previousOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var currentText = ""
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
