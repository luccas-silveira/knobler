import SwiftUI

// Seção do WhatsApp no notch expandido (mockup, variante A): lista de 260 pt
// à esquerda e, à direita, o estado da conexão ou a conversa. O que cada
// coluna mostra sai de `WhatsAppTela`; a conversa que aparece por padrão vira
// a aberta desta tela pelo `adotarPadrao`.

struct WhatsAppSecaoView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var store = WhatsAppStore.shared

    /// Quando muda, a coluna direita adota de novo a conversa padrão.
    private struct Padrao: Equatable {
        let conta: String?
        let primeira: String?
    }

    private var contaID: String? {
        WhatsAppTela.contaInicial(selecionada: vm.whatsappContaSelecionada, contas: store.estado.contas)
    }

    private var conta: WAConta? {
        store.estado.contas.first { $0.conta == contaID }
    }

    private var conversas: [WAConversa] {
        contaID.map { store.estado.conversas(da: $0) } ?? []
    }

    private var direita: WATelaDireita {
        WhatsAppTela.direita(conexao: store.conexao, conta: conta, pareamento: store.estado.pareamento,
                             conversas: conversas,
                             aberta: vm.whatsappConversaAberta.flatMap(WAChave.init(texto:)))
    }

    /// Sem conta conhecida a coluna esquerda não teria nada (nem seletor): o
    /// estado ocupa a seção inteira, centrado. O carregando é a exceção — as
    /// linhas de espera ficam no lugar da lista.
    private var estadoNaLarguraToda: Bool {
        guard store.estado.contas.isEmpty else { return false }
        switch direita {
        case .carregando, .conversa: return false
        default: return true
        }
    }

    var body: some View {
        Group {
            if estadoNaLarguraToda {
                WhatsAppEstadosView(tela: direita, conta: conta, outra: outra, store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 12) {
                    WhatsAppListaView(vm: vm, store: store, carregando: direita == .carregando)
                        .frame(width: NotchMetrics.whatsappListaLargura)
                    colunaDireita
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
                        }
                }
            }
        }
        .task(id: Padrao(conta: contaID, primeira: conversas.first?.jid)) {
            await WhatsAppTela.adotarPadrao(vm: vm, store: store)
        }
        .frame(height: NotchMetrics.whatsappAltura)
        .foregroundStyle(.white)
    }

    /// Outra conta que segue conectada, citada no apoio do QR.
    private var outra: String? {
        store.estado.contas.first { $0.conta != contaID && $0.estado == .conectada }
            .map { WACartao.rotuloDaConta(conta: $0, numero: $0.conta) }
    }

    // ponytail: o compositor entra na etapa seguinte; por ora a conversa
    // ocupa a coluna inteira.
    @ViewBuilder
    private var colunaDireita: some View {
        switch direita {
        case .conversa(let k):
            WhatsAppConversaView(vm: vm, chave: k, store: store)
        default:
            WhatsAppEstadosView(tela: direita, conta: conta, outra: outra, store: store)
        }
    }
}
