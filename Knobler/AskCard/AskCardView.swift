//
//  AskCardView.swift
//  Knobler
//
//  Pergunta interativa do Claude Code (AskUserQuestion) exibida como card
//  no notch. O hook PreToolUse publica via POST /ask; o card responde e o
//  hook devolve a resposta ao Claude. Modelo espelha o payload da tool.
//

import SwiftUI

// MARK: - Estilo

/// Escada de opacidade do branco e letras do card de pergunta (DESIGN.md).
/// As peças do card leem daqui; nenhuma leva valor solto.
enum AskEstilo {
    static let fundoDaLinha = 0.06
    static let fundoEmDestaque = 0.15
    static let fundoMarcada = 0.25
    /// Campo de texto, selo de tecla e botão apagado.
    static let fundoDoCampo = 0.08

    static let tintaForte = 0.85
    static let tintaSecundaria = 0.62
    static let tintaApagada = 0.5
    static let tintaDesabilitada = 0.3
    static let anel = 0.5

    static let raio: CGFloat = 8
    static let raioDoSelo: CGFloat = 4

    static let pergunta = Font.system(size: 15, weight: .semibold)
    static let rotulo = Font.system(size: 12, weight: .semibold)
    static let descricao = Font.system(size: 11)
    /// Selo, aba, legenda e origem.
    static let miudo = Font.system(size: 10)
}

/// Selo de tecla: o número da opção, o ⏎ do Confirmar e as teclas da legenda.
struct AskSeloView: View {
    let texto: String
    var tinta = AskEstilo.tintaSecundaria
    var fundo = AskEstilo.fundoDoCampo

    var body: some View {
        Text(texto)
            .font(AskEstilo.miudo.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(tinta))
            .padding(.horizontal, 4)
            .frame(minWidth: 16)
            .frame(height: 16)
            .background(RoundedRectangle(cornerRadius: AskEstilo.raioDoSelo).fill(.white.opacity(fundo)))
    }
}

// MARK: - Card no notch

/// Card interativo em três faixas: topo (abas ou chip, origem, ✕), pergunta
/// com as opções, e rodapé (campo de texto livre + legenda de teclas).
struct AskCardView: View {
    @ObservedObject var vm: NotchViewModel
    let askStore: AskStore
    /// Até onde o card cresce (`AskTeto.doCard`); passou disso, a lista rola.
    let alturaMaxima: CGFloat

    @FocusState private var textFocused: Bool
    @State private var sobreOFechar = false
    @State private var listaNatural: CGFloat = 0
    @State private var alturaDoCard: CGFloat = 0
    /// Altura da área rolável da lista; `nil` = ela cabe e é desenhada direto.
    @State private var tetoDaLista: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduzMovimento

    private var ask: AskRequest? { askStore.state.active }
    private var page: Int {
        guard let ask else { return 0 }
        return min(askStore.state.page, ask.questions.count - 1)
    }
    private var question: AskQuestion? {
        guard let ask, ask.questions.indices.contains(page) else { return nil }
        return ask.questions[page]
    }

    /// Preview exibido: o da opção em destaque (vazio se ela não tem); sem
    /// destaque, o primeiro da pergunta.
    private func textoDoPreview(_ question: AskQuestion) -> String {
        if let destaque = askStore.state.highlight, question.options.indices.contains(destaque) {
            return question.options[destaque].preview ?? ""
        }
        return question.options.compactMap(\.preview).first ?? ""
    }

    // MARK: Tamanho do preview

    /// Avanço de um caractere e altura de uma linha da letra do preview na
    /// base de 11 pt, medidos da fonte de verdade uma vez só.
    private static let letraDoPreview: (avanco: CGFloat, linha: CGFloat) = {
        let fonte = NSFont.monospacedSystemFont(ofSize: AskPreviewLayout.base, weight: .regular)
        return (fonte.maximumAdvancement.width, fonte.ascender - fonte.descender + fonte.leading)
    }()

    /// Onde o preview fica, com que letra e que largura o card precisa. O card
    /// e o `NotchView` chamam esta mesma função, para nunca divergirem. `nil` =
    /// pergunta sem preview.
    static func layoutDoPreview(question: AskQuestion, disponivel: CGSize, topo: CGFloat) -> AskPreviewLayout? {
        func calcular(reserva: CGFloat) -> AskPreviewLayout? {
            // 150 = topo, pergunta, campo e legenda
            let alturaMaxima = max(120, disponivel.height - 24 - topo - 150 - reserva)
            var layout = AskPreviewLayout.calcular(
                previews: question.options.compactMap(\.preview),
                avanco: letraDoPreview.avanco,
                linha: letraDoPreview.linha,
                // o mesmo limite de largura do `NotchPresentation`
                larguraMaxima: disponivel.width - 64,
                alturaMaxima: alturaMaxima)
            // Quando rola, o quadro para na altura que cabe; o resto é da rolagem.
            if let calculado = layout, calculado.rola {
                layout?.quadro.height = min(calculado.quadro.height, alturaMaxima)
            }
            return layout
        }
        // Ao lado ou embaixo sai só da largura. Embaixo, o preview divide a
        // altura com a lista: guarda o mínimo dela e encolhe a letra antes de
        // empurrar o card para fora da tela.
        let layout = calcular(reserva: 0)
        guard let layout, !layout.lado else { return layout }
        return calcular(reserva: AskTeto.minimoDaLista)
    }

