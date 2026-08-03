//
//  NotchView.swift
//  Knobler
//

import SwiftUI

struct NotchView: View {
    @ObservedObject var vm: NotchViewModel
    let askStore: AskStore
    @ObservedObject var agentRequestStore: AgentRequestStore
    @ObservedObject var media: MediaController
    // NÃO observado aqui: os níveis publicam a 30Hz e re-renderizariam o notch
    // inteiro em cada monitor — só o AudioBarsView (folha) observa
    let levels: SystemAudioLevels
    @ObservedObject var shelf: ShelfStore
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var history = NotificationHistory.shared
    @ObservedObject private var note = QuickNote.shared
    @ObservedObject private var linkPreview = LinkPreview.shared
    /// Só pra saber se há conversa (o `hasMensagens` da ordem das seções). O
    /// store não tem singleton: quem injeta é o app (e o harness de snapshot).
    @EnvironmentObject private var messages: MessageStore
    @FocusState private var noteFocused: Bool
    /// false no harness de snapshot: onDrop cria uma NSView que o ImageRenderer
    /// não renderiza (vira placeholder amarelo). No app fica sempre true.
    var dropTargetsEnabled = true
    /// Só o harness usa isso para capturar o estado expandido sem automação.
    var agentRequestInitiallyExpanded = false
    var onKeyboardEligibilityChanged: ((Bool) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var agentRequestExpanded = false

    /// A prioridade Ask é derivada do store compartilhado; o VM fornece apenas
    /// o modo dos demais subsistemas visuais.
    private var mode: NotchViewModel.Mode {
        askStore.state.active == nil && agentRequestStore.state.active == nil ? vm.mode : .question
    }

    /// A nota mora numa tela só (a que estava sob o mouse quando ligou). Nas
    /// outras ela simplesmente não existe: nada desenha, nada pede teclado.
    private var noteVisible: Bool {
        note.hosted(by: vm.displayID)
    }

    private var keyboardAllowed: Bool {
        askStore.state.active != nil
            || agentRequestStore.state.active != nil
            || vm.incoming?.allowReply == true
            || (vm.focus == .mensagens && vm.expanded)
            // o campo da nota só existe na árvore quando ela é a seção em foco —
            // pedir a janela-chave fora disso engoliria as teclas em silêncio
            || (noteVisible && vm.expanded && vm.focus == .nota)
            // a página do preview tem campo de busca, login e formulário: sem a
            // janela-chave o site fica só de leitura
            || (vm.focus == .link && vm.expanded
                && linkPreview.hosted(by: vm.displayID))
    }

    private func notifyKeyboardEligibility() {
        onKeyboardEligibilityChanged?(keyboardAllowed)
    }

    /// Abrir tem leve overshoot (assinatura do Dynamic Island); fechar é seco.
    /// Reduced Motion vira fade rápido.
    private var morphAnimation: Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        let opening = mode != .closed || vm.peeking
        return opening
            ? .spring(response: 0.42, dampingFraction: 0.76)
            : .spring(response: 0.30, dampingFraction: 0.95)
    }

    /// Altura do campo da nota. Mesma regra da `HistoryListView.listHeight`:
    /// o `currentSize` soma ESTA constante, então layout e moldura mudam juntos.
    static let noteEditorHeight: CGFloat = 120
    /// Cada seção manda na própria altura. Antes isto era uma soma
    /// combinatória no `currentSize` (`height += hasMusic || hasShelf ? 46 : 60`),
    /// que já tinha causado moldura menor que o conteúdo.
    /// O card do link é mais largo que o resto: uma página de site em 386 pt
    /// não é leitura, é miniatura.
    static let linkCardWidth: CGFloat = 780
    /// Sobra depois das margens internas do card (as mesmas 44 do `.frame`).
    static var linkContentWidth: CGFloat { linkCardWidth - 44 }
    /// A página em 16:9, a proporção de tela que o site espera. A altura da
    /// seção soma o cabeçalho de controles.
    static var linkWebHeight: CGFloat { (linkContentWidth * 9 / 16).rounded() }
    static let linkHeaderHeight: CGFloat = 24

    /// Largura do card por seção em foco: só o link foge do padrão.
    static func larguraDoCard(_ focus: NotchSection?, padrao: CGFloat) -> CGFloat {
        focus == .link ? linkCardWidth : padrao
    }

    /// A prateleira é a única seção com duas alturas: a grade de itens é uma
    /// linha, o preview de conversão empilha presets e botões.
    static let shelfPreviewHeight: CGFloat = 112
    static func alturaDaSecao(_ s: NotchSection, preview: Bool = false) -> CGFloat {
        switch s {
        case .musica: return 118
        case .atividade: return 60
        case .pomodoro: return 128
        case .shelf: return preview ? shelfPreviewHeight : 76
        case .espelho: return 202
        case .mensagens: return 272
        case .historico: return HistoryListView.listHeight + 12
        case .nota: return Self.noteEditorHeight + 20
        case .link: return linkWebHeight + linkHeaderHeight
        }
    }

    private let expandedSize = CGSize(width: NotchGesture.larguraDoCard, height: 188)
    private let notificationWidth: CGFloat = 380
    // asinhas do estado fechado quando tem música tocando (capa + visualizer)
    private let wingWidth: CGFloat = 44
    private let hudWingWidth: CGFloat = 85

