import Foundation
import Security

enum KeychainStore {
    static let museAPIKeyAccount = "muse-api-key"
    static let spaceXAIKeyAccount = "spacexai-api-key"
    static let rewriteCustomKeyAccount = "rewrite-custom-api-key"
    private static let service = "com.zertyn.granipa"
    private static let museKeyCache = MuseKeyCache()

    static func hasMuseKey() -> Bool {
        if let cached = museKeyCache.get() { return cached }
        let present = get(account: museAPIKeyAccount) != nil
        museKeyCache.set(present)
        return present
    }

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        if account == museAPIKeyAccount { museKeyCache.set(false) }
        guard !value.isEmpty else { return true }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let ok = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        if account == museAPIKeyAccount { museKeyCache.set(ok) }
        return ok
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)
        return value?.isEmpty == true ? nil : value
    }

    static func delete(account: String) {
        set("", account: account)
    }
}

private final class MuseKeyCache: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?

    func get() -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ new: Bool) {
        lock.lock()
        value = new
        lock.unlock()
    }
}
