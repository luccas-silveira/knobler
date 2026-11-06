import AppKit
import SwiftUI

// Compositor fixo embaixo da conversa do WhatsApp (mockup, variante A: `.cmpw`,
// `.cmp`, `.field`, `.qs`, `.recbox`): faixa de citação e anexo acima, clipe,
// campo de 26 pt e microfone ou avião. Gravando, o campo vira a caixa
// "Gravando"; ditando, o campo mostra "Ouvindo" à direita. Rascunho, citação e
// anexo moram no estado do WhatsApp por conta+conversa, nunca em @State.

struct WhatsAppCompositorView: View {
    @ObservedObject var vm: NotchViewModel
    let chave: WAChave
    @ObservedObject var store = WhatsAppStore.shared
    @FocusState private var campoFocado: Bool

    private var texto: String { store.rascunho(chave) }
    private var anexo: URL? { store.anexoPendente(chave) }
    private var gravacao: WAGravacaoEmCurso? {
        store.gravacao.flatMap { $0.chave == chave ? $0 : nil }
    }

    /// O ditado escreve neste campo: está gravando e o campo é o em uso.
    private var ditando: Bool {
        guard case .recording? = vm.dictation else { return false }
        return store.campoEmUso == chave
    }

    private var modo: WAModoDoCompositor {
        WACompositor.modo(gravando: gravacao != nil, ditando: ditando, texto: texto, temAnexo: anexo != nil)
    }

    /// Com texto ou anexo o botão da direita envia; sem nada, grava.
    private var podeEnviar: Bool {
        anexo != nil || !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let c = store.citacao(chave) { faixaDeCitacao(c) }
            if let anexo { faixaDeAnexo(anexo) }
            if let erro = store.erroDeAnexo ?? store.erroDeGravacao {
                Text(erro)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            linha
        }
        .onChange(of: campoFocado) { _, focado in
            vm.atualizarEdicaoWhatsApp(focado)
            if focado {
                store.campoEmUso = chave
            } else if store.campoEmUso == chave {
                store.campoEmUso = nil
            }
        }
        .onDisappear {
            if campoFocado { vm.atualizarEdicaoWhatsApp(false) }
            if store.campoEmUso == chave { store.campoEmUso = nil }
        }
    }

    @ViewBuilder
    private var linha: some View {
        switch modo {
        case .gravando:
            HStack(spacing: 6) {
                WABotaoDoCompositor(icone: "trash", ajuda: "Cancelar gravação") { store.cancelarGravacao() }
                caixaGravando
                WABotaoDoCompositor(icone: "paperplane.fill", ajuda: "Enviar áudio") {
                    Task { await store.pararEEnviarGravacao() }
                }
            }
        case let .normal(mostraEnviar, _):
            linhaComCampo(enviar: mostraEnviar)
        case .ditando:
            linhaComCampo(enviar: podeEnviar)
        }
    }

    private func linhaComCampo(enviar: Bool) -> some View {
        HStack(spacing: 6) {
            WABotaoDoCompositor(icone: "paperclip", ajuda: "Anexar foto, vídeo ou documento", acao: escolherAnexo)
            campo
            if enviar {
                WABotaoDoCompositor(icone: "paperplane.fill", ajuda: "Enviar", acao: enviarAgora)
            } else {
                WABotaoDoCompositor(icone: "mic", ajuda: "Gravar áudio") { store.gravar(em: chave) }
            }
        }
    }

    // MARK: - campo

