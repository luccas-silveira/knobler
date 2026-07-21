//
//  NotchViewModel.swift
//  Knobler
//

import Foundation
import SwiftUI

/// Atividade persistente publicada via API local (deploy, download, métrica…).
struct NotchActivity: Equatable {
    var id: String
    var title: String
    var detail: String
    /// 0…1; nil = indeterminada (arco girando)
    var progress: Double?
    var updatedAt: Date
}

/// Fases do ditado por voz mostradas na pílula do notch.
enum DictationPhase: Equatable {
    case preparing              // modelo local ainda baixando/carregando
    case recording(level: Float)
    case transcribing
    case error(String)
}

final class NotchViewModel: ObservableObject {
    @Published var expanded = false {
        // recolher o notch desliga o espelho — a câmera nunca fica ligada escondida
        didSet { if !expanded { mirrorOn = false } }
    }
    @Published var mirrorOn = false
    /// Algum app está capturando o microfone (pontinho laranja no notch).
    @Published var micInUse = false
    /// Música pausada some do notch; hover "espia" (peeking) antes de expandir.
    @Published var musicPaused = false
    @Published var peeking = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    /// true = notch físico (câmera no meio); false = ilha simulada em monitor externo
    @Published var hasRealNotch = false
    @Published var activeNotification: NotchNotification?
    @Published var hud: HUDState?
    @Published var dictation: DictationPhase?
    @Published var activity: NotchActivity?
    /// Timer Pomodoro em exibição (pílula própria no notch). nil = idle.
    @Published var pomodoro: PomodoroState?
    /// AirPods conectados: bateria por componente (nil = desconectado). Alimenta
    /// a faixa junto da música e o card dedicado no hover.
    @Published var airpods: AirPodsBattery?
    /// Card transitório de AirPods (connect / bateria baixa), auto-some.
    @Published var airpodsCard = false
    /// Pergunta do Claude Code em exibição (card interativo).
    @Published var ask: AskRequest?
    /// Página corrente do card (chamada com N perguntas).
    @Published var askPage = 0
    /// Texto livre do card — vive aqui (e não em @State) pra receber o
    /// ditado por fan-out do AppDelegate.
    @Published var askText = ""

    /// Aba do notch aberto: música (default) ou mensagens LAN.
    enum NotchTab: Equatable { case music, messages }
    @Published var tab: NotchTab = .music

    /// Mensagem LAN chegando, exibida como card no notch.
    struct IncomingMessage: Equatable {
        let peerID: String
        let name: String
        let text: String
        let allowReply: Bool
        /// Arquivo da foto/GIF recebido (nome em `media/`), se houver.
        var mediaFile: String?
        /// Altura que a imagem ocupa no card (o app calcula: tem o store).
        var mediaHeight: CGFloat = 0
    }
    @Published var incoming: IncomingMessage?
    /// Foto/GIF escolhido, esperando o envio. Mora aqui (e não em @State da
    /// MessagesView) porque o painel de arquivos tira o mouse do notch, o notch
    /// fecha e a view morreria levando a escolha junto.
    struct PendingAttachment { let data: Data; let kind: MediaKind }
    @Published var pendingAttachment: PendingAttachment?
    /// Última escolha falhou (formato/tamanho) — a view mostra o aviso.
    @Published var attachmentFailed = false
    /// Conversa aberta na aba Mensagens (peerID) — nil = mostra a lista.
    /// Fonte da verdade da seleção (a MessagesView lê/escreve aqui) pra que
    /// `openThread` (clique no card) consiga abrir a conversa certa.
    @Published var selectedThreadPeerID: String?
    /// Resposta rápida do card → app envia (peerID, texto).
    var onSendReply: ((String, String) -> Void)?
    private var incomingWork: DispatchWorkItem?

    struct HUDState: Equatable {
        enum Kind: Equatable { case volume, brightness, battery }
        var kind: Kind = .volume
        var level: Float
        var muted: Bool = false
        var charging: Bool = false
    }

