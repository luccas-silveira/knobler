import SwiftUI

// Coluna esquerda da seção do WhatsApp (mockup, variante A): seletor de conta
// com uma linha de 28 pt por conta, fio, e a lista de conversas da conta
// selecionada. A conta e a conversa abertas são desta tela (`vm`).

struct WhatsAppListaView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var store = WhatsAppStore.shared
    /// A ponte ainda não entregou as conversas: linhas de espera no lugar da
    /// lista (mockup, quadro "Carregando conversas").
    var carregando = false

    private var contaID: String? {
        WhatsAppTela.contaInicial(selecionada: vm.whatsappContaSelecionada, contas: store.estado.contas)
    }

    private var conta: WAConta? {
        store.estado.contas.first { $0.conta == contaID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 2) {
                ForEach(store.estado.contas, id: \.conta) { c in
                    WABotaoDaConta(conta: c, selecionada: c.conta == contaID) {
                        vm.whatsappContaSelecionada = c.conta
                    }
                }
            }
            // sem conta nenhuma não há seletor, e o fio ficaria solto
            if !store.estado.contas.isEmpty {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.vertical, 2)
            }
            if carregando {
                WAListaCarregando()
            } else {
                conteudo
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var conteudo: some View {
        switch WhatsAppTela.esquerda(conta: conta) {
        case .semPareamento:
            Text(WATextos.semPareamento)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        case .lista:
            if let contaID { lista(contaID) }
        }
    }

    private func lista(_ contaID: String) -> some View {
        let conversas = store.estado.conversas(da: contaID)
        let efetiva = WhatsAppTela.conversaEfetiva(
            aberta: vm.whatsappConversaAberta.flatMap(WAChave.init(texto:)),
            conta: contaID, conversas: conversas)
        return ScrollView(.vertical) {
            LazyVStack(spacing: 2) {
                ForEach(conversas, id: \.jid) { c in
                    let k = WAChave(conta: contaID, jid: c.jid)
                    WALinhaDaConversa(conversa: c, chave: k, rascunho: store.rascunho(k),
                                      selecionada: k == efetiva) {
                        vm.whatsappConversaAberta = k.texto
                        Task { await store.abrir(k) }
                    }
                    .onAppear {
                        // a última linha apareceu: pede a página seguinte
                        guard c.jid == conversas.last?.jid else { return }
                        Task { await store.carregarMaisConversas(conta: contaID) }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Seletor de conta

private struct WABotaoDaConta: View {
    let conta: WAConta
    let selecionada: Bool
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        let estado = WAApresentacao.estadoDaConta(conta.estado)
        let rotulo = WACartao.rotuloDaConta(conta: conta, numero: conta.conta)
        Button(action: acao) {
            HStack(spacing: 6) {
                // ponytail: a padrão é a de trabalho (maleta) e a outra, a
                // pessoal; a ponte não diz de quem é cada conta.
                Image(systemName: estado.rotulo != nil ? "powerplug" : (conta.padrao ? "briefcase" : "person"))
                    .font(.system(size: 12))
                    .frame(width: 14)
                Text(rotulo)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let r = estado.rotulo {
                    Text(r)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                } else if conta.naoLidas > 0 {
                    WAContagem(n: conta.naoLidas)
                }
            }
            .foregroundStyle(.white.opacity(selecionada ? 1 : 0.85))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(selecionada ? 0.25 : (hover ? 0.15 : 0.08))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(rotuloDeAcessibilidade(rotulo, estado: estado))
        .accessibilityAddTraits(selecionada ? .isSelected : [])
    }

    private func rotuloDeAcessibilidade(_ rotulo: String, estado: WAEstadoDaContaNaTela) -> String {
        if let r = estado.rotulo { return "\(rotulo), \(r)" }
        return conta.naoLidas > 0 ? "\(rotulo), \(conta.naoLidas) não lidas" : rotulo
    }
}

// MARK: - Linha da lista

private struct WALinhaDaConversa: View {
    let conversa: WAConversa
    let chave: WAChave
    let rascunho: String
    let selecionada: Bool
    let acao: () -> Void
    @State private var hover = false
    @StateObject private var foto = WAFotoLoader()

    private var grupo: Bool { conversa.tipo == .grupo }
    private var naoLida: Bool { conversa.naoLidas > 0 || conversa.marcadaNaoLida }

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 8) {
                avatar.frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(conversa.nome)
                            .font(.system(size: 10, weight: naoLida ? .bold : .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(WAApresentacao.hora(ts: conversa.ultima?.ts ?? conversa.ts,
                                                 agora: Date(), calendario: .current))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.white.opacity(naoLida ? 0.85 : 0.56))
                    }
                    HStack(spacing: 6) {
                        previa
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(naoLida ? 0.85 : 0.6))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        if conversa.naoLidas > 0 {
                            WAContagem(n: conversa.naoLidas)
                        } else if conversa.marcadaNaoLida {
                            // marcada como não lida sem contagem: só o ponto
                            Circle().fill(.white.opacity(0.85)).frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(selecionada ? 0.15 : (hover ? 0.08 : 0.06))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(conversa.naoLidas > 0 ? "\(conversa.nome), \(conversa.naoLidas) não lidas" : conversa.nome)
        .accessibilityAddTraits(selecionada ? .isSelected : [])
        .task(id: chave) { foto.carregar(conta: chave.conta, jid: chave.jid) }
    }

    @ViewBuilder
    private var avatar: some View {
        if let img = foto.imagem {
            Image(nsImage: img).resizable().scaledToFill().clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(.gray.opacity(0.35))
                if grupo {
                    Image(systemName: "person.2.fill").font(.system(size: 10))
                } else {
                    Text(String(conversa.nome.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                }
            }
        }
    }

    /// Prefixo (rascunho ou quem mandou no grupo), ícone do tipo e texto.
    private var previa: Text {
        let p = WAApresentacao.previa(ultima: conversa.ultima, grupo: grupo, rascunho: rascunho)
        var t = Text("")
        if let prefixo = p.prefixo {
            let pre = p.rascunho
                ? Text(prefixo).fontWeight(.semibold).foregroundColor(.white)
                : Text(prefixo).foregroundColor(.white.opacity(0.85))
            t = Text("\(pre) ")
        }
        if let icone = p.icone {
            t = Text("\(t)\(Image(systemName: icone)) ")
        }
        let corpo = p.apagada ? Text(p.texto).italic() : Text(p.texto)
        return Text("\(t)\(corpo)")
    }
}

// MARK: - Contagem

/// Número branco bold numa cápsula branca a 25% (seletor e lista).
private struct WAContagem: View {
    let n: Int

    var body: some View {
        Text("\(n)")
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 16, minHeight: 16, maxHeight: 16)
            .background(Capsule().fill(.white.opacity(0.25)))
    }
}
