import AppKit
import SwiftUI

@main
struct RouteBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: delegate.model)
        } label: {
            Image(nsImage: MenuBarIcon.image(active: delegate.model.server == .running))
                .accessibilityLabel("RouteBar")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if Snapshot.runIfRequested(model: model) { return }
        model.launch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.terminate()
    }
}
