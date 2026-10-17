import Foundation
import Security

enum KeychainStoreError: Error { case invalid, unavailable }

/// One Codable value under one Keychain item, readable only while this device is unlocked.
struct KeychainStore<Value: Codable> {
    let service: String
    let account: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func load() -> Value? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
    func save(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw KeychainStoreError.unavailable }
        } else if update != errSecSuccess { throw KeychainStoreError.unavailable }
    }
    func clear() { SecItemDelete(query as CFDictionary) }
}
