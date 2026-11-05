import Foundation

/// Para onde vai o texto do ditado. Mora fora de `Dictation.swift` (que importa
/// FluidAudio) para a escolha ser testável só com Foundation
/// (`tools/whatsappditadocheck.swift`).
enum DictationDestination: Equatable {
    case ask(id: String)
    /// `chave` é `WAChave.texto` (`"conta|jid"`) do campo do WhatsApp em uso.
    case whatsapp(chave: String)
    case application(pid: pid_t)

    /// Ask ativo vence; sem ele, o campo do WhatsApp em uso; sem os dois, o app
    /// da frente; sem nada, `nil`.
    static func escolher(askAtivo: String?, campoWhatsApp: String?, pidDaFrente: pid_t?) -> DictationDestination? {
        if let askAtivo { return .ask(id: askAtivo) }
        if let campoWhatsApp { return .whatsapp(chave: campoWhatsApp) }
        return pidDaFrente.map { .application(pid: $0) }
    }
}
