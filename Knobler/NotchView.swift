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
    @ObservedObject private var mirror = MirrorController.shared
    @ObservedObject private var monitors = Monitores.shared
    @ObservedObject private var agentes = AgentesUso.shared
    @ObservedObject private var annotation = AnnotationController.shared
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
    /// Diagnóstico passivo: registra desvios sem reconstruir a árvore.
    @StateObject private var vigia = VigiaDoCorte()
    /// Altura que o card do Ask reportou no último layout. 0 = ainda não mediu.
    @State private var askHeight: CGFloat = 0
    /// Sessão da câmera já rodando — até lá o espelho mostra o spinner.
    @State private var espelhoPronto = false
    /// Barra de endereço da seção Link enquanto nenhuma página está aberta.
    @State private var linkDigitado = ""
    @FocusState private var linkFocado: Bool

    private var presentation: NotchPresentation {
        var layout = NotchPresentation.Layout()
        layout.notch = vm.notchSize
        layout.realNotch = vm.hasRealNotch
        layout.available = vm.availableSize
        layout.closedContent = closedHasContent
        layout.sectionHeight = vm.focus.map {
            NotchMetrics.alturaDaSecao($0, preview: shelf.preview != nil,
                pilhaAberta: shelf.pilhaAberta != nil, espelhoLigado: vm.mirrorOn,
                linkAberto: linkAberto, eventoProximo: vm.calendarAviso != nil)
        } ?? 118
        if vm.focus == .agenda {
            layout.sectionHeight = NotchMetrics.alturaAgenda(editando: vm.agendaRascunho != nil,
                disponivel: vm.availableSize.height, topo: vm.hasRealNotch ? vm.notchSize.height : 4)
        }
        if vm.focus == .lembretesApple {
            layout.sectionHeight = min(330, max(0, vm.availableSize.height - vm.notchSize.height - 84))
        }
        if vm.focus == .monitores {
            let display = monitors.displays.first { $0.id == vm.monitoresSelecionado }
                ?? monitors.displays.first { $0.id == vm.displayID } ?? monitors.displays.first
            layout.sectionHeight = 172 + (vm.monitoresContraste ? 54 : 0)
                + (display?.software == true ? 24 : 0)
                + (display?.error != nil ? 42 : 0)
                + (display?.preferences.mode == .hardware && display?.hardwareBrightness == false ? 32 : 0)
        }
        layout.sectionWidth = NotchMetrics.larguraDoCard(vm.focus, padrao: 430, linkAberto: linkAberto)
        layout.notificationActions = vm.activeNotification?.actionTitles.isEmpty == false
        layout.notificationExtra = Self.alturaExtra(vm.activeNotification, aberto: vm.notificationHeld)
        layout.mediaHeight = vm.incoming?.mediaHeight ?? 0
        layout.questionSize = questionSize
        layout.contentID = "\(askStore.state.active?.id ?? "")/\(askStore.state.page)/\(agentRequestStore.state.active?.id ?? "")"
        return NotchPresentation(content: vm.contentState(question: askStore.state.active != nil
                                || agentRequestStore.state.active != nil), layout: layout)
    }

    private var mode: NotchMode { presentation.mode }
    private var currentSize: CGSize { presentation.size }
    private var topInset: CGFloat { presentation.topInset }
    private var noteVisible: Bool { note.hosted(by: vm.displayID) }
    private var linkAberto: Bool { linkPreview.hosted(by: vm.displayID) }

    private func publishPresentation(_ value: NotchPresentation) {
        vm.publishPresentation(value)
        if !value.keyboard || value.focus != .nota {
            noteFocused = false
            if noteVisible { note.editing = false }
        }
        if !value.keyboard || value.focus != .link { linkFocado = false }
        onKeyboardEligibilityChanged?(value.keyboard)
    }

    var body: some View {
        VStack(spacing: 0) {
            interactiveNotch
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // a raiz é o "onde a moldura deveria estar" do invariante da lacuna de
        // topo — ver Knobler/CorteDoKnob.swift
        .coordinateSpace(name: CorteDoKnob.espacoRaiz)
        .onReceive(monitors.$displays) { displays in
            vm.monitoresDisponiveis = !displays.isEmpty
        }
    }

    /// O retrato do instante da violação. Montado SÓ quando ela acontece.
    private func contextoDoCorte(_ moldura: CGRect) -> ContextoDoCorte {
        let ultimo = vm.eventos.max { $0.value < $1.value }
        return ContextoDoCorte(
            mode: "\(mode)",
            foco: vm.focus?.rawValue,
            alturaEsperada: Double(currentSize.height),
            ultimoEvento: ultimo.map {
                String(format: "%@ há %.1f s", $0.key.rawValue,
                       Date().timeIntervalSince($0.value))
            },
            animando: abs(moldura.height - currentSize.height) > CorteDoKnob.toleranciaPt,
            displayID: vm.displayID ?? 0,
            notchReal: vm.hasRealNotch)
    }

    private var hasMusic: Bool { media.state != nil }

    /// Com música na sessão, capa e barras ficam — tocando ou pausada, como na
    /// ilha do iPhone. Pausada, as barras caem pros pontinhos e a capa escurece.
    private var wingsVisible: Bool { hasMusic }

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
        NotchShell(presentation: presentation, reduceMotion: reduceMotion) {
            switch mode {
            case .closed:
                if closedHasContent {
                    closedWings
                        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
                }
            case .hud:
                hudPill
                    .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
            case .dictation:
                dictationPill
                    .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
            case .music:
                expandedContent
                    // largura fixa: o texto não pode refluir enquanto a forma anima
                    .frame(width: currentSize.width - 44)
                    .padding(.top, topInset + 8)
                    .padding(.bottom, 14)
                    // o conteúdo cresce junto com a moldura, ancorado no topo
                    .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(
                        with: .scale(scale: 0.94, anchor: .top)))
            case .pomodoro:
                pomodoroPill
                    .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
            case .notification:
                notificationCard
                    .frame(width: currentSize.width - 48,
                           height: currentSize.height - topInset, alignment: .top)
                    .padding(.top, topInset)
                    // notificação desce do notch, como no iPhone
                    .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .move(edge: .top)))
            case .message:
                if let incoming = vm.incoming {
                    IncomingMessageView(vm: vm, incoming: incoming)
                        .frame(width: 360 - 40)
                        .padding(.top, topInset)
                        .padding(.bottom, 12)
                        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .move(edge: .top)))
                }
            case .question:
                questionCard
                    // pergunta desce do notch, como as notificações
                    .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .move(edge: .top)))
            case .airpodsIsland:
                if let ap = vm.airpods {
                    AirPodsIslandView(battery: ap)
                        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
                }
            case .airpods:
                if let ap = vm.airpods {
                    AirPodsCardView(battery: ap)
                        .frame(width: currentSize.width - 40)
                        .padding(.top, topInset + 6)
                        .padding(.bottom, 12)
                        // desce do notch, como as notificações
                        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .move(edge: .top)))
                }
            case .update:
                updateNotchCard
                    .frame(width: 380 - 40)
                    .padding(.top, topInset)
                    .padding(.bottom, 12)
                    // desce do notch, como as notificações
                    .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .move(edge: .top)))
            }
        }
        // mede a lacuna de topo da moldura desenhada; não desenha nada
        .background(SensorDeCorte(vigia: vigia, contexto: contextoDoCorte))
        // folga invisível de hover ao redor do card aberto: jitter na borda
        // não fecha; e o hit-test cobre o retângulo todo, não só o desenhado.
        .padding(.horizontal, presentation.hoverPadding)
        .padding(.bottom, presentation.hoverPadding)
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
            // card de AirPods segurado solta em qualquer saída, mesmo se outro
            // modo (HUD, notificação) estiver por cima nessa hora
            if !inside, vm.airpodsHeld { vm.holdAirPods(false) }
            // idem pra notificação: se uma mensagem ou pergunta cobriu o card
            // durante o hover, a saída não passa pelo ramo abaixo e o card
            // voltaria aberto e sem timer
            if !inside, vm.notificationHeld, mode != .notification { vm.holdNotification(false) }
            if mode == .notification {
                vm.holdNotification(inside)
            } else if mode == .message {
                vm.holdIncoming(inside)
            } else if mode == .airpods || mode == .airpodsIsland {
                // entrada promove sem acordar a música; saída também fecha a
                // música pendente, senão ela assume quando os AirPods somem
                if inside { vm.holdAirPods(true) } else { vm.setHover(false) }
            } else if !inside || mode != .question {
                // O card de pergunta usa hover para preview e clique; não deixe
                // esse movimento alterar o estado de expansão da música.
                vm.setHover(inside)
            }
        }
        .onAppear {
            agentRequestExpanded = agentRequestInitiallyExpanded
            publishPresentation(presentation)
        }
        .onChange(of: presentation) { _, value in publishPresentation(value) }
        .onChange(of: agentRequestStore.state.active?.id) { _, _ in agentRequestExpanded = false }
        .onChange(of: vm.focus) { _, _ in ligarEspelhoSeEmFoco() }
        .onChange(of: vm.expanded) { _, _ in ligarEspelhoSeEmFoco() }
        // digitar segura as notificações; parar de digitar solta a fila
        .onChange(of: note.editing) { _, editing in
            if !editing { vm.resumePendingNotifications() }
        }
        .modifier(CarimboDeEventos(vm: vm,
                                   faixa: media.state?.title,
                                   tocando: media.state?.isPlaying,
                                   itensShelf: shelf.arquivos.count,
                                   itensHistorico: history.items.count,
                                   notaVazia: note.text.isEmpty))
        .onChange(of: sectionInputs, initial: true) { _, inputs in vm.updateSections(inputs) }

    }

    private var sectionInputs: NotchSectionInputs {
        NotchSectionInputs(music: hasMusic, shelf: !shelf.entradas.isEmpty,
            history: !history.items.isEmpty, messages: !messages.threads.isEmpty,
            note: noteVisible, link: linkAberto, annotation: annotation.isActive || annotation.temTinta,
            agentes: !agentes.sessoes.isEmpty || !agentes.uso.isEmpty)
    }

    private var questionSize: CGSize {
        if let request = agentRequestStore.state.active, askStore.state.active == nil {
            // expandido troca as 2 linhas do resumo (~34) pelo bloco rolável
            // com resumo + detalhes (176 + padding)
            let expandable = request.details?.isEmpty == false || request.summary.count > 110
            let extra: CGFloat = agentRequestExpanded && expandable ? 156 : 0
            return CGSize(width: 460, height: 116 + extra)
        }
        guard let ask = askStore.state.active else {
            return CGSize(width: 460, height: 120)
        }
        let question = ask.questions[min(askStore.state.page, ask.questions.count - 1)]
        let hasPreview = question.options.contains { $0.preview != nil }
        // Estimativa só do primeiro frame, antes do card se medir:
        // título+chip (46) + opções (48 cada) + rodapé com campo de texto (44)
        var height = 46 + CGFloat(question.options.count) * 48 + 44
        if question.multiSelect { height += 34 }  // botão Confirmar
        if hasPreview { height = max(height, 200) }
        // A altura real vem do próprio card (AlturaDoAskKey); os 18 são os
        // paddings que o `questionCard` acrescenta em volta dele.
        if askHeight > 0 { height = 6 + askHeight + 12 }
        return CGSize(width: hasPreview ? 540 : 460, height: height)
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
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Self.hudLabel(hud))
                            .font(hud.displayName == nil ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                        if let name = hud.displayName {
                            Text(name).font(.system(size: 8)).lineLimit(1).frame(maxWidth: 95, alignment: .leading)
                        }
                    }
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
                // nos últimos 5 min o evento vale mais que o timer: a largura da
                // pílula é fixa, então um substitui o outro em vez de somar
                if let aviso = vm.calendarAviso, aviso.urgente {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tint)
                        Text(aviso.quando)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.trailing, vm.hasRealNotch ? 14 : 16)
                } else {
                    Text(Self.mmss(p.remaining))
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.trailing, vm.hasRealNotch ? 14 : 16)
                }
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
            if let aviso = vm.calendarAviso {
                // o título é contexto, o tempo é o dado: pesos diferentes pra o
                // olho pegar "em 4 min" sem ler a frase inteira
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                    Text(aviso.titulo)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(aviso.quando)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .layoutPriority(1)   // o tempo nunca é o que trunca
                    Spacer(minLength: 0)
                }
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
                .onPreferenceChange(AlturaDoAskKey.self) { askHeight = $0 }
                .onDisappear { askHeight = 0 }
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
        if let control = hud.displayControl { return control }
        if hud.displayName != nil {
            switch hud.kind {
            case .brightness: return "Brilho"
            case .volume: return hud.muted ? "Silenciado" : "Volume"
            case .battery: break
            }
        }
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
                    .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
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
                        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
                }
                if vm.micInUse {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
                }
                if let activity = vm.activity {
                    ActivityRingView(progress: activity.progress)
                        .frame(width: 17, height: 17)
                        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
                } else if wingsVisible {
                    audioBars
                        .frame(width: IlhaVisualizador.area.width,
                               height: IlhaVisualizador.area.height)
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
            capa: media.artwork,
            luminancia: media.artworkLuminancia
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
        .frame(width: IlhaVisualizador.capaLado, height: IlhaVisualizador.capaLado)
        .clipShape(RoundedRectangle(cornerRadius: IlhaVisualizador.capaRaio,
                                    style: .continuous))
        // pausado a capa escurece, como no iPhone
        .opacity(media.state?.isPlaying == true
                 ? 1 : IlhaVisualizador.capaOpacidadePausada)
        .animation(.easeInOut(duration: IlhaVisualizador.capaDuracaoDim),
                   value: media.state?.isPlaying)
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
            .frame(height: NotchMetrics.noteEditorHeight)
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
            // zona de escrita um tom acima do fundo do card: sem isso o campo
            // vazio é indistinguível da moldura preta
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.07)))
            // adota ANTES de pedir o foco: a seção fixada chega aqui com a nota
            // desligada, e sem dono o texto digitado não conta pro badge do
            // notch fechado nem sobrevive à guarda de hover.
            .onAppear {
                note.adotar(vm.displayID)
                noteFocused = true
            }
            .onChange(of: noteFocused) { _, focused in
                if noteVisible { note.editing = focused && presentation.keyboard && presentation.focus == .nota }
            }
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
                // A saída antiga pode terminar depois de uma reabertura.
                guard mode != .music || vm.focus != .nota || !vm.expanded else { return }
                noteFocused = false
                if noteVisible { note.editing = false }
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
                case .link: if linkPreview.hosted(by: vm.displayID) { LinkPreviewView(preview: linkPreview) }
                           else { linkVazio }
                case .atividade:
                    if let a = vm.activity { activityRow(a) }
                    else { vazio("arrow.triangle.2.circlepath", "Nenhuma atividade") }
                case .pomodoro:
                    // ponytail: texto, não botão. `Pomodoro.startNext()` só sai
                    // de `.waiting`; não existe "iniciar do zero" no VM hoje.
                    // Vira ação quando alguém pedir.
                    if let p = vm.pomodoro { pomodoroSection(p) }
                    else { vazio("timer", "Pomodoro parado") }
                case .anotacao: AnnotationDeckView(annotation: annotation)
                case .agenda: AgendaView(vm: vm)
                case .lembretesApple: vm.onLembretesView?()
                case .monitores: MonitoresView(vm: vm)
                case .agentes: AgentesView(agentes: agentes)
                case .musica, .none: musicSection
                }
            }
            .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
            Spacer(minLength: 0)
            sectionStrip
        }
    }

    /// Rodapé do card: as seções que não estão em foco, cada uma com um sinal
    /// vivo mínimo. Você perde o detalhe, não o glance.
    private var sectionStrip: some View {
        HStack(spacing: 10) {
            ForEach(vm.secoes, id: \.self) { s in
                Button {
                    vm.focar(s)
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
        .frame(height: NotchMetrics.sectionStripHeight)
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
            // o badge conta VAGAS, que é o que casa com a capacidade da prateleira
            contagem(shelf.entradas.count)
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
        case .anotacao:
            if annotation.isActive || annotation.temTinta {
                Circle().fill(.white.opacity(0.8))
                    .frame(width: 3, height: 3)
                    .offset(x: 6, y: -6)
            }
        // agentes: sessão esperando você acende o ponto, como a anotação.
        case .agentes:
            if agentes.sessoes.first?.state == .waiting {
                Circle().fill(.orange).frame(width: 3, height: 3).offset(x: 6, y: -6)
            }
        case .espelho, .mensagens, .agenda, .lembretesApple, .monitores:
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
        MirrorPreviewView(onReady: { espelhoPronto = true })
            .frame(height: 180)
            .overlay {
                // abrir o dispositivo pode falhar (sem webcam, USB fora, câmera
                // tomada por outro app) — e aí o "ligando…" nunca sairia
                if mirror.falhou {
                    ZStack {
                        Color.black
                        VStack(spacing: 8) {
                            Image(systemName: "video.slash")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.4))
                            Text("Câmera indisponível")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .transition(.opacity)
                } else if !espelhoPronto {
                    ZStack {
                        Color.black
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Ligando a câmera…")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: espelhoPronto)
            .animation(.easeOut(duration: 0.2), value: mirror.falhou)
            .onDisappear { espelhoPronto = false }
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

    /// Sem link aberto a seção vira barra de endereço: colar (⌘V) e Enter.
    /// Arrastar do navegador continua valendo — isto é a via sem mouse.
    private var linkVazio: some View {
        VStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.4))
            TextField("Cole um link e tecle Enter", text: $linkDigitado)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.white)
                .focused($linkFocado)
                .onSubmit { abrirLinkDigitado() }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // o app não tem menu bar: sem este monitor o ⌘V não chega ao campo
        .onAppear {
            linkPreview.instalarAtalhos()
            linkFocado = true
        }
        .onDisappear {
            linkPreview.removerAtalhos()
            linkDigitado = ""
        }
    }

    /// Aceita `exemplo.com` além da URL completa — quem cola do navegador traz
    /// o esquema, quem digita não.
    private func abrirLinkDigitado() {
        let texto = linkDigitado.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        let comEsquema = texto.contains("://") ? texto : "https://" + texto
        guard let url = URL(string: comEsquema) else { return }
        linkDigitado = ""
        linkPreview.abrir(url, on: vm.displayID)
    }

    /// Abrir a aba do espelho já liga a câmera — sem exigir o clique. Só chega
    /// aqui com a seção fixada: sem fixar, ela nem aparece na faixa desligada.
    private func ligarEspelhoSeEmFoco() {
        guard vm.expanded, vm.focus == .espelho, !vm.mirrorOn else { return }
        MirrorController.activate(on: vm)
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
                        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
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

    // trio de transporte CENTRADO no card; o shuffle fica sobreposto à
    // esquerda pra não empurrar o play pro lado direito (era um HStack de 4
    // com Spacers iguais: o play caía fora do centro do card)
    private func controls(_ state: MediaController.PlaybackState) -> some View {
        HStack(spacing: 28) {
            Button { media.previousTrack() } label: {
                Image(systemName: "backward.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            Button { media.playPause() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 30)
            }
            Button { media.nextTrack() } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            Button { media.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.body)
                    .foregroundStyle(state.shuffling ? .white : .white.opacity(0.45))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            // fonte sem shuffle (navegador) → botão apagado, layout estável
            .disabled(!state.shuffleAvailable)
            .opacity(state.shuffleAvailable ? 1 : 0.2)
        }
    }

    // MARK: - Notificação

    @ViewBuilder
    private var notificationCard: some View {
        if let notification = vm.activeNotification {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    appIcon(for: notification)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(notification.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(vm.notificationHeld ? nil : 1)
                            Spacer(minLength: 0)
                            Text(NotificationRules.haQuanto(notification.date, agora: Date()))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                                .fixedSize()
                        }
                        if let subtitle = notification.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(vm.notificationHeld ? nil : 1)
                        }
                        if !notification.body.isEmpty {
                            Text(notification.body)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(vm.notificationHeld ? nil : 2)
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

    /// Quanto o card cresce além do compacto (título 1 linha + corpo 2).
    /// ponytail: estimativa por métrica de fonte, não medida do layout real;
    /// errar por uma linha só sobra ou corta um pouco. Trocar por medição via
    /// PreferenceKey se incomodar.
    static func alturaExtra(_ n: NotchNotification?, aberto: Bool) -> CGFloat {
        guard let n else { return 0 }
        guard aberto || n.subtitle?.isEmpty == false else { return 0 }
        // card 380 − padding 48 − ícone 32 − espaço 12; o título divide a linha
        // com a hora
        func altura(_ texto: String, _ fonte: NSFont, max linhas: Int?,
                    largura: CGFloat = 288) -> CGFloat {
            guard !texto.isEmpty else { return 0 }
            func medida(_ s: String) -> CGFloat {
                (s as NSString).boundingRect(
                    with: CGSize(width: largura, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin], attributes: [.font: fonte]).height
            }
            let linha = medida("x")
            // o teto do card é ~15 linhas: medir além disso só custa tempo
            let total = medida(String(texto.prefix(2_000)))
            let n = Swift.max(1, Int((total / linha).rounded(.up)))
            return CGFloat(linhas.map { Swift.min(n, $0) } ?? n) * linha
        }
        let tituloF = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize,
                                        weight: .semibold)
        let corpoF = NSFont.preferredFont(forTextStyle: .caption1)
        let compacto = altura("x", tituloF, max: 1) + altura("x\nx", corpoF, max: 2)
        let agora = altura(n.title, tituloF, max: aberto ? nil : 1, largura: 288 - 45)
            + altura(n.subtitle ?? "", corpoF, max: aberto ? nil : 1)
            + altura(n.body, corpoF, max: aberto ? nil : 2)
        // o Text do SwiftUI entrelinha um pouco mais que a métrica do AppKit e a
        // diferença acumula por linha: aberto ganha uma linha de folga, senão a
        // última encosta na borda
        let folga = aberto ? altura("x", corpoF, max: 1) : 0
        return Swift.max(0, agora - compacto + folga)
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
        if let app = Self.runningApp(named: notification.appName) {
            app.activate()
            return
        }
        // app instalado e fechado: abre, em vez de o clique não fazer nada.
        // Só pra banner do sistema — o nome de um card da API local vem de fora
        // e não pode lançar app — e só em pastas de apps.
        if notification.doBanner,
           let path = Self.appPath(bundleID: notification.bundleID, named: notification.appName) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                               configuration: NSWorkspace.OpenConfiguration())
        }
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

    /// Compara limpo dos dois lados: o `localizedName` do WhatsApp também traz
    /// U+200E, e o nome lido do banner já vem limpo.
    private static func runningApp(named name: String?) -> NSRunningApplication? {
        guard let name else { return nil }
        let alvo = NotificationRules.limpo(name)
        guard !alvo.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            NotificationRules.limpo($0.localizedName ?? "")
                .localizedCaseInsensitiveCompare(alvo) == .orderedSame
        }
    }

    /// Caminho do app pro ícone: bundle ID exato, senão app rodando pelo nome,
    /// senão instalado em /Applications ou ~/Applications (web apps do Safari,
    /// PWAs do Chrome).
    static func appPath(bundleID: String?, named name: String?) -> String? {
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.path
        }
        if let path = runningApp(named: name)?.bundleURL?.path { return path }
        guard let name else { return nil }
        let nome = NotificationRules.limpo(name)
        // "/" ou ".." escapariam da pasta de apps
        guard !nome.isEmpty, !nome.contains("/") else { return nil }
        let pastas = ["/Applications", NSHomeDirectory() + "/Applications"]
        return pastas.map { "\($0)/\(nome).app" }
            .first { FileManager.default.fileExists(atPath: $0) }
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
    var color: Color = .orange
    var lineWidth: CGFloat = 2.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let progress {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.03, progress))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // em 0 o lineCap redondo deixaria um ponto no topo
                    .opacity(progress > 0 ? 1 : 0)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9), value: progress)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.2) / 1.2
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(phase * 360))
            }
        }
    }
}

