import SwiftUI

/// Every secondary action as an icon button, each explained on hover.
/// Preferences live on the Settings screen behind the gear.
struct FooterBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            IconButton(
                systemImage: "square.and.arrow.down",
                help: model.isRemote ? "Logins are imported only into the OmniRoute on this Mac" : "Import logins from this Mac now",
                isBusy: model.isImporting
            ) { model.importLoginsNow() }
                .disabled(model.isRemote || model.server != .running || model.isImporting)

            IconButton(systemImage: "doc.text.magnifyingglass", help: "Show the OmniRoute log in Finder") {
                model.revealLog()
            }
            .disabled(model.isRemote)

            IconButton(systemImage: "gearshape", help: "Settings") {
                withAnimation(.snappy(duration: 0.22)) { model.showsSettings = true }
            }
            .keyboardShortcut(",")

            Spacer()

            IconButton(systemImage: "rectangle.portrait.and.arrow.right", help: "Quit RouteBar") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