    enum Mode: Equatable {
        case closed, music, notification, hud, dictation, question, pomodoro, airpods, message
    }

    /// Prioridade: pergunta > mensagem > ditado > notificação > HUD > AirPods(card) > música (hover) > pomodoro > fechado.
    var mode: Mode {
        if ask != nil { return .question }
        if incoming != nil { return .message }
        if dictation != nil { return .dictation }
        if activeNotification != nil { return .notification }
        if hud != nil { return .hud }
        if airpodsCard { return .airpods }
        if expanded { return .music }
        if pomodoro != nil { return .pomodoro }
        return .closed
    }

    /// Mouse sobre o notch agora — o peek de captura usa isto pra não fechar
    /// o card enquanto o usuário está com o cursor em cima.
    var isHovering: Bool { hovering }

    // ponytail: delays fixos anti-flicker; virar preferência se incomodar
    private let openDelay: TimeInterval = 0.18
    private let closeDelay: TimeInterval = 0.30
    /// Janela pós-fechar em que enter é ignorado: o frame encolhendo debaixo
    /// do mouse dispara enter de novo e reabre em loop sem isso.
    private let reopenCooldown: TimeInterval = 0.45
    private var lastCollapseAt = Date.distantPast
    private let notificationDuration: TimeInterval = 5.0
    private let hudDuration: TimeInterval = 1.5
    private var pendingWork: DispatchWorkItem?
    private var queue: [NotchNotification] = []
    private var askQueue: [AskRequest] = []
    private var dismissWork: DispatchWorkItem?
    private var hudWork: DispatchWorkItem?

    private var hovering = false
    /// Pausado: tempo de espiada antes de abrir o card completo.
    private let peekDwell: TimeInterval = 0.8

