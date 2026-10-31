import AppKit
import SwiftUI

/// `ROUTEBAR_SNAPSHOT=/path/panel.png` renders the panel with live data into a
/// PNG and quits. Used for README screenshots and visual checks.
@MainActor
enum Snapshot {
    static func runIfRequested(model: AppModel) -> Bool {
        guard let path = ProcessInfo.processInfo.environment["ROUTEBAR_SNAPSHOT"], !path.isEmpty else { return false }
        let dark = ProcessInfo.processInfo.environment["ROUTEBAR_SNAPSHOT_DARK"] == "1"
        Task {
            await model.refresh()
            try? await Task.sleep(for: .seconds(2)) // provider logos load asynchronously
            await model.refresh()
            let content = PanelView(model: model)
                .background(dark ? Color(white: 0.16) : Color(white: 0.97))
                .environment(\.colorScheme, dark ? .dark : .light)
            let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            let host = NSHostingView(rootView: content)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            window.setContentSize(host.fittingSize)
            window.orderFrontRegardless()
            try? await Task.sleep(for: .seconds(1))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
        return true
    }
}