// MARK: - Visualizador de áudio

/// Indicador de reprodução igual ao da Dynamic Island: seis barras que são o
/// RECORTE por onde a capa desfocada aparece — no iPhone elas não são pintadas
/// com uma cor da capa, e é isso que dá matiz diferente entre vizinhas.
/// Alimentado pelas bandas do áudio real; sem tap disponível, toca a animação
/// de reserva que a Apple usa no app Música. Medidas em `IlhaVisualizador`.
struct AudioBarsView: View {
    var playing: Bool
    @ObservedObject var levels: SystemAudioLevels
    var capa: NSImage?
    var luminancia: Double?

    private var bands: [Float]? { levels.bands }
    private static let area = IlhaVisualizador.area
    private static let paradas = [CGFloat](
        repeating: 0, count: IlhaVisualizador.barras)

    var body: some View {
        pintura
            .frame(width: Self.area.width, height: Self.area.height)
    }

    @ViewBuilder private var pintura: some View {
        if !playing {
            // pausado: seis pontinhos parados, como a ilha sem análise
            capaTratada.mask(barras(Self.paradas))
        } else if let bands {
            // Anima `frame(width:height:)`, não `scaleEffect`: escala
            // deformaria as pontas em cápsula, e o piso de altura (silêncio
            // vira ponto redondo) some sob escala uniforme. É relayout por
            // quadro — custo ainda não medido.
            capaTratada.mask(barras(bands.map { CGFloat($0) }))
                .animation(IlhaVisualizador.mola, value: bands)
        } else {
            // capaTratada fica fora do closure: só a máscara muda a 30fps, a
            // capa borrada/saturada é montada uma vez, não 30×/s.
            capaTratada.mask(
                // 30fps bastam pra reserva — 60 dobra o custo sem ganho visível
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { contexto in
                    barras(IlhaVisualizador.reserva(
                        em: contexto.date.timeIntervalSinceReferenceDate))
                }
            )
        }
    }

