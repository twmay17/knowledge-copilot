import Foundation
import Security
import os

struct AppSecretStore: Sendable {
    let loadValue: @Sendable (String) -> String?
    let saveValue: @Sendable (String, String) -> Void

    func load(key: String) -> String? {
        loadValue(key)
    }

    func save(key: String, value: String) {
        saveValue(key, value)
    }

    static let keychain = AppSecretStore(
        loadValue: { KeychainHelper.load(key: $0) },
        saveValue: { key, value in
            KeychainHelper.save(key: key, value: value)
        }
    )

    static let ephemeral = AppSecretStore(
        loadValue: { _ in nil },
        saveValue: { _, _ in }
    )
}

struct SettingsStorage {
    let defaults: UserDefaults
    let secretStore: AppSecretStore
    let defaultNotesDirectory: URL
    let runMigrations: Bool

    static func live(defaults: UserDefaults = .standard) -> SettingsStorage {
        SettingsStorage(
            defaults: defaults,
            secretStore: .keychain,
            defaultNotesDirectory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/OpenOats"),
            runMigrations: true
        )
    }
}

/// Backward-compatible alias for existing test code.
typealias AppSettingsStorage = SettingsStorage

// MARK: - Keychain Helper

/// No existing `Log` category (Utils/Logging.swift) fits Keychain storage, and
/// that file is outside this change's scope, so this stays file-local. Key
/// names are non-secret identifiers safe to log `.public`; values must never
/// appear in a log line.
private let keychainLog = Logger(subsystem: "com.openoats.app", category: "keychain")

enum KeychainHelper {
    private static let service = "com.openoats.app"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            keychainLog.error("Keychain save failed for \(key, privacy: .public): \(status)")
        }
    }

    static func saveIfMissing(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess, status != errSecDuplicateItem {
            keychainLog.error("Keychain saveIfMissing failed for \(key, privacy: .public): \(status)")
        }
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            keychainLog.error("Keychain delete failed for \(key, privacy: .public): \(status)")
        }
    }
}
