import Foundation
import RouteBarKit

/// Connecting the AI tools already signed in on this Mac.
extension AppModel {
    /// Runs every importer OmniRoute offers, then names what was added using
    /// OmniRoute's own provider catalog. Automatic runs skip importers that can
    /// show a macOS permission prompt, a manual run includes them.
    func importLogins(includeInteractive: Bool) async {
        guard !isImporting else { return }
        isImporting = true
        importedThisSession = true
        defer { isImporting = false }

        let before = await Set(((try? client.connections()) ?? []).map(\.provider))
        let importer = LoginImporter(client: client)
        // Off the main actor: reading a Keychain item blocks on a child process.
        let failures = await Task.detached(priority: .utility) {
            await importer.run(connected: before, includeInteractive: includeInteractive)
        }.value
        let after = await (try? client.connections()) ?? []
        let added = Dashboard.tiles(connections: after.filter { !before.contains($0.provider) }, catalog: catalog)

        if !added.isEmpty {
            show("Connected " + ListFormatter.localizedString(byJoining: added.map(\.name)))
            await refresh()
        } else if let failure = failures.first {
            let name = Dashboard.displayName(for: failure.source, catalog: catalog)
            show("Could not import the \(name) login: \(failure.message)")
        } else if includeInteractive {
            show("No new logins found on this Mac")
        }
    }

    func importLoginsNow() {
        Task { await importLogins(includeInteractive: true) }
    }
}
