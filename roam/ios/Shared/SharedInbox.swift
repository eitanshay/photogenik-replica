import Foundation
import Security

/// Hand-off from the share extension to the app through a shared Keychain group.
/// (A shared Keychain group needs no extra Apple portal setup, unlike an App Group: every App Store
/// profile already allows `<TeamID>.*` Keychain groups.)
enum SharedInbox {
    private static let service = "com.eitanshay.roam.inbox"
    private static let account = "inbox"
    private static let groupSuffix = "com.eitanshay.roam.shared"

    /// "<TeamID>.com.eitanshay.roam.shared". The Team ID is read from the default access group of a probe item.
    static let accessGroup: String? = {
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "com.eitanshay.roam.probe",
                                    kSecAttrAccount as String: "probe",
                                    kSecReturnAttributes as String: true]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(probe as CFDictionary, &result)
        if status == errSecItemNotFound {
            var add = probe
            add[kSecValueData as String] = Data("1".utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, &result)
        }
        guard status == errSecSuccess, let attrs = result as? [String: Any],
              let group = attrs[kSecAttrAccessGroup as String] as? String,
              let dot = group.firstIndex(of: ".") else { return nil }
        return String(group[...dot]) + groupSuffix
    }()

    private static var query: [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        if let g = accessGroup { q[kSecAttrAccessGroup as String] = g }
        return q
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func read() -> [Place] {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let places = try? decoder.decode([Place].self, from: data) else { return [] }
        return places
    }

    static func append(_ p: Place) {
        var items = read()
        items.append(p)
        guard let data = try? encoder.encode(items) else { return }
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }

    /// Moves everything into the library. Returns ids of the merged places.
    @discardableResult
    static func drain(into lib: inout PlaceLibrary) -> [String] {
        let items = read()
        guard !items.isEmpty else { return [] }
        clear()
        return items.map { lib.upsert($0) }
    }
}
