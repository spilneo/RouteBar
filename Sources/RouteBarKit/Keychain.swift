import Foundation
import Security

/// Small wrapper over generic-password Keychain items, used for remote access
/// tokens and OmniRoute API keys.
public struct Keychain: Sendable {
    public let service: String
    /// What Keychain Access shows for the items.
    public let label: String

    public init(service: String, label: String = "RouteBar: OmniRoute access token") {
        self.service = service
        self.label = label
    }

    public func read(_ account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func save(_ value: String, for account: String) -> Bool {
        let data = Data(value.utf8)
        let status = SecItemUpdate(base(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = base(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel as String] = label
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    public func delete(_ account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }

    private func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
