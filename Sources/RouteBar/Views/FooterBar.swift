import SwiftUI

/// Every secondary action as an icon button. Toggles tint when on, and each
/// button explains itself on hover. Nothing hides behind a menu.
struct FooterBar: View {
    @Bindable var model: AppModel

    var body: some View {
        let preferences = model.preferences
        HStack(spacing: 2) {
            IconButton(
                systemImage: "square.and.arrow.down",
                help: "Import logins from this Mac now",
                isBusy: model.isImporting
            ) { model.importLoginsNow() }
                .disabled(model.server != .running || model.isImporting)

            IconButton(
                systemImage: "sparkles",
                help: preferences.autoImport
                    ? "New logins on this Mac are connected automatically. Click to turn off."
                    : "Automatic login import is off. Click to turn on.",
                isOn: preferences.autoImport
            ) { preferences.autoImport.toggle() }

            IconButton(
                systemImage: "autostartstop",
                help: preferences.opensAtLogin
                    ? "RouteBar opens at login. Click to turn off."
                    : "Open RouteBar at login",
                isOn: preferences.opensAtLogin
            ) {
                preferences.setOpensAtLogin(!preferences.opensAtLogin)
                if let error = preferences.loginItemError { model.show("Could not change Open at Login: \(error)") }
            }

            IconButton(systemImage: "doc.text.magnifyingglass", help: "Show the OmniRoute log in Finder") {
                model.revealLog()
            }

            Spacer()

            IconButton(systemImage: "rectangle.portrait.and.arrow.right", help: "Quit RouteBar") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
