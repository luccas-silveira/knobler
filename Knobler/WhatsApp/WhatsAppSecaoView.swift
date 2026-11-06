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

    var body: some View {
        HStack(spacing: 12) {
            WhatsAppListaView(vm: vm, store: store)
                .frame(width: NotchMetrics.whatsappListaLargura)
            colunaDireita
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
                }
                .task(id: Padrao(conta: contaID, primeira: conversas.first?.jid)) {
                    await WhatsAppTela.adotarPadrao(vm: vm, store: store)
                }
        }
        .frame(height: NotchMetrics.whatsappAltura)
        .foregroundStyle(.white)
    }

    // ponytail: nesta etapa a conversa é só o nome e os estados só o título;
    // bolhas, compositor, QR e botões entram nas etapas seguintes.
    @ViewBuilder
    private var colunaDireita: some View {
        switch direita {
        case .conversa(let k):
            Text(conversas.first { $0.jid == k.jid }?.nome ?? k.jid)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        default:
            Text(titulo(direita))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
        }
    }

    private func titulo(_ d: WATelaDireita) -> String {
        switch d {
        case .ponteFora: return WATextos.ponteForaTitulo
        case .chave: return WATextos.chaveTitulo
        case .incompativel: return WATextos.incompativelTitulo
        case .carregando: return WATextos.carregando
        case .qr:
            let rotulo = WACartao.rotuloDaConta(conta: conta, numero: contaID ?? "")
            return WATextos.qrTitulo(rotulo: rotulo)
        case .qrExpirado: return WATextos.qrExpiradoTitulo
        case .vazio: return WATextos.vazioTitulo
        case .conversa: return ""
        }
    }
}
