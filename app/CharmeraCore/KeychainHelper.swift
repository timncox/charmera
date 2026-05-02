import Foundation
import Security

public enum KeychainHelper {

    private static let service = "com.charmera.app"

    // MARK: - Convenience Properties

    public static var githubToken: String? {
        get { load(key: "github_token") }
        set {
            if let value = newValue {
                save(key: "github_token", value: value)
            } else {
                delete(key: "github_token")
            }
        }
    }

    public static var githubUsername: String? {
        get { load(key: "github_username") }
        set {
            if let value = newValue {
                save(key: "github_username", value: value)
            } else {
                delete(key: "github_username")
            }
        }
    }

    // MARK: - Core Operations

    @discardableResult
    public static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete any existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { return false }

        // After SecItemAdd, the item lives in the default partition list, which means
        // every other binary (including charmera-mcp inside this same app bundle) hits
        // a Keychain ACL prompt on first read. Whitelist any tool signed by our team
        // so the helper goes through silently. Best-effort — if this fails the user
        // just sees the legacy prompt and can click "Always Allow."
        relaxPartitionList(account: key)
        return true
    }

    private static func relaxPartitionList(account: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = [
            "set-key-partition-list",
            "-S", "apple-tool:,apple:,teamid:P5EK689L33",
            "-s", service,
            "-a", account,
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }

    public static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
