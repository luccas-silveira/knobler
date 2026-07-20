//
//  WebhookKeychainStore.swift
//  Knobler
//
//  Segredos do relay de webhook no Keychain (não em UserDefaults, não em log).
//  Uma conta por valor sob o mesmo service. Acessível após o 1º unlock (o
//  agente lê no login sem interação). Espelha o padrão do DeepgramKeyStore.
//

import Security
import Foundation

enum WebhookKeychainStore {
    enum Account: String, CaseIterable { case deviceId, deviceSecret, publishToken }
    private static let service = "com.zoi.knobler.webhook"

    static func load(_ account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, _ account: Account) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete(_ account: Account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func clearAll() { Account.allCases.forEach(delete) }
}