    var body: some View {
        Group {
            if let ask, let question {
                VStack(alignment: .leading, spacing: 8) {
                    topo(ask: ask, question: question)
                    // Trocar de aba troca só este bloco; o card em volta fica parado.
                    ZStack(alignment: .topLeading) {
                        conteudo(question: question, abas: ask.questions.count > 1)
                            .id(page)
                            .transition(.asymmetric(
                                insertion: reduzMovimento ? .opacity : .opacity.combined(with: .offset(x: 8)),
                                removal: .opacity))
                    }
                    .animation(.easeOut(duration: reduzMovimento ? 0.15 : 0.22), value: page)
                }
            }
        }
        .foregroundStyle(.white)
        // Em overlay, não em background: a chave fica com o último valor, e o
        // background entra ANTES do conteúdo (que não mede nada e zeraria a medida).
        .overlay(
            GeometryReader { proxy in
                Color.clear.preference(key: AlturaDoAskKey.self, value: proxy.size.height)
            }
            .allowsHitTesting(false)
        )
        .onPreferenceChange(AlturaDoAskKey.self) { alturaDoCard = $0 }
        .onPreferenceChange(AlturaDaListaDoAskKey.self) { listaNatural = $0 ?? 0 }
        // Uma conta por rodada de medida, com o card e a lista do mesmo layout.
        .onChange(of: [listaNatural, alturaDoCard, alturaMaxima]) { refazerTetoDaLista() }
        // Esc (com o campo focado) = mesmo intent do ✕: pergunta vai pro terminal
        .onExitCommand { askStore.send(.cancelActive) }
    }

    // MARK: Topo