    private var campo: some View {
        let emUso = campoFocado || store.campoEmUso == chave
        return HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if texto.isEmpty {
                    Text(WATextos.placeholderConversa)
                        .foregroundStyle(.white.opacity(0.5))
                        .allowsHitTesting(false)
                }
                TextField("", text: Binding(
                    get: { store.rascunho(chave) },
                    set: { store.definirRascunho($0, para: chave) }))
                    .textFieldStyle(.plain)
                    .focused($campoFocado)
                    .onSubmit(enviarAgora)
                    .onKeyPress(.escape) { esc() }
                    .accessibilityLabel("Mensagem")
            }
            .font(.system(size: 10))
            .padding(.horizontal, 8)
            if ditando {
                HStack(spacing: 5) {
                    WAPontoGravando()
                    Text(WATextos.ouvindo)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.trailing, 8)
                .fixedSize()
            }
        }
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
        .overlay {
            // anel de foco: 2 pt, 1 pt para fora
            if emUso {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.white.opacity(0.62), lineWidth: 2)
                    .padding(-3)
            }
        }
    }

    // MARK: - gravando

    private var caixaGravando: some View {
        HStack(spacing: 8) {
            WAPontoGravando()
            Text(WATextos.gravando)
                .font(.system(size: 10, weight: .semibold))
            TimelineView(.periodic(from: gravacao?.inicio ?? Date(), by: 1)) { ctx in
                Text(WACompositor.tempoDeGravacao(inicio: gravacao?.inicio ?? ctx.date, agora: ctx.date))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white)
                    .frame(width: 64 * CGFloat(min(1, max(0, gravacao?.nivel ?? 0))))
            }
            .frame(width: 64, height: 6)
            .animation(.spring(response: 0.2, dampingFraction: 0.9), value: gravacao?.nivel)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }

    // MARK: - faixas acima do campo

    private func faixaDeCitacao(_ c: WACitacao) -> some View {
        let conversa = store.estado.conversas(da: chave.conta).first { $0.jid == chave.jid }
        let citada = store.estado.bolhas(de: chave).first { $0.id == c.id }?.mensagem
        let rotulo: String
        let corpo: String
        if let citada, let conversa {
            rotulo = WACompositor.rotuloDaCitacao(m: citada, conversa: conversa)
            corpo = WACompositor.textoDaCitacao(citada)
        } else {
            rotulo = WATextos.citacao(nome: conversa?.nome)
            corpo = c.texto
        }
        return WAFaixaAcimaDoCampo(fechar: { store.cancelarCitacao(chave) }, ajudaDoFechar: "Cancelar citação") {
            VStack(alignment: .leading, spacing: 0) {
                Text(rotulo)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(corpo)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
    }

    private func faixaDeAnexo(_ url: URL) -> some View {
        WAFaixaAcimaDoCampo(fechar: { store.definirAnexo(nil, para: chave) }, ajudaDoFechar: "Tirar o anexo") {
            HStack(spacing: 6) {
                Image(systemName: "doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                Text(url.lastPathComponent)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - ações

    /// Enter e avião: o anexo sai com o texto como legenda; sem anexo, o texto
    /// sai com a citação. Quem esvazia campo, faixa e anexo é o store.
    private func enviarAgora() {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let k = chave
        if let url = anexo {
            Task { await store.enviarAnexo(url, para: k, legenda: t.isEmpty ? nil : t) }
        } else if !t.isEmpty {
            Task { await store.enviarTexto(t, para: k, citando: store.citacao(k)) }
        }
    }

    /// Esc fecha a barra de reações e a citação; sem nada aberto, segue adiante.
    private func esc() -> KeyPress.Result {
        guard vm.whatsappReacoesEm != nil || store.citacao(chave) != nil else { return .ignored }
        vm.fecharReacoesWhatsApp()
        store.cancelarCitacao(chave)
        return .handled
    }

    /// Qualquer arquivo; foto e vídeo viram mídia, o resto documento.
    private func escolherAnexo() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // app agente (LSUIElement): sem ativar, o painel abre atrás de tudo; o
        // nível acompanha o notch (molde de MessageMedia.pick)
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel
        panel.makeKeyAndOrderFront(nil)
        let k = chave
        let store = store
        panel.begin { resposta in
            guard resposta == .OK, let url = panel.url else { return }
            Task { @MainActor in store.definirAnexo(url, para: k) }
        }
    }
}

// MARK: - Peças

/// Botão de ícone do compositor: 24 pt, canto 8, fundo só no hover.
private struct WABotaoDoCompositor: View {
    let icone: String
    let ajuda: String
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(hover ? 1 : 0.85))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(hover ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(ajuda)
        .accessibilityLabel(ajuda)
    }
}

/// Faixa acima do campo (citação, anexo): barra de 3 pt à esquerda, fundo
/// branco 6%, canto 8 e o x à direita.
private struct WAFaixaAcimaDoCampo<Conteudo: View>: View {
    let fechar: () -> Void
    let ajudaDoFechar: String
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(.white.opacity(0.62)).frame(width: 3)
            conteudo
                .frame(maxWidth: .infinity, alignment: .leading)
            WABotaoDoCompositor(icone: "xmark", ajuda: ajudaDoFechar, acao: fechar)
        }
        .padding(.vertical, 4)
        .padding(.trailing, 4)
        .fixedSize(horizontal: false, vertical: true)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Ponto vermelho de 8 pt que pulsa (o da pílula do ditado); parado com
/// movimento reduzido.
struct WAPontoGravando: View {
    @Environment(\.accessibilityReduceMotion) private var reduzir
    @State private var apagado = false

    var body: some View {
        Circle()
            .fill(Color(red: 1, green: 0.231, blue: 0.188))
            .frame(width: 8, height: 8)
            .opacity(apagado ? 0.35 : 1)
            .onAppear {
                guard !reduzir else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { apagado = true }
            }
    }
}
