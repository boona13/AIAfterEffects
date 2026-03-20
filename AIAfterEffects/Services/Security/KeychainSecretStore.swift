//
//  KeychainSecretStore.swift
//  AIAfterEffects
//
//  Stores user-provided API credentials in the macOS Keychain.
//

import Foundation
import Security

enum SecretStoreKey: String {
    case openRouterAPIKey = "openrouter_api_key"
    case sketchfabAPIToken = "sketchfab_api_token"
    case sketchfabOAuthToken = "sketchfab_oauth_token"
}

enum KeychainSecretStore {
    private static let service = "AIAfterEffects"
    
    static func string(for key: SecretStoreKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            DebugLogger.shared.warning(
                "Keychain read failed for \(key.rawValue): \(status)",
                category: .app
            )
            return nil
        }
    }
    
    static func set(_ value: String, for key: SecretStoreKey) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteValue(for: key)
            return
        }
        
        guard let data = trimmed.data(using: .utf8) else { return }
        
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        
        if updateStatus != errSecItemNotFound {
            DebugLogger.shared.warning(
                "Keychain update failed for \(key.rawValue): \(updateStatus)",
                category: .app
            )
        }
        
        var insertQuery = baseQuery
        insertQuery[kSecValueData as String] = data
        
        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            DebugLogger.shared.warning(
                "Keychain add failed for \(key.rawValue): \(addStatus)",
                category: .app
            )
        }
    }
    
    static func deleteValue(for key: SecretStoreKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status != errSecSuccess, status != errSecItemNotFound else { return }
        
        DebugLogger.shared.warning(
            "Keychain delete failed for \(key.rawValue): \(status)",
            category: .app
        )
    }
    
    static func migrateLegacyUserDefaultsValue(for key: SecretStoreKey) -> String? {
        guard let legacyValue = UserDefaults.standard.string(forKey: key.rawValue),
              !legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        set(legacyValue, for: key)
        UserDefaults.standard.removeObject(forKey: key.rawValue)
        return legacyValue
    }
}