    private func topo(ask: AskRequest, question: AskQuestion) -> some View {
        HStack(spacing: 8) {
            if ask.questions.count > 1 {
                AskAbasView(perguntas: ask.questions, respostas: askStore.state.answers, pagina: page,
                            ir: { askStore.send(.goTo(page: $0)) })
            } else if !question.header.isEmpty {
                Text(question.header)
                    .font(AskEstilo.miudo.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(AskEstilo.fundoEmDestaque)))
            }
            Spacer(minLength: 0)
            if let source = ask.source, !source.isEmpty {
                // quem pergunta: pasta do projeto da sessão do Claude Code
                Text("◐ \(source)")
                    .font(AskEstilo.miudo.weight(.medium))
                    .foregroundStyle(.white.opacity(AskEstilo.tintaApagada))
                    .lineLimit(1)
            }
            Button { askStore.send(.cancelActive) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(sobreOFechar ? 1 : AskEstilo.tintaForte))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.white.opacity(
                        sobreOFechar ? AskEstilo.fundoMarcada : AskEstilo.fundoEmDestaque)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { sobreOFechar = $0 }
            .help("Responder no terminal")
            .accessibilityLabel("Responder no terminal")
        }
        .frame(height: 22)
    }

    // MARK: Pergunta, opções e rodapé

    private func conteudo(question: AskQuestion, abas: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.question)
                .font(AskEstilo.pergunta)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .padding(.bottom, 4)
            if let layout = Self.layoutDoPreview(question: question, disponivel: vm.availableSize,
                                                 topo: vm.hasRealNotch ? vm.notchSize.height : 4) {
                let previa = AskPreviewView(
                    texto: textoDoPreview(question), layout: layout,
                    passo: AskPreviewLayout.passo(linha: Self.letraDoPreview.linha, fonte: layout.fonte))
                if layout.lado {
                    HStack(alignment: .top, spacing: AskPreviewLayout.vao) {
                        lista(question: question).frame(width: AskPreviewLayout.lista)
                        previa
                    }
                } else {
                    // largo demais para ficar ao lado: desce e usa a largura toda
                    VStack(spacing: 8) {
                        lista(question: question)
                        previa
                    }
                }
            } else {
                lista(question: question)
            }
            AskRodapeView(
                texto: textBinding,
                foco: $textFocused,
                nivelDoDitado: nivelDoDitado,
                itens: AskLegenda.itens(teclado: false, campo: textFocused,
                                        multipla: question.multiSelect, abas: abas,
                                        atalho: vm.glifoDoAtalho()),
                enviar: {
                    let text = askStore.state.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    askStore.send(.submit(labels: question.multiSelect ? marcadas(question) : [],
                                          text: text))
                })
        }
    }

    /// A lista inteira quando cabe; acima do teto, só ela rola e o resto do
    /// card (topo, pergunta, preview, campo, legenda) fica parado.
    @ViewBuilder
    private func lista(question: AskQuestion) -> some View {
        if let teto = tetoDaLista {
            ScrollView(.vertical) { optionList(question: question) }
                // sem a barra clássica do macOS: com mouse conectado ela abre uma
                // calha de 17 pt e as linhas ficam mais estreitas que o campo;
                // a linha cortada embaixo já diz que a lista rola
                .scrollIndicators(.never)
                .frame(height: teto)
        } else {
            optionList(question: question)
        }
    }

    /// `tetoDaLista` ainda é a altura com que a lista foi desenhada na medida
    /// que chegou: é o `listaAtual` da conta.
    private func refazerTetoDaLista() {
        var teto = AskTeto.daLista(natural: listaNatural, card: alturaDoCard,
                                   listaAtual: tetoDaLista ?? listaNatural, tetoDoCard: alturaMaxima)
        // Ao lado do preview o card já tem a altura dele: a lista não fica
        // mais baixa que o preview.
        if let calculado = teto, let question,
           let layout = Self.layoutDoPreview(question: question, disponivel: vm.availableSize,
                                             topo: vm.hasRealNotch ? vm.notchSize.height : 4),
           layout.lado {
            teto = listaNatural > layout.quadro.height ? max(calculado, layout.quadro.height) : nil
        }
        // Diferença de fração de ponto é ruído da medida, não teto novo.
        if let teto, let tetoDaLista, abs(teto - tetoDaLista) < 0.5 { return }
        if teto != tetoDaLista { tetoDaLista = teto }
    }

    private func optionList(question: AskQuestion) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { indice, option in
                AskOpcaoView(
                    indice: indice, rotulo: option.label, descricao: option.description,
                    multipla: question.multiSelect,
                    marcada: estaMarcada(option, em: question),
                    destaque: askStore.state.highlight == indice,
                    teclado: false,
                    pairar: { dentro in
                        if dentro {
                            askStore.send(.setHighlight(indice))
                        } else if askStore.state.highlight == indice {
                            askStore.send(.setHighlight(nil))
                        }
                    },
                    clicar: {
                        if question.multiSelect {
                            askStore.send(.toggle(label: option.label))
                        } else {
                            askStore.send(.choose(index: indice))
                        }
                    })
            }
            if question.multiSelect {
                confirmar(question: question)
            }
        }
        // Altura natural: dentro da rolagem o conteúdo é desenhado inteiro, então
        // a medida vale com ou sem ela. Em overlay pelo mesmo motivo do card.
        .overlay(
            GeometryReader { proxy in
                Color.clear.preference(key: AlturaDaListaDoAskKey.self, value: proxy.size.height)
            }
            .allowsHitTesting(false)
        )
    }

    private func confirmar(question: AskQuestion) -> some View {
        let labels = marcadas(question)
        let aceso = !labels.isEmpty
        return Button { askStore.send(.submit(labels: labels, text: nil)) } label: {
            HStack(spacing: 8) {
                Text(aceso ? "Confirmar \(labels.count)" : "Confirmar")
                    .font(AskEstilo.rotulo)
                    .monospacedDigit()
                AskSeloView(texto: "⏎",
                            tinta: aceso ? AskEstilo.tintaSecundaria : AskEstilo.tintaDesabilitada)
            }
            .foregroundStyle(.white.opacity(aceso ? 1 : AskEstilo.tintaDesabilitada))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: AskEstilo.raio)
                .fill(.white.opacity(aceso ? AskEstilo.fundoMarcada : AskEstilo.fundoDoCampo)))
            .contentShape(RoundedRectangle(cornerRadius: AskEstilo.raio))
        }
        .buttonStyle(.plain)
        .disabled(!aceso)
    }

    /// Rótulos marcados na ordem das opções: o `Set` do estado não tem ordem.
    private func marcadas(_ question: AskQuestion) -> [String] {
        question.options.map(\.label).filter { askStore.state.selected.contains($0) }
    }

    /// Múltipla: está no conjunto marcado. Simples: é a resposta já dada.
    private func estaMarcada(_ option: AskOption, em question: AskQuestion) -> Bool {
        if question.multiSelect { return askStore.state.selected.contains(option.label) }
        return askStore.state.answers[question.question]?.labels.first == option.label
    }

    /// Ditado ativo alimenta o campo do card: o nível aparece DENTRO dele.
    private var nivelDoDitado: CGFloat? {
        if case .recording(let level) = vm.dictation { return CGFloat(level) }
        return nil
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { askStore.state.text },
            set: { askStore.send(.setText($0)) }
        )
    }
}

// MARK: - Altura medida

/// O card do Ask não tem altura previsível: a pergunta e as descrições variam
/// de linhas, e cada aba tem a sua. Ele mede a si mesmo e o `NotchView` usa
/// esse valor no lugar da estimativa por número de opções. Vale a última
/// medida, não a maior: o card encolhe ao trocar para uma pergunta menor.
struct AlturaDoAskKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Altura natural da lista de opções (com o Confirmar), medida por ela mesma.
/// Comparada ao teto, decide se a lista rola.
struct AlturaDaListaDoAskKey: PreferenceKey {
    static var defaultValue: CGFloat?
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        // A lista tem vizinhos depois dela (preview, rodapé) que não medem nada
        // e entram aqui sem valor: só uma medida de verdade troca o que há.
        value = nextValue() ?? value
    }
}
