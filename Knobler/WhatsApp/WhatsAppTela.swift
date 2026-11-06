import Foundation

// O que a seção do WhatsApp mostra, decidido fora da view: a coluna direita
// (estado da conexão, QR, vazio ou a conversa), a coluna esquerda, a conta
// inicial e a conversa que aparece por padrão. Tudo puro, menos o
// `adotarPadrao`, que é a ponte entre o `NotchViewModel` (que só guarda
// `String`) e o `WhatsAppStore`.

/// Coluna direita da seção (mockup, variante A).
enum WATelaDireita: Equatable {
    case ponteFora
    /// `ausente`: o arquivo da chave não existe (o apoio muda, o título não).
    case chave(ausente: Bool)
    case incompativel
    case carregando
    case qr
    case qrExpirado
    case vazio
    case conversa(WAChave)
}

/// Coluna esquerda: a lista, ou o aviso de parear quando a conta caiu.
enum WATelaEsquerda: Equatable {
    case lista, semPareamento
}

enum WhatsAppTela {
    /// A conexão vence o conteúdo; depois a conta deslogada (QR); depois a
    /// conversa (a aberta ou a mais recente), ou o vazio.
    static func direita(conexao: WAConexao, conta: WAConta?, pareamento: WAPareamento?,
                        conversas: [WAConversa], aberta: WAChave?) -> WATelaDireita {
        switch conexao {
        case .foraDoAr: return .ponteFora
        case .chaveNaoConfere: return .chave(ausente: false)
        case .semChave: return .chave(ausente: true)
        case .incompativel: return .incompativel
        case .carregando, .inerte: return .carregando
        case .pronta: break
        }
        if conta?.estado == .deslogada {
            return pareamento?.estado == .expirado ? .qrExpirado : .qr
        }
        guard let conta, let k = conversaEfetiva(aberta: aberta, conta: conta.conta, conversas: conversas)
        else { return .vazio }
        return .conversa(k)
    }

    /// Conta deslogada sem pareamento em andamento: a tela do QR pede um.
    /// QR expirado não conta: quem pede outro é o "Gerar outro".
    static func precisaIniciarPareamento(conta: WAConta?, pareamento: WAPareamento?) -> Bool {
        guard conta?.estado == .deslogada else { return false }
        switch pareamento?.estado {
        case nil, .cancelado?, .erro?, .sucesso?: return true
        case .iniciando?, .qr?, .expirado?, .outro?: return false
        }
    }

    static func esquerda(conta: WAConta?) -> WATelaEsquerda {
        conta?.estado == .deslogada ? .semPareamento : .lista
    }

    /// A selecionada, se ainda existe; senão a padrão (ou a primeira).
    static func contaInicial(selecionada: String?, contas: [WAConta]) -> String? {
        if let selecionada, contas.contains(where: { $0.conta == selecionada }) { return selecionada }
        return (contas.first { $0.padrao } ?? contas.first)?.conta
    }

    /// A conversa que a coluna direita mostra: a aberta, se é desta conta;
    /// senão a mais recente (`conversas` já vem ordenada).
    static func conversaEfetiva(aberta: WAChave?, conta: String, conversas: [WAConversa]) -> WAChave? {
        if let aberta, aberta.conta == conta { return aberta }
        return conversas.first.map { WAChave(conta: conta, jid: $0.jid) }
    }

    /// A conversa que aparece por padrão vira a aberta da tela: grava a chave
    /// no VM (o `enqueue` só suprime o card da conversa aberta) e carrega as
    /// bolhas. Nunca marca lida. Mesma chave de antes: nada a fazer.
    ///
    /// ponytail: trocar de conversa não chama `store.fechar` da anterior. A
    /// aberta pode ter vindo de um card (`abrirConversa`) sem `abrir`, e um
    /// `fechar` sem par desconta a contagem de outra tela.
    @MainActor
    static func adotarPadrao(vm: NotchViewModel, store: WhatsAppStore) async {
        guard let conta = contaInicial(selecionada: vm.whatsappContaSelecionada, contas: store.estado.contas),
              let k = conversaEfetiva(aberta: vm.whatsappConversaAberta.flatMap(WAChave.init(texto:)),
                                      conta: conta, conversas: store.estado.conversas(da: conta)),
              k.texto != vm.whatsappConversaAberta else { return }
        vm.whatsappConversaAberta = k.texto
        await store.abrir(k)
    }
}
