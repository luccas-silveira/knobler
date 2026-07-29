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

    /// Lê o segredo **sem nunca** deixar o Keychain abrir o diálogo de senha.
    ///
    /// A ACL destes itens confia no requisito de assinatura de quem os gravou.
    /// Se a assinatura do app mudar (ex.: passar a ser notarizado com Developer
    /// ID), a ACL deixa de bater e o macOS pediria a senha do login keychain —
    /// três diálogos, um por item, no meio do launch. Preferimos falhar aqui e
    /// avisar na nossa própria UI: quem chama usa `exists(account:)` pra separar
    /// "nunca pareado" de "pareado mas trancado".
    ///
    /// ponytail: `SecKeychain*` é deprecated desde 10.10 e não tem substituto
    /// pra ACL de keychain de arquivo. O data protection keychain resolveria,
    /// mas exige entitlement `keychain-access-groups`, que exige Team ID — só
    /// vale a troca quando o app tiver Developer ID.
    static func loadRaw(account: String) -> String? {
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(true) }
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

    /// O item existe? Só consulta atributos, nunca o segredo — por isso responde
    /// mesmo quando a ACL não bate, e nunca dispara diálogo.
    static func exists(_ account: Account) -> Bool { existsRaw(account: account.rawValue) }

    static func existsRaw(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
        ]
        var out: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess
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
