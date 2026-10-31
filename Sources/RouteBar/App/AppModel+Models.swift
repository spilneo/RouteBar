import Foundation
import RouteBarKit

/// Keeping the model list current with what each provider serves today.
///
/// OmniRoute stores a connection's models when it is added, so a model released
/// later (a new Haiku, say) stays missing until the list is fetched again. Each
/// provider is refreshed once per session when it first shows up as active, and
/// the button in the search field refreshes every active account on demand.
extension AppModel {
    /// Connections refreshed together, so many accounts never flood the server.
    private static let refreshBatch = 4

    /// Refreshes one active account of each provider not refreshed yet this session.
    func refreshNewProvidersModels() {
        guard !isRefreshingModels else { return }
        var picked: [String: String] = [:]
        for connection in connections where connection.isUsable && !modelRefreshedProviders.contains(connection.provider) {
            if picked[connection.provider] == nil, let id = connection.id { picked[connection.provider] = id }
        }
        guard !picked.isEmpty else { return }
        modelRefreshedProviders.formUnion(picked.keys)
        let generation = generation
        Task {
            let refreshed = await refreshModels(connectionIDs: Array(picked.values))
            guard refreshed > 0, generation == self.generation else { return }
            invalidateCatalog()
            await refresh()
        }
    }

    /// The search field's refresh button: every active account, then a short report.
    func refreshModelsNow() {
        guard !isRefreshingModels, server == .running else { return }
        let ids = connections.filter(\.isUsable).compactMap(\.id)
        guard !ids.isEmpty else { return show("Connect a provider to list its models") }
        isRefreshingModels = true
        let before = Set(models), generation = generation
        Task {
            defer { isRefreshingModels = false }
            let refreshed = await refreshModels(connectionIDs: ids)
            guard generation == self.generation else { return }
            invalidateCatalog()
            await refresh()
            let added = models.filter { !before.contains($0) }
            if refreshed == 0 {
                show("Could not refresh models. The providers did not answer.")
            } else if added.isEmpty {
                show("Models are up to date")
            } else if added.count <= 2 {
                show("New: " + ListFormatter.localizedString(byJoining: added))
            } else {
                show("Found \(added.count) new models")
            }
        }
    }

    /// Refreshes the given connections a few at a time. Returns how many succeeded.
    private func refreshModels(connectionIDs ids: [String]) async -> Int {
        let client = client
        var succeeded = 0
        for start in stride(from: 0, to: ids.count, by: Self.refreshBatch) {
            let batch = ids[start..<min(start + Self.refreshBatch, ids.count)]
            succeeded += await withTaskGroup(of: Bool.self) { group in
                for id in batch {
                    group.addTask { await (try? client.refreshModels(connectionID: id)) != nil }
                }
                var count = 0
                for await succeeded in group where succeeded {
                    count += 1
                }
                return count
            }
        }
        return succeeded
    }
}
