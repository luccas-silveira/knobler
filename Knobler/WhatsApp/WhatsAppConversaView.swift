import SwiftUI

// Conversa na coluna direita da seção do WhatsApp (mockup, variante A):
// cabeçalho de 28 pt e a lista de bolhas, que abre na mais recente e pede a
// página antiga quando a primeira linha aparece, e o compositor fixo embaixo.
// Abrir a conversa nunca marca lida: só o botão "Marcar como lida".

struct WhatsAppConversaView: View {
    @ObservedObject var vm: NotchViewModel
    let chave: WAChave
    @ObservedObject var store = WhatsAppStore.shared
    /// Participantes do grupo, pedidos quando a conversa de grupo abre.
    @State private var grupo: WAGrupo?

    private var conversa: WAConversa? {
        store.estado.conversas(da: chave.conta).first { $0.jid == chave.jid }
    }

    private var ehGrupo: Bool {
        conversa?.tipo == .grupo || chave.jid.hasSuffix("@g.us")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WACabecalhoDaConversa(chave: chave, conversa: conversa, grupo: grupo) {
                Task { await store.marcarLida(chave) }
            }
            bolhas
            WhatsAppCompositorView(vm: vm, chave: chave)
                .id(chave)
        }
        .task(id: chave) {
            grupo = nil
            guard ehGrupo else { return }
            grupo = await store.grupo(chave)
        }
    }

    /// Altura do degradê que esmaece a linha cortada no topo da lista.
    private static let esmaecerTopo: CGFloat = 16

    private var bolhas: some View {
        let todas = store.estado.bolhas(de: chave)
        let linhas = WAConversaModelo.linhas(bolhas: todas, grupo: ehGrupo, agora: Date(), calendario: .current)
        return GeometryReader { geo in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(linhas) { linha in
                        Group {
                            switch linha {
                            case let .dia(texto):
                                Text(texto)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.56))
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity)
                            case let .bolha(b, mostraRemetente, podeAgir):
                                WhatsAppBolhaView(
                                    vm: vm, bolha: b, chave: chave, mostraRemetente: mostraRemetente,
                                    podeAgir: podeAgir, larguraMaxima: geo.size.width * 0.78,
                                    nomeDaCitacao: b.mensagem.citacao.map {
                                        WAConversaModelo.nomeDaCitacao($0, conta: chave.conta,
                                                                       bolhas: todas, conversa: conversa)
                                    },
                                    store: store)
                            }
                        }
                        .onAppear {
                            // a primeira linha apareceu: pede a página antiga
                            guard linha.id == linhas.first?.id else { return }
                            Task { await store.carregarMais(chave) }
                        }
                    }
                }
                // no topo da rolagem a primeira linha começa abaixo do degradê
                .padding(.top, Self.esmaecerTopo)
                .padding(.bottom, 2)
                // conversa curta fica colada embaixo, como no mockup
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .bottomLeading)
            }
            // abre na mensagem mais recente e segue colada nela quando chega outra
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.hidden)
        }
        // nada da lista desenha fora da área dela (sobre o cabeçalho ou o
        // compositor); a linha cortada no topo some num degradê em vez de
        // ficar colada ao subtítulo do cabeçalho
        .mask {
            VStack(spacing: 0) {
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .clear, location: 0.4),
                                       .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.esmaecerTopo)
                Rectangle()
            }
        }
    }
}

// MARK: - Cabeçalho

private struct WACabecalhoDaConversa: View {
    let chave: WAChave
    let conversa: WAConversa?
    let grupo: WAGrupo?
    let marcarLida: () -> Void
    @StateObject private var foto = WAFotoLoader()

    var body: some View {
        let c = conversa.map { WAConversaModelo.cabecalho(conversa: $0, grupo: grupo) }
            ?? (titulo: chave.jid, subtitulo: nil, marcarLida: false)
        HStack(spacing: 8) {
            avatar.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(c.titulo)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                if let sub = c.subtitulo {
                    Text(sub)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
            if c.marcarLida {
                WABotaoMarcarLida(acao: marcarLida)
            }
        }
        .frame(height: 28)
        .task(id: chave) { foto.carregar(conta: chave.conta, jid: chave.jid) }
    }

    @ViewBuilder
    private var avatar: some View {
        if let img = foto.imagem {
            Image(nsImage: img).resizable().scaledToFill().clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(.gray.opacity(0.35))
                if conversa?.tipo == .grupo {
                    Image(systemName: "person.2.fill").font(.system(size: 9))
                } else {
                    Text(String((conversa?.nome ?? "?").prefix(1)).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                }
            }
        }
    }
}

/// Chip "Marcar como lida": dois tiques e o rótulo, 22 pt de altura.
private struct WABotaoMarcarLida: View {
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 4) {
                WATiquesDuplos(tamanho: 10)
                Text(WATextos.marcarComoLida)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(hover ? 0.15 : 0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .fixedSize()
    }
}
