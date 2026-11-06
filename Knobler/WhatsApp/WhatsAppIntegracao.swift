import AppKit
import os

// Card de chegada do WhatsApp ligado às telas: a mensagem que o store recebe
// vira UM card (montado fora do laço das telas — um por tela viraria N linhas
// no histórico), promove a seção em cada tela e vai para o `publicar` do app,
// que decide entre mostrar e silenciar. A supressão da conversa aberta numa
// tela mora no `enqueue` do `NotchViewModel`.

private let log = Logger(subsystem: "com.zoi.knobler", category: "whatsapp")

@MainActor
final class WhatsAppIntegracao {
    private let telas: () -> [NotchViewModel]
    private let publicar: (NotchNotification) -> Void
    private let agora: () -> Date
    private var rajada = WARajada()

    init(telas: @escaping () -> [NotchViewModel],
         publicar: @escaping (NotchNotification) -> Void,
         agora: @escaping () -> Date = Date.init) {
        self.telas = telas
        self.publicar = publicar
        self.agora = agora
    }

    /// Mensagem recebida pelo store. Velha, minha ou apagada não vira card
    /// nem conta na rajada.
    func chegou(mensagem: WAMensagem, conversa: WAConversa, conta: WAConta?, numero: String) {
        let agora = agora()
        guard WACartao.vale(mensagem: mensagem, agora: agora) else { return }
        let chave = WAChave(conta: numero, jid: conversa.jid).texto
        let contagem = rajada.registrar(chave: chave, agora: agora)
        let card = WACartao.montar(mensagem: mensagem, conversa: conversa, conta: conta,
                                   numero: numero, contagem: contagem, agora: agora)
        telas().forEach { $0.marcarEvento(.whatsapp) }
        publicar(card)
        let atraso = Int((agora.timeIntervalSince1970 - TimeInterval(mensagem.ts)) * 1000)
        log.notice("cartão publicado atraso_ms=\(atraso, privacy: .public)")
    }

    /// Respondeu pelo card (ou fechou no X): some com o card dessa conversa em
    /// todas as telas e a contagem recomeça.
    func respondeu(chave: String) {
        for vm in telas() where vm.activeNotification?.whatsapp?.chave == chave {
            vm.dismissActiveNotification()
        }
        rajada.zerar(chave: chave)
    }

    /// Abre a conversa do card nesta tela.
    func abrir(chave: String, conta: String, em vm: NotchViewModel) {
        vm.abrirWhatsApp(chave: chave, conta: conta)
    }
}
