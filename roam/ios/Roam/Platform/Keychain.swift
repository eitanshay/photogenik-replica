import Foundation
import Security

/// API keys and the Google refresh token live in the Keychain, never in UserDefaults.
enum Keychain {
    private static let service = "com.eitanshay.roam"

    enum Key: String {
        case googleMapsKey = "google-maps-api-key"
        case anthropicKey = "anthropic-api-key"
        case googleRefreshToken = "google-refresh-token"
    }

    private static func query(_ key: Key) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key.rawValue]
    }

    static func read(_ key: Key) -> String {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    static func write(_ key: Key, _ value: String) {
        SecItemDelete(query(key) as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = query(key)
        add[kSecValueData as String] = Data(trimmed.utf8)
        // Readable after first unlock so background wake-ups (geofence entry) can use the keys.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
