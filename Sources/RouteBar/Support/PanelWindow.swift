import AppKit
import SwiftUI

/// Keeps the menu bar window exactly as tall as the panel, with its top edge
/// pinned under the menu bar.
///
/// `MenuBarExtra` sizes its window when it opens but does not reliably follow
/// later changes in content height. Opening Settings clipped it at the top and
/// bottom, and going back left the taller window behind with empty space.
struct PanelWindowHeight: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> SizingView { SizingView() }

    func updateNSView(_ view: SizingView, context: Context) {
        view.height = height
    }

    final class SizingView: NSView {
        var height: CGFloat = 0 {
            didSet { if height != oldValue { scheduleResize() } }
        }

        private var isScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleResize()
        }

        /// Resizing during a SwiftUI update re-enters layout, so it waits for the next turn of the run loop.
        private func scheduleResize() {
            guard !isScheduled else { return }
            isScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                isScheduled = false
                resizeWindow()
            }
        }

        private func resizeWindow() {
            guard let window, height > 0 else { return }
            let content = window.contentRect(forFrameRect: window.frame)
            guard abs(content.height - height) > 0.5 else { return }
            let target = NSRect(x: content.minX, y: content.maxY - height, width: content.width, height: height)
            window.setFrame(window.frameRect(forContentRect: target), display: true, animate: false)
        }
    }
}
