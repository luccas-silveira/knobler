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

    static func load(_ account: Account) -> String? { loadRaw(account: account.rawValue) }

    static func save(_ value: String, _ account: Account) { saveRaw(value, account: account.rawValue) }

    static func delete(_ account: Account) { deleteRaw(account: account.rawValue) }

    static func clearAll() { Account.allCases.forEach(delete) }

    // MARK: Helpers genéricos por account (mesma lógica; reusados pelos tokens por perfil)

    static func loadRaw(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveRaw(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func deleteRaw(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: Token por perfil (o relay só guarda o hash → o app monta o link)

    static func saveProfileToken(_ token: String, _ profileId: String) { saveRaw(token, account: "profile:\(profileId)") }
    static func loadProfileToken(_ profileId: String) -> String? { loadRaw(account: "profile:\(profileId)") }
    static func deleteProfileToken(_ profileId: String) { deleteRaw(account: "profile:\(profileId)") }
}