    private var capaTratada: some View {
        ZStack {
            if let capa {
                Image(nsImage: capa)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: IlhaVisualizador.desfoqueDaCapa)
                    .saturation(IlhaVisualizador.saturacaoDaCapa)
                correcao
            } else {
                Color(nsColor: IlhaVisualizador.cinzaSemCapa)
            }
        }
        .frame(width: Self.area.width, height: Self.area.height)
        .clipped()
        .animation(.easeInOut(duration: IlhaVisualizador.duracaoSemCapa),
                   value: capa == nil)
    }

    /// Capa escura demais some no preto do notch; clara demais perde contorno.
    /// ponytail: a Apple ainda soma saturação junto do clareamento — teto
    /// conhecido, capa quase preta fica cinza em vez de colorida. Duas camadas
    /// resolvem o caso que importa.
    @ViewBuilder private var correcao: some View {
        let ajuste = IlhaVisualizador.correcaoDeLuminancia(luminancia ?? 0.5)
        if ajuste.clarear > 0 { Color.white.opacity(ajuste.clarear) }
        if ajuste.escurecer > 0 { Color.black.opacity(ajuste.escurecer) }
    }

    /// Cada barra fica no centro que `IlhaVisualizador.centro(_:largura:)`
    /// calcula (o `ilhacheck` prova esses centros), em vez de um `HStack` com
    /// vão fixo: a barra engorda até 0,66 pt no pico, e num `HStack` isso
    /// empurraria os vizinhos e transbordaria os 22 pt em vez de crescer em
    /// torno do próprio centro, como o `layoutSubviews` da Apple faz.
    private func barras(_ amplitudes: [CGFloat]) -> some View {
        ZStack {
            ForEach(0..<IlhaVisualizador.barras, id: \.self) { indice in
                let amplitude = indice < amplitudes.count ? amplitudes[indice] : 0
                Capsule(style: .continuous)
                    .frame(
                        width: IlhaVisualizador.largura(
                            amplitude: amplitude, area: Self.area),
                        height: IlhaVisualizador.altura(
                            amplitude: amplitude, area: Self.area))
                    .position(
                        x: IlhaVisualizador.centro(indice, largura: Self.area.width),
                        y: Self.area.height / 2)
            }
        }
        .frame(width: Self.area.width, height: Self.area.height)
    }
}

// MARK: - Avatar remoto do card

/// Avatar do card: tenta o avatar remoto (com guardas) quando há iconURL e o
/// toggle está on; senão o ícone do app; senão o sino.
struct RemoteAvatarView: View {
    let iconURL: String?
    let iconEmoji: String?
    var iconColor: NSColor? = nil
    let fallbackPath: String?
    /// Emoji e sino foram desenhados pro card (32 pt); a linha do histórico
    /// usa metade.
    var escala: CGFloat = 1
    @StateObject private var loader = RemoteAvatarLoader()

    var body: some View {
        Group {
            if let iconColor {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: iconColor))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1))
            } else if let e = iconEmoji, !e.isEmpty {
                Text(e).font(.system(size: 22 * escala))
            } else if let img = loader.image {
                Image(nsImage: img).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else if let path = fallbackPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
            } else {
                Image(systemName: "bell.badge.fill").resizable().scaledToFit()
                    .padding(6 * escala).foregroundStyle(.white.opacity(0.6))
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
