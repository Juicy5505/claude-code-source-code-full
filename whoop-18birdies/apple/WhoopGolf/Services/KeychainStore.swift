import Foundation
import Security

struct KeychainStore: Sendable {
    enum KeychainError: Error {
        case status(OSStatus)
    }

    private let service = "com.alex.whoopgolf.bridge"

    private struct PairedBridgeCredential: Codable {
        let version: Int
        let baseURL: String
        let bearerToken: String
    }

    func setToken(_ token: String) throws {
        let account = "mobile-api-token"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        guard !token.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.status(status)
            }
            return
        }

        let value: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(updateStatus)
        }

        var item = query
        value.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
    }

    func token() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "mobile-api-token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { throw KeychainError.status(status) }
        return value
    }

    /// Atomically stores the paired URL and bearer in one device-only Keychain
    /// value. App wiring can migrate from the legacy split URL/token fields
    /// without creating a crash window between two persistence systems.
    func setPairedBridgeConfiguration(_ configuration: BridgeConfiguration) throws {
        let payload = PairedBridgeCredential(
            version: 1,
            baseURL: configuration.baseURL.absoluteString,
            bearerToken: configuration.bearerToken
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try set(
            encoder.encode(payload),
            account: "mobile-api-configuration"
        )
    }

    func pairedBridgeConfiguration() throws -> BridgeConfiguration? {
        guard let data = try data(account: "mobile-api-configuration") else { return nil }
        let payload: PairedBridgeCredential
        do { payload = try JSONDecoder().decode(PairedBridgeCredential.self, from: data) }
        catch { throw KeychainError.status(errSecDecode) }
        guard payload.version == 1 else { throw KeychainError.status(errSecDecode) }
        return try BridgeConfiguration(
            baseURLString: payload.baseURL,
            bearerToken: payload.bearerToken
        )
    }

    private func set(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let value: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError.status(updateStatus) }
        var item = query
        value.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
    }

    private func data(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let value = item as? Data else {
            throw KeychainError.status(status)
        }
        return value
    }
}
