import Foundation
import Observation
import RouteBarKit

/// The local server's client API keys as Settings shows them.
@MainActor
@Observable
final class APIKeyState {
    /// Usable keys, masked, newest first.
    var keys: [APIKeyInfo] = []
    /// Keys whose full value RouteBar can copy: kept in the Keychain, or any key when OmniRoute allows reveal.
    var copyable: Set<String> = []
    var allowsReveal = false
    var isCreating = false
    /// The key RouteBar lists models with while OmniRoute requires one.
    var modelsKey: String?
    var ownKeyAttemptAt: Date?

    func reset() {
        keys = []
        copyable = []
        allowsReveal = false
        isCreating = false
        modelsKey = nil
        ownKeyAttemptAt = nil
    }
}

/// Client API keys for the server on this Mac: listing, copying and creating
/// them, and the key RouteBar itself needs for the model list once OmniRoute
/// requires one. Full keys are only ever kept in the Keychain, under the key's id.
extension AppModel {
    static let apiKeychain = Keychain(service: "com.spilneo.RouteBar.apikeys", label: "RouteBar: OmniRoute API key")
    /// Name of the key RouteBar creates; more get a number.
    private static let keyName = "RouteBar"

    /// Reads the key list while a key is required. Keys the Keychain holds for
    /// ids no longer on the server are removed.
    func refreshAPIKeys() async {
        guard !isRemote, server == .running, requiresAPIKey == true else {
            if !apiKeyState.keys.isEmpty { apiKeyState.keys = [] }
            return
        }
        let client = client, generation = generation
        guard let list = try? await client.apiKeys(), generation == self.generation else { return }
        let usable = list.keys.filter { $0.isUsable() }
        let stored = Set(list.keys.map(\.id).filter { Self.apiKeychain.read($0) != nil })
        let copyable = list.allowKeyReveal ? Set(usable.map(\.id)) : stored.intersection(usable.map(\.id))
        if apiKeyState.keys != usable { apiKeyState.keys = usable }
        if apiKeyState.copyable != copyable { apiKeyState.copyable = copyable }
        if apiKeyState.allowsReveal != list.allowKeyReveal { apiKeyState.allowsReveal = list.allowKeyReveal }
    }

    /// Copies a key in full: from the Keychain, or revealed by OmniRoute and then kept.
    /// Returns whether something was copied.
    @discardableResult
    func copyAPIKey(_ info: APIKeyInfo) async -> Bool {
        if let stored = Self.apiKeychain.read(info.id) {
            copy(stored)
            return true
        }
        let client = client
        do {
            let key = try await client.revealAPIKey(id: info.id)
            Self.apiKeychain.save(key, for: info.id)
            apiKeyState.copyable.insert(info.id)
            copy(key)
            return true
        } catch {
            show((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return false
        }
    }

    /// Creates a key for the user's apps, keeps it in the Keychain and copies it.
    func createAPIKey() {
        guard !apiKeyState.isCreating, !isRemote else { return }
        apiKeyState.isCreating = true
        Task {
            defer { apiKeyState.isCreating = false }
            do {
                let created = try await makeKey()
                copy(created.key)
                show("Created \(created.name ?? "an API key") and copied it")
            } catch {
                show("Could not create an API key: \(error.localizedDescription)")
            }
        }
    }

    /// The model list. Once OmniRoute requires an API key, RouteBar lists models
    /// with a key it keeps in the Keychain, creating one the first time.
    func fetchModels(client: OmniRouteClient) async throws -> [ModelEntry] {
        do {
            return try await client.models(apiKey: isRemote ? nil : apiKeyState.modelsKey)
        } catch OmniRouteError.apiKeyRequired where !isRemote {
            apiKeyState.modelsKey = nil
            guard let key = await ownAPIKey(client: client) else { throw OmniRouteError.apiKeyRequired }
            apiKeyState.modelsKey = key
            return try await client.models(apiKey: key)
        }
    }

    /// A usable key whose full value the Keychain holds, or a new one. Creating is
    /// tried at most once a minute so a refusing server is not filled with keys.
    func ownAPIKey(client: OmniRouteClient, announce: Bool = true) async -> String? {
        guard let list = try? await client.apiKeys() else { return nil }
        for info in list.keys where info.isUsable() {
            if let stored = Self.apiKeychain.read(info.id) { return stored }
        }
        guard isStale(apiKeyState.ownKeyAttemptAt, after: 60) else { return nil }
        apiKeyState.ownKeyAttemptAt = Date()
        guard let created = try? await makeKey(existing: list.keys) else { return nil }
        if announce { show("Created the API key \"\(created.name ?? Self.keyName)\" so RouteBar can list models") }
        return created.key
    }

    private func makeKey(existing: [APIKeyInfo]? = nil) async throws -> CreatedAPIKey {
        let client = client, generation = generation
        let names = Set((existing ?? apiKeyState.keys).compactMap(\.name))
        let name = ([Self.keyName] + (2...99).map { "\(Self.keyName) \($0)" }).first { !names.contains($0) } ?? Self.keyName
        let created = try await client.createAPIKey(name: name)
        guard Self.apiKeychain.save(created.key, for: created.id) else { throw AppModel.RemoteError.keychain }
        if generation == self.generation { await refreshAPIKeys() }
        return created
    }
}
