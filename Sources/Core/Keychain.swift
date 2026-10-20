import Foundation
import Security

enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.mathieuletyrant.habar",
        kSecAttrAccount as String: "token",
    ]

    static func get() -> String {
        var q = query
        q[kSecReturnData as String] = true
        var out: AnyObject?
        SecItemCopyMatching(q as CFDictionary, &out)
        return (out as? Data).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    static func set(_ value: String) {
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}