    func setHover(_ inside: Bool) {
        hovering = inside
        pendingWork?.cancel()

        guard inside else {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.expanded || self.peeking { self.lastCollapseAt = Date() }
                self.expanded = false
                self.peeking = false
            }
            pendingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay, execute: work)
            return
        }

        guard !expanded else { return }
        guard Date().timeIntervalSince(lastCollapseAt) >= reopenCooldown else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hovering else { return }
            if self.musicPaused, !self.peeking, self.pomodoro == nil {
                // etapa 1: espia as asinhas; mouse parado em cima abre o completo
                // (só pra música — com Pomodoro ativo abre o card direto)
                self.peeking = true
                self.scheduleExpandAfterPeek()
            } else {
                self.expanded = true
            }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + openDelay, execute: work)
    }

    private func scheduleExpandAfterPeek() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hovering else { return }
            self.expanded = true
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + peekDwell, execute: work)
    }

    /// Abre/fecha por gesto (swipe): imediato, sem os delays do hover.
    func setExpandedDirect(_ value: Bool) {
        pendingWork?.cancel()
        expanded = value
    }

    // MARK: - Mensagens LAN

    /// Mostra o card de entrada. Some sozinho como notificação — com resposta
    /// permitida demora mais (dá tempo de ler e digitar), mas some.
    func showIncoming(_ m: IncomingMessage) {
        incoming = m
        scheduleIncomingDismiss()
    }

    private func scheduleIncomingDismiss() {
        guard let incoming else { return }
        incomingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.incoming = nil }
        incomingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (incoming.allowReply ? 20 : 6),
                                      execute: work)
    }

    /// Ponteiro sobre o card segura; ao sair, o relógio recomeça (igual às
    /// notificações) — ninguém perde o card no meio da resposta.
    func holdIncoming(_ hovering: Bool) {
        guard incoming != nil else { return }
        if hovering { incomingWork?.cancel() } else { scheduleIncomingDismiss() }
    }

    func dismissIncoming() {
        incomingWork?.cancel()
        incoming = nil
    }

    /// Fechar/abrir o card vale pra TODAS as telas — o app faz o fan-out.
    /// Sem isso, o X some só no monitor clicado e sobra card no outro.
    var onDismissEverywhere: (() -> Void)?

    func requestDismissIncoming() {
        if let onDismissEverywhere { onDismissEverywhere() } else { dismissIncoming() }
    }

    /// Abre a conversa daquele peer na aba Mensagens.
    func openThread(peerID: String) {
        requestDismissIncoming()
        selectedThreadPeerID = peerID
        tab = .messages
        setExpandedDirect(true)
    }

    // MARK: - Notificações

    func enqueue(_ notification: NotchNotification) {
        // progresso: mesmo webhookID substitui a ativa ou a enfileirada
        if let wid = notification.webhookID {
            if activeNotification?.webhookID == wid {
                activeNotification = notification
                scheduleDismiss()
                return
            }
            if let i = queue.firstIndex(where: { $0.webhookID == wid }) {
                queue[i] = notification
                return
            }
        }
        if activeNotification == nil {
            show(notification)
        } else {
            queue.append(notification)
        }
    }

    func dismissActiveNotification() {
        dismissWork?.cancel()
        activeNotification = nil
        if !queue.isEmpty {
            let next = queue.removeFirst()
            // respiro entre uma e outra pra animação de fechar/abrir ler bem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.show(next)
            }
        }
    }

    /// Segurar o mouse em cima pausa o auto-dismiss.
    func holdNotification(_ hovering: Bool) {
        guard activeNotification != nil else { return }
        if hovering {
            dismissWork?.cancel()
        } else {
            scheduleDismiss()
        }
    }

    private func show(_ notification: NotchNotification) {
        activeNotification = notification
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.dismissActiveNotification()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + notificationDuration, execute: work)
    }

    // MARK: - HUD de som

    func showHUD(_ state: HUDState, duration: TimeInterval? = nil) {
        hud = state
        hudWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hud = nil
        }
        hudWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (duration ?? hudDuration), execute: work)
    }

    // MARK: - Card de AirPods (transitório)

    private var airpodsWork: DispatchWorkItem?

    /// Mostra o card de AirPods por `duration` e some (igual ao HUD).
    func showAirPodsCard(duration: TimeInterval = 4.0) {
        airpodsCard = true
        airpodsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.airpodsCard = false }
        airpodsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: - Perguntas do Claude Code

    /// Fiação do AppDelegate: resposta/cancelamento voltam pro servidor
    /// e sincronizam os outros monitores (primeira resposta vence).
    var onAskAnswered: ((String, [String: AskAnswer]) -> Void)?
    var onAskCancelled: ((String) -> Void)?

    /// Controles do card do Pomodoro (view → engine no AppDelegate).
    var onPomodoroPause: (() -> Void)?
    var onPomodoroResume: (() -> Void)?
    var onPomodoroSkip: (() -> Void)?
    var onPomodoroReset: (() -> Void)?
    var onPomodoroStartNext: (() -> Void)?
    var onPomodoroSettings: (() -> Void)?

    func enqueueAsk(_ request: AskRequest) {
        if ask == nil {
            askPage = 0
            askText = ""
            ask = request
        } else if ask?.id != request.id,
                  !askQueue.contains(where: { $0.id == request.id }) {
            askQueue.append(request)
        }
    }

    /// Encerra o ask (respondido/cancelado em qualquer monitor) e promove
    /// o próximo da fila FIFO.
    func clearAsk(id: String) {
        askQueue.removeAll { $0.id == id }
        guard ask?.id == id else { return }
        ask = nil
        askPage = 0
        askText = ""
        if !askQueue.isEmpty {
            let next = askQueue.removeFirst()
            // respiro pra animação de fechar/abrir ler bem (padrão das notificações)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.enqueueAsk(next)
            }
        }
    }

    /// Chamado pelo card na última página com TODAS as respostas acumuladas.
    func answerAsk(_ answers: [String: AskAnswer]) {
        guard let current = ask else { return }
        onAskAnswered?(current.id, answers)
        clearAsk(id: current.id)
    }

    /// ✕ do card: pergunta volta pro terminal do Claude Code.
    func cancelActiveAsk() {
        guard let current = ask else { return }
        onAskCancelled?(current.id)
        clearAsk(id: current.id)
    }
}
