import Foundation

// A peça do WhatsApp na máquina de peças (`Plugin.swift`). A conformidade mora
// aqui, e não em `WhatsAppStore.swift`, pra os gates do estado não arrastarem
// `Plugin.swift` (o `whatsapppecaligacaocheck` reprova `PluginServico` em
// qualquer outro arquivo desta pasta). Só o app compila este arquivo.

extension WhatsAppStore: PluginServico {
    /// O host chama de qualquer lugar, mas na prática sempre da main (desinstalar
    /// vem do painel de Ajustes); o `stop()` para o canal.
    nonisolated func parar() { MainActor.assumeIsolated { stop() } }
}

enum WhatsAppPeca {
    /// O `nascer` da peça: o store é singleton e nasce inerte, então ligar só
    /// dispara a conexão (sem o arquivo da chave, o canal nem tenta).
    @MainActor static func ligar() -> PluginServico {
        WhatsAppStore.shared.fonteDeMicrofone = MicrofoneDoDitado()
        WhatsAppStore.shared.start()
        return WhatsAppStore.shared
    }
}