    var body: some View {
        VStack(spacing: 0) {
            interactiveNotch
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var hasMusic: Bool { media.state != nil }

    /// Pausado, a música se esconde; hover espia (peeking) antes do card completo.
    private var wingsVisible: Bool {
        hasMusic && (media.state?.isPlaying == true || vm.peeking)
    }

    /// Nota ligada COM texto: o notch fechado precisa dizer que tem coisa lá
    /// dentro. Sem isso o usuário fecha o card, trabalha meia hora, esquece, e
    /// desliga o interruptor achando que está limpando um campo vazio — o
    /// clipboard salva o texto hoje, mas continua sendo surpresa.
    /// Só na tela dona, como todo o resto da nota.
    private var noteBadge: Bool {
        noteVisible && !note.text.isEmpty
    }

    /// Tem asa no fechado? A view e o `currentSize` precisam concordar — quando
    /// divergiam, o conteúdo desenhava fora da moldura.
    private var closedHasContent: Bool {
        wingsVisible || vm.activity != nil || vm.micInUse || noteBadge
    }

    private var notch: some View {
        let compact = mode == .closed || mode == .hud
            || mode == .dictation || mode == .pomodoro
        // raios menores no compacto: as curvas de canto decepavam a capa/barras
        let shape = NotchShape(
            topCornerRadius: compact ? 6 : 14,
            bottomCornerRadius: compact ? 12 : 30
        )
        return ZStack(alignment: .top) {
            shape.fill(Color.black)

            switch mode {
            case .closed:
                if closedHasContent {
                    closedWings
                        .transition(.blurReplace)
                }
            case .hud:
                hudPill
                    .transition(.blurReplace)
            case .dictation:
                dictationPill
                    .transition(.blurReplace)
            case .music:
                expandedContent
                    // largura fixa: o texto não pode refluir enquanto a forma anima
                    .frame(width: Self.larguraDoCard(vm.focus,
                                                     padrao: expandedSize.width) - 44)
                    .padding(.top, topInset + 8)
                    .padding(.bottom, 14)
                    // o conteúdo cresce junto com a moldura, ancorado no topo
                    .transition(.blurReplace.combined(
                        with: .scale(0.94, anchor: .top)))
            case .pomodoro:
                pomodoroPill
                    .transition(.blurReplace)
            case .notification:
                notificationCard
                    .frame(width: notificationWidth - 48,
                           height: vm.activeNotification?.actionTitles.isEmpty == false
                               ? 92 : 56, alignment: .top)
                    .padding(.top, topInset)
                    // notificação desce do notch, como no iPhone
                    .transition(.blurReplace.combined(with: .move(edge: .top)))
            case .message:
                if let incoming = vm.incoming {
                    IncomingMessageView(vm: vm, incoming: incoming)
                        .frame(width: 360 - 40)
                        .padding(.top, topInset)
                        .padding(.bottom, 12)
                        .transition(.blurReplace.combined(with: .move(edge: .top)))
                }
            case .question:
                questionCard
                    // pergunta desce do notch, como as notificações
                    .transition(.blurReplace.combined(with: .move(edge: .top)))
            case .airpods:
                airpodsConnectCard
                    .frame(width: 320 - 40)
                    .padding(.top, topInset)
                    .padding(.bottom, 12)
                    // desce do notch, como as notificações
                    .transition(.blurReplace.combined(with: .move(edge: .top)))
            case .update:
                updateNotchCard
                    .frame(width: 380 - 40)
                    .padding(.top, topInset)
                    .padding(.bottom, 12)
                    // desce do notch, como as notificações
                    .transition(.blurReplace.combined(with: .move(edge: .top)))
            }
        }
        // recorta o conteúdo com a própria forma do notch — fechando, a informação
        // some junto com a moldura, em sincronia
        .compositingGroup()
        .mask(shape)
        // aberto, o notch "flutua" sobre o wallpaper; fechado, some na moldura
        .shadow(
            color: .black.opacity(mode == .closed ? 0 : 0.35),
            radius: 12, y: 5
        )
        .frame(width: currentSize.width, height: currentSize.height)
        // folga invisível de hover ao redor do card aberto: jitter na borda
        // não fecha; e o hit-test cobre o retângulo todo, não só o desenhado.
        // A constante vem do NotchGesture porque a zona do scroll soma a MESMA
        // folga — separar as duas deixaria uma tira que responde ao hover e
        // não ao gesto.
        .padding(.horizontal, mode == .music ? NotchGesture.folgaDeHover : 0)
        .padding(.bottom, mode == .music ? NotchGesture.folgaDeHover : 0)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var interactiveNotch: some View {
        Group {
            if dropTargetsEnabled {
                // a lista tem que bater com a do `ShelfDropDelegate.validateDrop`:
                // o `of:` filtra ANTES do delegate, e um tipo que falte aqui
                // nunca chega lá (foi assim que link arrastado do navegador
                // sumia sem erro nenhum)
                notch.onDrop(
                    of: [.fileURL, .url, .plainText],
                    delegate: ShelfDropDelegate(shelf: shelf, vm: vm))
            } else {
                notch
            }
        }
        .onHover { inside in
            if mode == .notification {
                vm.holdNotification(inside)
            } else if mode == .message {
                vm.holdIncoming(inside)
            } else if !inside || mode != .question {
                // O card de pergunta usa hover para preview e clique; não deixe
                // esse movimento alterar o estado de expansão da música.
                vm.setHover(inside)
            }
        }
        .animation(morphAnimation, value: mode)
        .animation(morphAnimation, value: wingsVisible)
        // asa aparece/some com o pontinho da nota, não só com a música
        .animation(morphAnimation, value: noteBadge)
        .animation(morphAnimation, value: vm.micInUse)
        .animation(morphAnimation, value: askStore.state.active?.id)
        .animation(morphAnimation, value: agentRequestStore.state.active?.id)
        .animation(morphAnimation, value: askStore.state.page)
        .onAppear {
            agentRequestExpanded = agentRequestInitiallyExpanded
            notifyKeyboardEligibility()
        }
        .onChange(of: askStore.state.active?.id) { _, _ in notifyKeyboardEligibility() }
        .onChange(of: agentRequestStore.state.active?.id) { _, _ in
            agentRequestExpanded = false
            notifyKeyboardEligibility()
        }
        .onChange(of: vm.incoming?.allowReply) { _, _ in notifyKeyboardEligibility() }
        .onChange(of: vm.focus) { _, _ in notifyKeyboardEligibility() }
        .onChange(of: vm.expanded) { _, _ in notifyKeyboardEligibility() }
        .onChange(of: note.active) { _, _ in notifyKeyboardEligibility() }
        // o teclado segue o dono, não só o interruptor
        .onChange(of: note.hostDisplayID) { _, _ in notifyKeyboardEligibility() }
        // trocar de link com a seção já em foco não passa pelo `vm.focus`
        .onChange(of: linkPreview.url) { _, _ in notifyKeyboardEligibility() }
        // digitar segura as notificações; parar de digitar solta a fila
        .onChange(of: note.editing) { _, editing in
            if !editing { vm.resumePendingNotifications() }
        }
        .modifier(CarimboDeEventos(vm: vm,
                                   faixa: media.state?.title,
                                   tocando: media.state?.isPlaying,
                                   itensShelf: shelf.items.count,
                                   itensHistorico: history.items.count,
                                   notaVazia: note.text.isEmpty))
        .modifier(AberturaDoCard(vm: vm,
                                 altura: currentSize.height,
                                 hasMusic: hasMusic,
                                 hasShelf: !shelf.items.isEmpty,
                                 hasHistory: !history.items.isEmpty,
                                 hasMensagens: !messages.threads.isEmpty,
                                 hasNota: noteVisible,
                                 hasLink: linkPreview.hosted(by: vm.displayID)))
    }

    /// Faixa morta no topo dos cards: só existe onde tem câmera de verdade.
    private var topInset: CGFloat {
        vm.hasRealNotch ? vm.notchSize.height : 4
    }

    private var currentSize: CGSize {
        // notch real: asas ao redor da câmera; externo: o conteúdo dita o tamanho
        switch mode {
        case .closed:
            let hasContent = closedHasContent
            if vm.hasRealNotch {
                return CGSize(
                    width: vm.notchSize.width + (hasContent ? wingWidth * 2 : 0),
                    height: vm.notchSize.height
                )
            }
            // externo vazio não pode sumir: 160 mantém presença sem as asas
            return CGSize(width: hasContent ? 200 : 160, height: vm.notchSize.height)
        case .hud, .dictation, .pomodoro:
            return CGSize(
                width: vm.hasRealNotch ? vm.notchSize.width + hudWingWidth * 2 : 232,
                height: vm.notchSize.height
            )
        case .music:
            // Parcela por parcela, as MESMAS que o `expandedContent` desenha:
            // `.padding(.top, topInset + 8)`, a seção em foco, o espaçamento de 8
            // da VStack, a faixa do rodapé (mais o segundo espaçamento de 8) e
            // `.padding(.bottom, 14)`. Divergir daqui é o modo de falha clássico
            // deste arquivo: o conteúdo sai da moldura, a `.frame` centraliza e a
            // metade de baixo do card cai fora do `.onHover` — mover o mouse pra
            // lá lê como saída e fecha o card.
            let corpo = vm.focus.map {
                Self.alturaDaSecao($0, preview: shelf.preview != nil)
            } ?? 118
            // a nota é modo exclusivo: sem faixa, e sem o espaçamento dela
            let faixa = vm.focus == .nota ? 0 : Self.sectionStripHeight + 8
            let chrome = topInset + 8 + 8 + 14
            return CGSize(
                width: Self.larguraDoCard(vm.focus, padrao: expandedSize.width),
                height: chrome + corpo + faixa)
        case .notification:
            let hasActions = vm.activeNotification?.actionTitles.isEmpty == false
            return CGSize(width: notificationWidth,
                          height: topInset + 56 + (hasActions ? 36 : 0))
        case .message:
            let tall = vm.incoming?.allowReply == true
            // a imagem toma a largura toda do card; a altura vem do app (aspecto real)
            let media = vm.incoming?.mediaHeight ?? 0
            return CGSize(width: 360,
                          height: topInset + (tall ? 108 : 72) + (media > 0 ? media + 6 : 0))
        case .airpods:
            return CGSize(width: 320, height: topInset + 64)
        case .update:
            // título + até 2 linhas de notas; sem folga morta embaixo
            return CGSize(width: 380, height: topInset + 72)
        case .question:
            if let request = agentRequestStore.state.active, askStore.state.active == nil {
                let detailsHeight: CGFloat = agentRequestExpanded && request.details?.isEmpty == false
                    ? 144 : 0
                return CGSize(width: 460, height: topInset + 116 + detailsHeight)
            }
            guard let ask = askStore.state.active else {
                return CGSize(width: 460, height: topInset + 120)
            }
            let question = ask.questions[min(askStore.state.page, ask.questions.count - 1)]
            let hasPreview = question.options.contains { $0.preview != nil }
            // título+chip (46) + opções (48 cada) + rodapé com campo de texto (44)
            var height = topInset + 46 + CGFloat(question.options.count) * 48 + 44
            if question.multiSelect { height += 34 }  // botão Confirmar
            if hasPreview { height = max(height, topInset + 200) }
            return CGSize(width: hasPreview ? 540 : 460, height: min(height, 500))
        }
    }

    // MARK: - HUD de som (pílula inline)

    @ViewBuilder
    private var hudPill: some View {
        if let hud = vm.hud {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: Self.hudIcon(hud))
                        .font(.footnote)
                        .frame(width: 18, alignment: .leading)
                        .contentTransition(.symbolEffect(.replace))
                    Text(Self.hudLabel(hud))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.leading, 16)
                Spacer(minLength: 0)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule()
                        .fill(Self.hudBarColor(hud))
                        .frame(width: max(0, 64 * CGFloat(hud.level)))
                }
                .frame(width: 64, height: 6)
                .padding(.trailing, 16)
                // resposta curta + quase sem overshoot: desliza contínuo quando os
                // passos chegam em rajada (segurar a tecla), em vez de pular
                .animation(.spring(response: 0.18, dampingFraction: 0.95), value: hud.level)
            }
            .frame(height: vm.notchSize.height)
        }
    }

    // MARK: - Pílula de ditado

    @ViewBuilder
    private var dictationPill: some View {
        if let phase = vm.dictation {
            HStack(spacing: 8) {
                switch phase {
                case .preparing:
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Baixando modelo…")
                        .font(.subheadline.weight(.semibold))
                case .recording(let level):
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Ouvindo")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(.white)
                            .frame(width: max(4, 64 * CGFloat(level)))
                    }
                    .frame(width: 64, height: 6)
                    .animation(.spring(response: 0.2, dampingFraction: 0.9), value: level)
                case .transcribing:
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Transcrevendo…")
                        .font(.subheadline.weight(.semibold))
                case .error(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: vm.notchSize.height)
        }
    }

    // MARK: - Pílula do Pomodoro

    @ViewBuilder
    private var pomodoroPill: some View {
        if let p = vm.pomodoro {
            let focus = p.phase == .focus
            let tint: Color = focus
                ? Color(red: 1.00, green: 0.45, blue: 0.32)   // tomate (foco)
                : Color(red: 0.30, green: 0.82, blue: 0.55)   // verde (pausa)
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: focus ? "brain.head.profile" : "cup.and.saucer.fill")
                        .font(.footnote)
                        .foregroundStyle(tint)
                    if p.runState == .paused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    if p.runState == .waiting {
                        Text(Self.pomodoroWaitingLabel(p.phase))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.leading, vm.hasRealNotch ? 14 : 16)
                Spacer(minLength: 0)
                Text(Self.mmss(p.remaining))
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.trailing, vm.hasRealNotch ? 14 : 16)
            }
            .frame(height: vm.notchSize.height)
        }
    }

    /// "Foco ▸" / "Pausa ▸" / "Pausa longa ▸" — a próxima ação na espera.
    private static func pomodoroWaitingLabel(_ phase: PomodoroPhase) -> String {
        switch phase {
        case .focus: return "Foco ▸"
        case .shortBreak: return "Pausa ▸"
        case .longBreak: return "Pausa longa ▸"
        }
    }

    private static func mmss(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: - Card do Pomodoro (expandido)

    /// Seção no topo do card enquanto o Pomodoro está ativo: fase + timer grande
    /// + "Ciclo N de M" (no foco) + controles clicáveis. A música fica suprimida.
    @ViewBuilder
    private func pomodoroSection(_ p: PomodoroState) -> some View {
        let focus = p.phase == .focus
        let tint: Color = focus
            ? Color(red: 1.00, green: 0.45, blue: 0.32)   // tomate (foco)
            : Color(red: 0.30, green: 0.82, blue: 0.55)   // verde (pausa)
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: focus ? "brain.head.profile" : "cup.and.saucer.fill")
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(Self.pomodoroPhaseLabel(p.phase))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button { vm.onPomodoroSettings?() } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Self.mmss(p.remaining))
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                if focus, p.cyclesUntilLong > 0 {
                    Text("Ciclo \(p.completedFocus % p.cyclesUntilLong + 1) de \(p.cyclesUntilLong)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            pomodoroControls(p, tint: tint, focus: focus)
        }
    }

    @ViewBuilder
    private func pomodoroControls(_ p: PomodoroState, tint: Color, focus: Bool) -> some View {
        HStack(spacing: 8) {
            switch p.runState {
            case .running:
                pomodoroButton("Pausar", "pause.fill", tint) { vm.onPomodoroPause?() }
                pomodoroButton("Pular", "forward.end.fill", nil) { vm.onPomodoroSkip?() }
                pomodoroButton("Resetar", "arrow.counterclockwise", nil) { vm.onPomodoroReset?() }
            case .paused:
                pomodoroButton("Retomar", "play.fill", tint) { vm.onPomodoroResume?() }
                pomodoroButton("Pular", "forward.end.fill", nil) { vm.onPomodoroSkip?() }
                pomodoroButton("Resetar", "arrow.counterclockwise", nil) { vm.onPomodoroReset?() }
            case .waiting:
                pomodoroButton(focus ? "Iniciar foco" : "Iniciar pausa", "play.fill", tint) {
                    vm.onPomodoroStartNext?()
                }
                pomodoroButton("Resetar", "arrow.counterclockwise", nil) { vm.onPomodoroReset?() }
            case .idle:
                EmptyView()
            }
        }
    }

    private func pomodoroButton(
        _ label: String, _ icon: String, _ tint: Color?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption.weight(.bold))
                Text(label).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(tint?.opacity(0.9) ?? Color.white.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
    }

    private static func pomodoroPhaseLabel(_ phase: PomodoroPhase) -> String {
        switch phase {
        case .focus: return "Foco"
        case .shortBreak: return "Pausa"
        case .longBreak: return "Pausa longa"
        }
    }

    // MARK: - Card de pergunta (Claude Code)

    @ViewBuilder
    private var questionCard: some View {
        if askStore.state.active != nil {
            AskCardView(vm: vm, askStore: askStore)
                .frame(width: currentSize.width - 40)
                .padding(.top, topInset + 6)
                .padding(.bottom, 12)
        } else if let request = agentRequestStore.state.active {
            AgentRequestCard(
                request: request, store: agentRequestStore,
                expanded: $agentRequestExpanded,
                // ImageRenderer não desenha Text selecionável no harness.
                detailsSelectable: dropTargetsEnabled
            )
            .frame(width: currentSize.width - 40)
            .padding(.top, topInset + 6)
            .padding(.bottom, 12)
            .id(request.id)
        }
    }

    private static func hudIcon(_ hud: NotchViewModel.HUDState) -> String {
        switch hud.kind {
        case .volume:
            if hud.muted || hud.level == 0 { return "speaker.slash.fill" }
            switch hud.level {
            case ..<0.34: return "speaker.wave.1.fill"
            case ..<0.67: return "speaker.wave.2.fill"
            default: return "speaker.wave.3.fill"
            }
        case .brightness:
            return hud.level < 0.34 ? "sun.min.fill" : "sun.max.fill"
        case .battery:
            return hud.charging ? "battery.100.bolt" : "battery.25"
        }
    }

    private static func hudLabel(_ hud: NotchViewModel.HUDState) -> String {
        switch hud.kind {
        case .volume: return hud.muted ? "Mute" : "Sound"
        case .brightness: return "Brightness"
        case .battery:
            let percent = Int((hud.level * 100).rounded())
            return hud.charging ? "Charging · \(percent)%" : "Battery · \(percent)%"
        }
    }

    private static func hudBarColor(_ hud: NotchViewModel.HUDState) -> Color {
        guard hud.kind == .battery else { return .white }
        if hud.charging { return .green }
        return hud.level <= 0.2 ? .red : .white
    }

    // MARK: - Fechado com música: capa à esquerda, visualizer à direita

    private var closedWings: some View {
        // paddings ≥ raio de canto inferior pra ficar fora da zona de curvatura
        HStack(spacing: 0) {
            if wingsVisible {
                miniArtwork
                    .id(media.state?.title)
                    .transition(.blurReplace)
                    .padding(.leading, vm.hasRealNotch ? 12 : 14)
            }
            Spacer(minLength: 0)
            // asa direita: mic em uso + (atividade OU barras de áudio)
            HStack(spacing: 8) {
                // pontinho da nota: dica ambiente, sem ícone e sem cor própria —
                // "tem rascunho aqui" não é urgente como o mic laranja.
                // Ink Tertiary (60%) em vez do Ink Faint que a DESIGN.md reserva
                // pra placeholder: num alvo de 4 pt, 30% some contra o preto.
                if noteBadge {
                    Circle()
                        .fill(.white.opacity(0.6))
                        .frame(width: 4, height: 4)
                        .transition(.blurReplace)
                }
                if vm.micInUse {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .transition(.blurReplace)
                }
                if let activity = vm.activity {
                    ActivityRingView(progress: activity.progress)
                        .frame(width: 17, height: 17)
                        .transition(.blurReplace)
                } else if wingsVisible {
                    audioBars
                        .frame(width: 27, height: 21)
                }
            }
            .padding(.trailing, vm.hasRealNotch ? 12 : 14)
        }
        .frame(height: vm.notchSize.height)
        .animation(.easeOut(duration: 0.3), value: media.state?.title)
        .animation(.easeOut(duration: 0.3), value: vm.activity == nil)
    }

    private var audioBars: some View {
        AudioBarsView(
            playing: media.state?.isPlaying == true,
            levels: levels,
            tint: media.artworkTint ?? .white
        )
    }

    private var miniArtwork: some View {
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.15))
            }
        }
        .frame(width: 25, height: 25)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    // MARK: - Nota rápida

    /// Desliga o scroller do `NSScrollView` que o `TextEditor` embrulha — o
    /// SwiftUI não expõe isso por modificador nenhum no macOS.
    ///
    /// `.scrollIndicators(.hidden)` não pega em `TextEditor` no macOS, e no
    /// macOS 26 ele embrulha um `AppKitScrollView` cujo `hasVerticalScroller`
    /// sozinho também não bastou — por isso o `NSScroller` é escondido direto.
    ///
    /// ponytail: varredura de árvore, porque não há API. Teto conhecido: se o
    /// SwiftUI mudar a hierarquia interna, o laço não acha nada e a barra volta
    /// — falha em silêncio, para no comportamento de hoje, não quebra. A saída
    /// definitiva é trocar o `TextEditor` por um `NSTextView` próprio; custo
    /// alto pra um campo que vive minutos.
    private struct ScrollerHider: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { NSView() }

        func updateNSView(_ view: NSView, context: Context) {
            // async: no momento do update a árvore do TextEditor ainda não
            // existe embaixo da janela.
            DispatchQueue.main.async {
                guard let root = view.window?.contentView else { return }
                Self.hideScrollers(in: root)
            }
        }

        /// Varre pra BAIXO a partir da janela: o `.background` é irmão do
        /// TextEditor, não ancestral, então subir por `superview` não acha nada.
        /// Pega todo scroller da janela do notch, e isso é seguro porque a nota
        /// é modo exclusivo — a lista do histórico nunca está na árvore junto.
        private static func hideScrollers(in view: NSView) {
            if let scroll = view as? NSScrollView {
                scroll.hasVerticalScroller = false
                scroll.scrollerStyle = .overlay
            }
            // o scroller some por ele mesmo também: no macOS 26 o TextEditor usa
            // um `AppKitScrollView` próprio e reativar o flag acima não bastou.
            if let scroller = view as? NSScroller {
                scroller.isHidden = true
                scroller.alphaValue = 0
            }
            view.subviews.forEach(hideScrollers)
        }
    }

    /// ponytail: texto simples, não rich text. Negrito e itálico exigiriam
    /// NSAttributedString e uma barra de formatação pra uma nota que vive
    /// minutos.
    private var noteSection: some View {
        TextEditor(text: $note.text)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.92))
            .scrollContentBackground(.hidden)
            // `scrollContentBackground` esconde o fundo, não o scroller, e
            // `.scrollIndicators(.hidden)` não pega em TextEditor no macOS
            // (testado no app real). Quem usa "Mostrar barras de rolagem:
            // sempre" via uma barra cinza parada dentro do card, com o campo
            // VAZIO — barra de sistema dentro do notch é o "widget de terceiro"
            // que o DESIGN.md proíbe.
            .background(ScrollerHider())
            .focused($noteFocused)
            .frame(height: Self.noteEditorHeight)
            // Campo vazio é um retângulo preto com um cursor: o placeholder é o
            // único lugar onde cabe dizer que o texto morre no desligar.
            // Ink Tertiary (60%), não o Ink Faint (30%) que a DESIGN.md dá pra
            // placeholder: 30% sobre preto puro dá 2,6:1 e o PRODUCT.md exige
            // 4,5:1. Vai ANTES do padding externo pra alinhar com o inset
            // interno do TextEditor, não com a moldura.
            //
            // O 5 no leading NÃO é chute: medido no app real, o NSTextView por
            // baixo tem textContainerInset (0,0) e lineFragmentPadding 5, então
            // a primeira linha digitada nasce exatamente em (5, 0). Sem topo
            // nenhum — um padding aqui faria o placeholder pular pra cima na
            // primeira tecla.
            .overlay(alignment: .topLeading) {
                if note.text.isEmpty {
                    Text("Rascunho — some ao desligar")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 4)
            .onAppear { noteFocused = true }
            .onChange(of: noteFocused) { _, focused in note.editing = focused }
            // Esc precisa liberar o foco explicitamente: TextEditor não
            // garante isso por padrão, e a guarda de hover em
            // NotchViewModel.setHover depende de note.editing virar false.
            .onExitCommand { noteFocused = false }
            // cinto e suspensório: o campo também sai da árvore por caminhos
            // que não passam pelo onChange acima (uma notificação tira o modo
            // de .music, um gesto fecha o card). O SwiftUI costuma zerar o
            // @FocusState nessa hora, mas não é contrato — e um `editing`
            // preso em true trava TODO notch aberto pra sempre, sem saída
            // pelo lado do usuário.
            .onDisappear {
                noteFocused = false
                note.editing = false
            }
    }

    // MARK: - Música expandida

    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 8) {
            Group {
                switch vm.focus {
                case .nota: noteSection
                case .historico: HistoryListView(history: history,
                                                 onOpen: { vm.setExpandedDirect(false) })
                case .mensagens: MessagesView(vm: vm)
                case .espelho: if vm.mirrorOn { mirrorSection } else { espelhoDesligado }
                case .shelf: ShelfRowView(shelf: shelf, vm: vm, onAirDrop: vm.onAirDrop)
                case .link: if linkPreview.url != nil { LinkPreviewView(preview: linkPreview) }
                           else { vazio("globe", "Nenhum link copiado") }
                case .atividade:
                    if let a = vm.activity { activityRow(a) }
                    else { vazio("arrow.triangle.2.circlepath", "Nenhuma atividade") }
                case .pomodoro:
                    // ponytail: texto, não botão. `Pomodoro.startNext()` só sai
                    // de `.waiting`; não existe "iniciar do zero" no VM hoje.
                    // Vira ação quando alguém pedir.
                    if let p = vm.pomodoro { pomodoroSection(p) }
                    else { vazio("timer", "Pomodoro parado") }
                case .musica, .none: musicSection
                }
            }
            .transition(.blurReplace)
            Spacer(minLength: 0)
            // a nota é modo exclusivo: enquanto o teclado está nos dedos a faixa
            // não pode oferecer um caminho pra fora do campo
            if vm.focus != .nota { sectionStrip }
        }
        .animation(.easeOut(duration: 0.3), value: vm.focus)
    }

    /// Altura da faixa do rodapé. Fixa e não intrínseca de propósito: o maior
    /// desenho lá dentro é o anel de progresso da atividade (14) mais o padding
    /// de 4 de cada lado do alvo de clique, e o `currentSize` soma ESTA
    /// constante. Deixar a faixa medir sozinha era o caminho pra moldura e
    /// conteúdo divergirem de novo.
    static let sectionStripHeight: CGFloat = 22

    /// Rodapé do card: as seções que não estão em foco, cada uma com um sinal
    /// vivo mínimo. Você perde o detalhe, não o glance.
    private var sectionStrip: some View {
        HStack(spacing: 10) {
            ForEach(vm.secoes, id: \.self) { s in
                Button {
                    withAnimation(.easeOut(duration: 0.22)) { vm.focar(s) }
                } label: {
                    ZStack {
                        Image(systemName: s.simbolo)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(vm.focus == s ? 0.9 : 0.35))
                        sinalVivo(s)
                    }
                    // alvo de clique maior que o desenho
                    .padding(4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.titulo)
            }
        }
        .frame(height: Self.sectionStripHeight)
    }

    /// O sinal de cada ícone: anel pra progresso, ponto pra "está rolando",
    /// contagem pra pilha.
    @ViewBuilder
    private func sinalVivo(_ s: NotchSection) -> some View {
        switch s {
        case .atividade:
            if let p = vm.activity?.progress {
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(.white.opacity(0.7), lineWidth: 1.5)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 14, height: 14)
            }
        case .musica:
            if media.state?.isPlaying == true {
                Circle().fill(.white.opacity(0.8))
                    .frame(width: 3, height: 3)
                    .offset(x: 6, y: -6)
            }
        case .shelf:
            contagem(shelf.items.count)
        case .historico:
            contagem(history.items.count)
        case .nota:
            if !note.text.isEmpty {
                Circle().fill(.white.opacity(0.8))
                    .frame(width: 3, height: 3)
                    .offset(x: 6, y: -6)
            }
        case .link:
            if linkPreview.carregando {
                Circle().fill(.white.opacity(0.8))
                    .frame(width: 3, height: 3)
                    .offset(x: 6, y: -6)
            }
        case .pomodoro:
            if let p = vm.pomodoro, let fatia = Self.fatiaDoCiclo(p, settings: settings) {
                Circle()
                    .trim(from: 0, to: fatia)
                    .stroke(.white.opacity(0.7), lineWidth: 1.5)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 14, height: 14)
            }
        // espelho: ligado/desligado já é a presença do ícone na faixa.
        // mensagens: o sinal seria a contagem de não-lidas, que não existe hoje
        // (o store guarda a conversa, não o "lido") — melhor nada que inventar.
        case .espelho, .mensagens:
            EmptyView()
        }
    }

    /// Quanto falta da fase atual do Pomodoro, de 0 a 1 — o anel do ícone.
    ///
    /// A duração cheia da fase não vem no `PomodoroState` (só o `remaining`),
    /// então sai dos Ajustes, pelo mesmo par que o próprio `Pomodoro` usa —
    /// `pomodoroConfig` + `duration(of:config:)`. Mexer na config no meio de uma
    /// fase pode dar fração fora da faixa; daí o clamp.
    /// Parado (idle) não tem ciclo em andamento e não desenha anel.
    static func fatiaDoCiclo(_ p: PomodoroState, settings: AppSettings) -> CGFloat? {
        guard p.runState != .idle else { return nil }
        let total = Pomodoro.duration(of: p.phase, config: settings.pomodoroConfig)
        guard total > 0 else { return nil }
        return CGFloat(min(max(p.remaining / total, 0), 1))
    }

    @ViewBuilder
    private func contagem(_ n: Int) -> some View {
        if n > 0 {
            Text("\(n)")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .offset(x: 7, y: -6)
        }
    }

    // MARK: - Espelho

    private var mirrorSection: some View {
        MirrorPreviewView()
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                Button { vm.mirrorOn = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7), .black.opacity(0.45))
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            .overlay(alignment: .topLeading) { cameraPicker }
    }

    /// Setinha sobre o preview: troca a entrada de vídeo sem sair do notch.
    /// Só aparece com mais de uma câmera na máquina — com uma só não há escolha.
    @ViewBuilder
    private var cameraPicker: some View {
        let devices = MirrorController.availableDevices()
        if devices.count > 1 {
            Menu {
                Picker("", selection: $settings.mirrorDeviceID) {
                    Text("Automática").tag("")
                    ForEach(devices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7), .black.opacity(0.45))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .padding(8)
        }
    }

    /// Botão de ligar o espelho; negada a permissão, abre os ajustes de câmera.
    private var mirrorButton: some View {
        Button {
            if vm.mirrorOn {
                vm.mirrorOn = false
                return
            }
            MirrorController.requestAccess { granted in
                if granted {
                    vm.mirrorOn = true
                } else if let url = URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
        } label: {
            Image(systemName: vm.mirrorOn ? "video.fill" : "video")
                .font(.body)
                .foregroundStyle(vm.mirrorOn ? .white : .white.opacity(0.45))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    /// Desenho comum de seção fixada e vazia. Mesma altura da seção cheia:
    /// uma altura só evita um segundo eixo de casos no `alturaDaSecao`.
    private func vazio(_ simbolo: String, _ texto: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: simbolo)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.4))
            Text(texto)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Espelho fixado e desligado: o botão que já existe, centralizado.
    private var espelhoDesligado: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.square")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.4))
            mirrorButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activityRow(_ activity: NotchActivity) -> some View {
        HStack(spacing: 10) {
            ActivityRingView(progress: activity.progress)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !activity.detail.isEmpty {
                    Text(activity.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 0)
            if let progress = activity.progress {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .contentTransition(.numericText())
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: activity.progress)
    }

    @ViewBuilder
    private var musicSection: some View {
        if let state = media.state {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    artworkView
                        .id(state.title + state.artist)
                        .transition(.blurReplace)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                        Text(state.artist)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                    Spacer(minLength: 0)
                }
                progressBar(state)
                controls(state)
            }
            .frame(maxWidth: .infinity)
            // troca de faixa: capa e textos fazem crossfade em vez de pop
            .animation(.easeOut(duration: 0.3), value: state.title)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.4))
                Text("Nada tocando")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                mirrorButton
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var artworkView: some View {
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(0.3))
                    }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
    }

    private func progressBar(_ state: MediaController.PlaybackState) -> some View {
        // TimelineView só existe enquanto expandido — zero custo com o notch fechado
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = media.currentPosition(at: context.date)
            let fraction = state.duration > 0 ? position / state.duration : 0
            HStack(spacing: 10) {
                Text(Self.timeString(position))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule()
                            .fill(.white)
                            .frame(width: max(5, geo.size.width * fraction))
                    }
                }
                .frame(height: 5)
                // sem duração (live) não há "quanto falta" — mantém a altura da linha
                Text(state.duration > 0
                     ? "-" + Self.timeString(max(0, state.duration - position))
                     : "–:––")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    // 5 itens distribuídos na largura toda:
    // shuffle · backward · play/pause (maior) · forward · espelho
    private func controls(_ state: MediaController.PlaybackState) -> some View {
        HStack(spacing: 0) {
            Button { media.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.body)
                    .foregroundStyle(state.shuffling ? .white : .white.opacity(0.45))
                    .contentTransition(.symbolEffect(.replace))
            }
            // fonte sem shuffle (navegador) → botão apagado, layout estável
            .disabled(!state.shuffleAvailable)
            .opacity(state.shuffleAvailable ? 1 : 0.2)
            Spacer()
            Button { media.previousTrack() } label: {
                Image(systemName: "backward.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            Spacer()
            Button { media.playPause() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 30)
            }
            Spacer()
            Button { media.nextTrack() } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            Spacer()
            mirrorButton
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Notificação

    @ViewBuilder
    private var notificationCard: some View {
        if let notification = vm.activeNotification {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    appIcon(for: notification)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notification.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !notification.body.isEmpty {
                            Text(notification.body)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    Self.openSourceApp(notification)
                    vm.dismissActiveNotification()
                }
                if let token = notification.actionToken, !notification.actionTitles.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(notification.actionTitles.enumerated()), id: \.offset) {
                            index, title in
                            Button(title) {
                                vm.onNotificationAction?(token, index)
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 12)
                            .background(.white.opacity(index == 0 ? 0.22 : 0.10),
                                        in: Capsule())
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func appIcon(for notification: NotchNotification) -> some View {
        RemoteAvatarView(iconURL: notification.iconURL,
                         iconEmoji: notification.iconEmoji,
                         iconColor: notification.iconColor,
                         fallbackPath: Self.appPath(bundleID: notification.bundleID,
                                                    named: notification.appName))
            .frame(width: 32, height: 32)
    }

    /// Estático e internal: a linha do histórico reusa o mesmo clique. O corpo
    /// já só usava `Self.` e NSWorkspace, então a promoção não muda nada.
    static func openSourceApp(_ notification: NotchNotification) {
        // AirDrop revela a pasta de destino — caminho fixo do sistema, nunca uma
        // string vinda de fora (o openURL abaixo aceita payload de webhook)
        if notification.revealsDownloads {
            if let downloads = FileManager.default.urls(
                for: .downloadsDirectory, in: .userDomainMask).first {
                NSWorkspace.shared.activateFileViewerSelecting([downloads])
            }
            return
        }
        // só http/https: file:// aqui deixaria um webhook abrir qualquer app
        if let raw = notification.openURL, let url = URL(string: raw),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
            return
        }
        if notification.supacodeWorktree != nil || notification.supacodeTab != nil {
            Self.focusSupacode(
                worktree: notification.supacodeWorktree, tab: notification.supacodeTab)
            return
        }
        if let bundleID = notification.bundleID,
           let app = NSRunningApplication.runningApplications(
               withBundleIdentifier: bundleID).first {
            app.activate()
            return
        }
        Self.runningApp(named: notification.appName)?.activate()
    }

    /// Foca a sessão no Supacode via CLI do app e traz o app pra frente.
    private static func focusSupacode(worktree: String?, tab: String?) {
        let cli = "/Applications/supacode.app/Contents/Resources/bin/supacode"
        DispatchQueue.global(qos: .userInitiated).async {
            func run(_ args: [String]) {
                guard FileManager.default.fileExists(atPath: cli) else { return }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cli)
                process.arguments = args
                try? process.run()
                process.waitUntilExit()
            }
            if let worktree { run(["worktree", "focus", "-w", worktree]) }
            if let worktree, let tab { run(["tab", "focus", "-w", worktree, "-t", tab]) }
            DispatchQueue.main.async {
                NSRunningApplication.runningApplications(
                    withBundleIdentifier: "app.supabit.supacode"
                ).first?.activate()
            }
        }
    }

    private static func runningApp(named name: String?) -> NSRunningApplication? {
        guard let name, !name.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// Caminho do app pro ícone: bundle ID exato, senão app rodando pelo nome,
    /// senão instalado em /Applications.
    private static func appPath(bundleID: String?, named name: String?) -> String? {
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.path
        }
        if let path = runningApp(named: name)?.bundleURL?.path { return path }
        guard let name, !name.isEmpty else { return nil }
        let installed = "/Applications/\(name).app"
        return FileManager.default.fileExists(atPath: installed) ? installed : nil
    }

    // MARK: - AirPods

    /// Card transitório mostrado quando os AirPods conectam ou ficam com bateria
    /// baixa: nome + bateria L / R / estojo.
    @ViewBuilder
    private var airpodsConnectCard: some View {
        if let ap = vm.airpods {
            HStack(spacing: 12) {
                Image(systemName: "airpodspro")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ap.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 14) {
                        airpodsPip("L", ap.left)
                        airpodsPip("R", ap.right)
                        airpodsPip("Estojo", ap.case_)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Um componente (rótulo + %); vermelho quando ≤10%, "—" quando não reportou.
    private func airpodsPip(_ label: String, _ level: Int?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
            Text(level.map { "\($0)%" } ?? "—")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle((level ?? 100) <= 10 ? .red : .white)
        }
    }

    // MARK: - Atualização disponível

    /// Nome com sufixo `NotchCard` de propósito: `updateCard` já é a flag de
    /// exibição no view model, e as duas coisas convivem no mesmo escopo aqui.
    @ViewBuilder
    private var updateNotchCard: some View {
        if let state = vm.update {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    switch state {
                    case .available(let release):
                        Text("Knobler \(release.version) disponível")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(release.notes.isEmpty
                             ? "Nova versão pronta pra instalar." : release.notes)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    case .installing:
                        Text("Atualizando…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("O Knobler reinicia sozinho ao terminar.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    case .failed(let message):
                        Text("Falha ao atualizar")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if case .installing = state {
                    // ActivityRingView e não ProgressView: o indicador do AppKit
                    // precisa de NSView real e vira o ícone de "proibido" no
                    // harness de snapshot (ver CLAUDE.md).
                    ActivityRingView(progress: nil)
                        .frame(width: 16, height: 16)
                } else {
                    HStack(spacing: 6) {
                        Button("Depois") { vm.onUpdateSkip?() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        Button(vm.updateCanInstall ? "Atualizar" : "Ver release") {
                            vm.onUpdateInstall?()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Anel de progresso de atividade

/// Anel estilo timer do Dynamic Island: determinado preenche; sem progresso,
/// arco girando (indeterminado).
struct ActivityRingView: View {
    var progress: Double?

    var body: some View {
        if let progress {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.03, progress))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: progress)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.2) / 1.2
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(phase * 360))
            }
        }
    }
}

// MARK: - Visualizador de áudio

/// Visualizador estilo Dynamic Island do iPhone: 5 barras tingidas pela capa,
/// dirigidas pelas bandas de frequência do áudio REAL do Spotify (via
/// SystemAudioLevels). Sem tap (permissão negada / tocando sem captura),
/// cai numa animação sintética de senoides sobrepostas.
struct AudioBarsView: View {
    var playing: Bool
    @ObservedObject var levels: SystemAudioLevels
    var tint: Color = .white

    private var bands: [Float]? { levels.bands }

    private static let phases: [Double] = [0.0, 1.9, 0.7, 2.6, 1.3]
    private static let speeds: [Double] = [7.2, 8.8, 6.1, 9.5, 7.9]
    // pausado: pontinhos uniformes (altura mínima = largura da barra), como o island
    private static let idleProfile: [CGFloat] = [0, 0, 0, 0, 0]

    var body: some View {
        if playing, let bands {
            // áudio de verdade: as alturas seguem as bandas publicadas a ~30Hz;
            // a animação interpola entre publicações
            bars(levels: bands.map { CGFloat($0) })
                .animation(.linear(duration: 1.0 / 20.0), value: bands)
        } else if playing {
            // 30fps bastam pro fallback — 60 dobra o custo sem ganho visível
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                bars(levels: Self.syntheticLevels(
                    at: context.date.timeIntervalSinceReferenceDate))
            }
        } else {
            bars(levels: Self.idleProfile)
        }
    }

    private func bars(levels: [CGFloat]) -> some View {
        GeometryReader { geo in
            let count = levels.count
            // barras finas com vão generoso, como as da Apple
            let barWidth = geo.size.width / (CGFloat(count) * 2.1)
            HStack(alignment: .center, spacing: barWidth * 1.1) {
                ForEach(0..<count, id: \.self) { index in
                    // altura FIXA + scaleEffect: anima por transform (GPU),
                    // sem relayout da janela a cada frame — era o maior custo
                    // de CPU do app com música tocando
                    Capsule()
                        .fill(tint)
                        .frame(width: barWidth, height: geo.size.height)
                        .scaleEffect(
                            x: 1,
                            y: max(barWidth / geo.size.height, min(1, levels[index])),
                            anchor: .center
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // fallback sintético: duas senoides não-harmônicas por barra
    private static func syntheticLevels(at time: TimeInterval) -> [CGFloat] {
        (0..<phases.count).map { index in
            let fast = sin(time * speeds[index] + phases[index])
            let slow = sin(time * speeds[index] * 0.37 + phases[index] * 2)
            let mixed = 0.6 * fast + 0.4 * slow
            return 0.25 + 0.75 * CGFloat((mixed + 1) / 2)
        }
    }
}

// MARK: - Avatar remoto do card

/// Avatar do card: tenta o avatar remoto (com guardas) quando há iconURL e o
/// toggle está on; senão o ícone do app; senão o sino.
private struct RemoteAvatarView: View {
    let iconURL: String?
    let iconEmoji: String?
    var iconColor: NSColor? = nil
    let fallbackPath: String?
    @StateObject private var loader = RemoteAvatarLoader()

    var body: some View {
        Group {
            if let iconColor {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: iconColor))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1))
            } else if let e = iconEmoji, !e.isEmpty {
                Text(e).font(.system(size: 22))
            } else if let img = loader.image {
                Image(nsImage: img).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else if let path = fallbackPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
            } else {
                Image(systemName: "bell.badge.fill").resizable().scaledToFit()
                    .padding(6).foregroundStyle(.white.opacity(0.6))
            }
        }
        .onAppear { reload() }
        .onChange(of: iconURL) { _, _ in reload() }   // notificações consecutivas com avatares diferentes
    }

    private func reload() {
        guard iconEmoji == nil else { return }   // emoji fixo: renderiza local, não baixa nada
        if AppSettings.shared.loadRemoteImages { loader.load(iconURL) }
    }
}

/// Congela a ordem das seções na abertura do card e publica a altura pra quem
/// vive fora do SwiftUI (o monitor de scroll). Mesmo motivo do `CarimboDeEventos`
/// pra ser um modificador à parte: mais `.onChange` inline estoura o
/// type-checker do `interactiveNotch`.
private struct AberturaDoCard: ViewModifier {
    let vm: NotchViewModel
    let altura: CGFloat
    let hasMusic: Bool
    let hasShelf: Bool
    let hasHistory: Bool
    let hasMensagens: Bool
    let hasNota: Bool
    let hasLink: Bool

    func body(content: Content) -> some View {
        content
            // já aberto quando a view nasce (harness de snapshot, janela
            // recriada por troca de monitor): sem isto a ordem ficaria vazia.
            // Lista já montada não é recalculada — é como o harness captura
            // cenários que não dá pra provocar offscreen.
            .onAppear { if vm.expanded, vm.secoes.isEmpty { recalcular() } }
            .onChange(of: vm.expanded) { _, aberto in
                if aberto { recalcular() }
            }
            // ligar/desligar a nota com o card JÁ aberto não passa pelo
            // `expanded`: sem isto a seção nova nunca entraria na ordem congelada
            .onChange(of: hasNota) { _, _ in if vm.expanded { recalcular() } }
            // idem pra Mensagens: a PRIMEIRA conversa nasce com o card já
            // aberto (hover + mensagem LAN chegando), e sem isto `.mensagens`
            // não estaria na ordem congelada quando o clique no card pede foco
            .onChange(of: hasMensagens) { _, _ in if vm.expanded { recalcular() } }
            // e pro link: arrastar uma URL abre o card e a seção nasce junto
            .onChange(of: hasLink) { _, _ in if vm.expanded { recalcular() } }
            // a altura inicial também precisa sair daqui: quem vive fora do
            // SwiftUI (o monitor de scroll) leria 0 até o card mudar de tamanho
            .onAppear { vm.publicarAltura(altura) }
            .onChange(of: altura) { _, novo in vm.publicarAltura(novo) }
    }

    private func recalcular() {
        vm.recalcularSecoes(
            vm.estadoDasSecoes(hasMusic: hasMusic,
                               hasShelf: hasShelf,
                               hasHistory: hasHistory,
                               hasMensagens: hasMensagens,
                               hasNota: hasNota,
                               hasLink: hasLink),
            travadaNaNota: vm.typingNote)
    }
}

/// Carimba os eventos de transição das seções que nascem fora do VM (música,
/// shelf, histórico, nota). Vive num `ViewModifier` próprio — e recebe valores
/// já extraídos, não os stores — porque o `body` do notch interativo já estoura
/// o type-checker do Swift quando ganha mais um punhado de `.onChange`.
///
/// Nada aqui carimba tique: da música só troca de faixa e play/pause entram (a
/// posição avança sozinha e promoveria a música pra sempre), e da nota só o
/// vazio → não-vazio (cada tecla depois disso não recarimba).
private struct CarimboDeEventos: ViewModifier {
    let vm: NotchViewModel
    let faixa: String?
    let tocando: Bool?
    let itensShelf: Int
    let itensHistorico: Int
    let notaVazia: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: faixa) { _, _ in vm.marcarEvento(.musica) }
            .onChange(of: tocando) { _, _ in vm.marcarEvento(.musica) }
            .onChange(of: itensShelf) { _, _ in vm.marcarEvento(.shelf) }
            .onChange(of: itensHistorico) { _, _ in vm.marcarEvento(.historico) }
            .onChange(of: notaVazia) { _, vazio in
                if !vazio { vm.marcarEvento(.nota) }
            }
    }
}
