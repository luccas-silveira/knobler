//
//  NotchView.swift
//  Knobler
//

import SwiftUI

struct NotchView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var media: MediaController
    // NÃO observado aqui: os níveis publicam a 30Hz e re-renderizariam o notch
    // inteiro em cada monitor — só o AudioBarsView (folha) observa
    let levels: SystemAudioLevels
    @ObservedObject var shelf: ShelfStore
    /// false no harness de snapshot: onDrop cria uma NSView que o ImageRenderer
    /// não renderiza (vira placeholder amarelo). No app fica sempre true.
    var dropTargetsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Abrir tem leve overshoot (assinatura do Dynamic Island); fechar é seco.
    /// Reduced Motion vira fade rápido.
    private var morphAnimation: Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        let opening = vm.mode != .closed || vm.peeking
        return opening
            ? .spring(response: 0.42, dampingFraction: 0.76)
            : .spring(response: 0.30, dampingFraction: 0.95)
    }

    private let expandedSize = CGSize(width: 430, height: 188)
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

    private var notch: some View {
        let compact = vm.mode == .closed || vm.mode == .hud
            || vm.mode == .dictation || vm.mode == .pomodoro
        // raios menores no compacto: as curvas de canto decepavam a capa/barras
        let shape = NotchShape(
            topCornerRadius: compact ? 6 : 14,
            bottomCornerRadius: compact ? 12 : 30
        )
        return ZStack(alignment: .top) {
            shape.fill(Color.black)

            switch vm.mode {
            case .closed:
                if wingsVisible || vm.activity != nil || vm.micInUse {
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
                    .frame(width: expandedSize.width - 44)
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
                    .frame(width: notificationWidth - 48, height: 56)
                    .padding(.top, topInset)
                    // notificação desce do notch, como no iPhone
                    .transition(.blurReplace.combined(with: .move(edge: .top)))
            case .question:
                questionCard
                    // pergunta desce do notch, como as notificações
                    .transition(.blurReplace.combined(with: .move(edge: .top)))
            }
        }
        // recorta o conteúdo com a própria forma do notch — fechando, a informação
        // some junto com a moldura, em sincronia
        .compositingGroup()
        .mask(shape)
        // aberto, o notch "flutua" sobre o wallpaper; fechado, some na moldura
        .shadow(
            color: .black.opacity(vm.mode == .closed ? 0 : 0.35),
            radius: 12, y: 5
        )
        .frame(width: currentSize.width, height: currentSize.height)
        // folga invisível de hover ao redor do card aberto: jitter na borda
        // não fecha; e o hit-test cobre o retângulo todo, não só o desenhado
        .padding(.horizontal, vm.mode == .music ? 16 : 0)
        .padding(.bottom, vm.mode == .music ? 16 : 0)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var interactiveNotch: some View {
        Group {
            if dropTargetsEnabled {
                notch.onDrop(
                    of: [.fileURL],
                    delegate: ShelfDropDelegate(shelf: shelf, vm: vm))
            } else {
                notch
            }
        }
        .onHover { inside in
            if vm.mode == .notification {
                vm.holdNotification(inside)
            } else if !inside || vm.mode != .question {
                // hover no card de pergunta é pra clicar em opção, não pra
                // expandir: setHover(true) aqui armava expanded invisível e o
                // card de música abria sozinho depois da resposta. A saída
                // (inside=false) continua passando pra desarmar estado antigo.
                vm.setHover(inside)
            }
        }
        .animation(morphAnimation, value: vm.mode)
        .animation(morphAnimation, value: wingsVisible)
        .animation(morphAnimation, value: vm.micInUse)
        .animation(morphAnimation, value: vm.ask)
        .animation(morphAnimation, value: vm.askPage)
    }

    /// Faixa morta no topo dos cards: só existe onde tem câmera de verdade.
    private var topInset: CGFloat {
        vm.hasRealNotch ? vm.notchSize.height : 4
    }

    private var currentSize: CGSize {
        // notch real: asas ao redor da câmera; externo: o conteúdo dita o tamanho
        switch vm.mode {
        case .closed:
            let hasContent = wingsVisible || vm.activity != nil || vm.micInUse
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
            let hasShelf = !shelf.items.isEmpty
            let hasPomodoro = vm.pomodoro != nil
            // Pomodoro ativo suprime música e placeholder
            let placeholder = !hasMusic && vm.activity == nil && !hasShelf
                && !vm.mirrorOn && !hasPomodoro
            var height = topInset
            if hasPomodoro { height += 128 }  // cabeçalho + timer grande + ciclo + controles
            if vm.mirrorOn {
                height += vm.activity != nil || hasShelf ? 190 : 202
            }
            if !vm.mirrorOn, !hasPomodoro, hasMusic || placeholder { height += 140 }
            if vm.activity != nil { height += hasMusic || hasShelf ? 46 : 60 }
            if hasShelf { height += hasMusic || vm.activity != nil ? 62 : 76 }
            return CGSize(width: expandedSize.width, height: height)
        case .notification:
            return CGSize(width: notificationWidth, height: topInset + 56)
        case .question:
            guard let ask = vm.ask else {
                return CGSize(width: 460, height: topInset + 120)
            }
            let question = ask.questions[min(vm.askPage, ask.questions.count - 1)]
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
        if let ask = vm.ask {
            AskCardView(vm: vm, ask: ask)
                .frame(width: currentSize.width - 40)
                .padding(.top, topInset + 6)
                .padding(.bottom, 12)
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

    // MARK: - Música expandida

    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 10) {
            // Pomodoro ativo toma o topo do card; a música some enquanto ele roda
            if let p = vm.pomodoro {
                pomodoroSection(p)
                    .transition(.blurReplace)
            }
            if vm.mirrorOn {
                mirrorSection
                    .transition(.blurReplace)
            }
            if !shelf.items.isEmpty {
                ShelfRowView(shelf: shelf)
                    .transition(.blurReplace)
            }
            if let activity = vm.activity {
                activityRow(activity)
                    .transition(.blurReplace)
            }
            // espelho aberto (ou Pomodoro ativo) toma o lugar da música — volta ao fechar/encerrar
            if !vm.mirrorOn, vm.pomodoro == nil {
                musicSection
            }
        }
        .animation(.easeOut(duration: 0.3), value: vm.activity == nil)
        .animation(.easeOut(duration: 0.3), value: shelf.items)
        .animation(.easeOut(duration: 0.3), value: vm.mirrorOn)
        .animation(.easeOut(duration: 0.3), value: vm.pomodoro == nil)
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
                    mirrorButton
                        .padding(.trailing, 4)
                    audioBars
                        .frame(width: 24, height: 18)
                }
                progressBar(state)
                controls(state)
            }
            .frame(maxWidth: .infinity)
            // troca de faixa: capa e textos fazem crossfade em vez de pop
            .animation(.easeOut(duration: 0.3), value: state.title)
        } else if vm.activity == nil, shelf.items.isEmpty, !vm.mirrorOn {
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
                Text("-" + Self.timeString(max(0, state.duration - position)))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    // 5 itens distribuídos na largura toda, como na referência:
    // star · backward · play/pause (maior) · forward · macbook
    private func controls(_ state: MediaController.PlaybackState) -> some View {
        HStack(spacing: 0) {
            Button { media.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.body)
                    .foregroundStyle(state.shuffling ? .white : .white.opacity(0.45))
                    .contentTransition(.symbolEffect(.replace))
            }
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
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "macbook")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Notificação

    @ViewBuilder
    private var notificationCard: some View {
        if let notification = vm.activeNotification {
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
                openSourceApp(notification)
                vm.dismissActiveNotification()
            }
        }
    }

    private func appIcon(for notification: NotchNotification) -> some View {
        Group {
            if let path = Self.appPath(
                bundleID: notification.bundleID, named: notification.appName) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
            } else {
                Image(systemName: "bell.badge.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 32, height: 32)
    }

    private func openSourceApp(_ notification: NotchNotification) {
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
