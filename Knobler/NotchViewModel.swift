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
    /// Tela deste view model (existe um por monitor). Quem precisa saber "sou
    /// eu?" — hoje só a nota rápida — compara com este id. nil no harness de
    /// snapshot, que instancia o VM solto.
    var displayID: CGDirectDisplayID?

    @Published var expanded = false {
        // recolher o notch desliga o espelho — a câmera nunca fica ligada escondida
        didSet {
            if !expanded {
                mirrorOn = false
                // escolha manual vale até fechar; a próxima abertura volta ao automático
                focusLocked = false
                // pedido de foco que ninguém consumiu morre aqui: vivo, ele
                // vazaria pra abertura seguinte e abriria numa seção que o
                // usuário não pediu — já travada, matando a promoção do card.
                focoPendente = nil
            }
        }
    }
    @Published var mirrorOn = false {
        didSet { if mirrorOn != oldValue { marcarEvento(.espelho) } }
    }
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
    /// Atividade em curso. Só título/detalhe e o aparecer/sumir promovem — o
    /// `progress` (e o `updatedAt` que vem junto) anda a cada passo e faria a
    /// atividade morar no topo pra sempre.
    @Published var activity: NotchActivity? {
        didSet {
            guard activity?.title != oldValue?.title
                || activity?.detail != oldValue?.detail
                || (activity == nil) != (oldValue == nil) else { return }
            marcarEvento(.atividade)
        }
    }
    /// Timer Pomodoro em exibição (pílula própria no notch). nil = idle.
    /// Só fase/estado promovem — `remaining` muda a cada segundo e faria o
    /// Pomodoro morar no topo pra sempre.
    @Published var pomodoro: PomodoroState? {
        didSet {
            guard pomodoro?.phase != oldValue?.phase
                || pomodoro?.runState != oldValue?.runState else { return }
            marcarEvento(.pomodoro)
        }
    }
    /// AirPods conectados: bateria por componente (nil = desconectado). Alimenta
    /// a faixa junto da música e o card dedicado no hover.
    @Published var airpods: AirPodsBattery?
    /// Card transitório de AirPods (connect / bateria baixa), auto-some.
    @Published var airpodsCard = false
    /// Atualização disponível/instalando. Espelha o Updater; quem empurra é o
    /// AppDelegate, como faz com AirPods e Pomodoro.
    @Published var update: UpdateState?
    /// Card de update em exibição. Sem esta flag o card ficaria permanente: o
    /// `update` não é transitório como um HUD.
    @Published var updateCard = false
    /// Dá pra instalar de dentro do app? false = sem brew e sem asset baixável,
    /// e o botão do card vira "Ver release" em vez de mentir.
    @Published var updateCanInstall = true
    /// Ações do card — o app conecta no Updater.
    var onUpdateInstall: (() -> Void)?
    var onUpdateSkip: (() -> Void)?

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
    /// Conversa aberta na seção Mensagens (peerID) — nil = mostra a lista.
    /// Fonte da verdade da seleção (a MessagesView lê/escreve aqui) pra que
    /// `openThread` (clique no card) consiga abrir a conversa certa.
    @Published var selectedThreadPeerID: String?
    /// Resposta rápida do card → app envia (peerID, texto).
    var onSendReply: ((String, String) -> Void)?
    private var incomingWork: DispatchWorkItem?

    // MARK: - Eventos das seções (insumo da hierarquia do card)

    /// Quando cada seção teve o último **evento de transição**. É o insumo da
    /// promoção; ver a tabela em docs/specs/card-foco.md pra o que conta.
    /// Não é `@Published`: só é lido no instante em que o card abre.
    private(set) var eventos: [NotchSection: Date] = [:]

    func marcarEvento(_ section: NotchSection, at date: Date = Date()) {
        eventos[section] = date
    }

    /// Retrato das seções pro `NotchSectionOrder`. Os dados que não moram no
    /// VM (música, shelf, histórico, mensagens, nota) entram por parâmetro:
    /// quem chama é a NotchView, que já observa esses stores.
    func estadoDasSecoes(hasMusic: Bool, hasShelf: Bool,
                         hasHistory: Bool, hasMensagens: Bool,
                         hasNota: Bool, hasLink: Bool = false) -> [NotchSectionState] {
        let conteudo: [NotchSection: Bool] = [
            .musica: hasMusic,
            .atividade: activity != nil,
            .pomodoro: pomodoro != nil,
            .shelf: hasShelf,
            .espelho: mirrorOn,
            .mensagens: hasMensagens,
            .historico: hasHistory,
            .nota: hasNota,
            .link: hasLink,
        ]
        return NotchSection.allCases.map {
            NotchSectionState(section: $0,
                              hasContent: conteudo[$0] ?? false,
                              lastEvent: eventos[$0])
        }
    }

    // MARK: - Foco do card aberto

    /// Ordem efetiva do card, congelada no instante da abertura. Recalcular a
    /// cada mudança faria o conteúdo pular debaixo do cursor e mover o alvo de
    /// clique da faixa.
    ///
    /// `internal` e não `private(set)`: o harness de snapshot monta a lista à
    /// mão pra capturar cenários que não dá pra provocar offscreen.
    @Published var secoes: [NotchSection] = []
    @Published var focus: NotchSection?
    /// Escolha manual do usuário (clique na faixa ou swipe): nenhuma promoção
    /// tira o foco até o notch recolher.
    @Published private(set) var focusLocked = false
    /// Altura desenhada do notch agora, em QUALQUER modo (fechado, HUD, ditado,
    /// card aberto) — não só do card. Publicada porque o monitor de scroll roda
    /// fora do SwiftUI e precisa dela pra delimitar a zona do gesto.
    @Published private(set) var alturaAtual: CGFloat = 0

    /// Foco pedido de fora ANTES de o card abrir (clique no card de mensagem, o
    /// painel de arquivos que devolve o anexo). A ordem só existe depois do
    /// `recalcularSecoes`, então o pedido espera aqui em vez de ser sobrescrito
    /// pela promoção da abertura.
    ///
    /// Semântica do slot, em três regras:
    /// 1. só é consumido quando a seção pedida **existe** na ordem — antes
    ///    disso ele espera, em vez de sumir em silêncio;
    /// 2. quem pede com o card **já aberto** não passa por aqui: chama `focar`
    ///    direto, porque o único gatilho de `recalcularSecoes` é a mudança de
    ///    `expanded` e ela não acontece;
    /// 3. fechar o card apaga o pedido (ver o `didSet` de `expanded`).
    var focoPendente: NotchSection?

    func recalcularSecoes(_ estados: [NotchSectionState], travadaNaNota: Bool) {
        secoes = NotchSectionOrder.ordenar(base: AppSettings.shared.notchSectionOrder,
                                           estados: estados,
                                           fixadas: AppSettings.shared.notchSectionsFixadas,
                                           agora: Date(),
                                           travadaNaNota: travadaNaNota)
        // a trava da nota vence até a escolha manual anterior — e descarta o
        // pedido pendente de propósito: digitar é o compromisso mais forte, e
        // deixar o pedido vivo faria o foco pular de seção no instante em que o
        // usuário largasse o teclado.
        if travadaNaNota, secoes.contains(.nota) {
            focus = .nota
            focoPendente = nil
            return
        }
        // o pedido só é consumido quando a seção pedida de fato entrou na
        // ordem; sem conteúdo ainda, ele espera o próximo recálculo
        if let pedido = focoPendente, secoes.contains(pedido) {
            focar(pedido)
            return
        }
        // uma seção fixada aparece vazia; abrir o card em cima dela mostraria
        // "Nada tocando" com música parada, então o foco procura o primeiro
        // conteúdo real e só cai no primeiro da lista quando não há nenhum.
        let comConteudo = Set(estados.filter(\.hasContent).map(\.section))
        let inicial = secoes.first(where: { comConteudo.contains($0) }) ?? secoes.first
        guard !focusLocked, let primeira = inicial else {
            // o foco travado pode ter perdido o conteúdo enquanto isso
            if let f = focus, !secoes.contains(f) { focus = inicial; focusLocked = false }
            return
        }
        focus = primeira
    }

    func focar(_ section: NotchSection) {
        guard secoes.contains(section) else { return }
        focoPendente = nil
        focus = section
        focusLocked = true
    }

    /// Swipe horizontal no card: anda um passo na faixa e trava, igual ao clique.
    func focarVizinho(avancando: Bool) {
        guard let atual = focus, let i = secoes.firstIndex(of: atual), secoes.count > 1 else { return }
        let destino = (i + (avancando ? 1 : -1) + secoes.count) % secoes.count
        focar(secoes[destino])
    }

    func publicarAltura(_ h: CGFloat) {
        guard abs(h - alturaAtual) > 0.5 else { return }
        alturaAtual = h
    }

    struct HUDState: Equatable {
        enum Kind: Equatable { case volume, brightness, battery }
        var kind: Kind = .volume
        var level: Float
        var muted: Bool = false
        var charging: Bool = false
    }

    enum Mode: Equatable {
        case closed, music, notification, hud, dictation, question, pomodoro, airpods, message
        case update
    }

    /// Digitando na nota rápida nesta tela — o compromisso mais forte que o
    /// usuário faz com o notch, e por isso ganha de notificação e HUD.
    var typingNote: Bool { QuickNote.shared.typing(on: displayID) }
    /// Link aberto nesta tela: segura o card do mesmo jeito que digitar na nota.
    /// Sem isto a página fecharia assim que o mouse saísse pra ler.
    var linkAberto: Bool { LinkPreview.shared.hosted(by: displayID) }

    /// Prioridade dos modos próprios: mensagem > ditado > nota (digitando) >
    /// notificação > HUD > update > AirPods(card) > música (hover) > pomodoro
    /// > fechado. Ask é derivado pelo NotchView a partir do AskStore
    /// compartilhado.
    var mode: Mode {
        if incoming != nil { return .message }
        if dictation != nil { return .dictation }
        // nota com o teclado nos dedos vence notificação e HUD: quando o campo
        // sai da árvore, o `.onDisappear` zera o foco, `keyboardAllowed` cai e o
        // painel larga a chave — as teclas seguintes vão pro app da frente sem
        // sinal nenhum. Ditado e mensagem ainda passam na frente (ditado é
        // pedido pelo usuário; mensagem tem campo de resposta próprio).
        if typingNote { return .music }
        if activeNotification != nil { return .notification }
        if hud != nil { return .hud }
        // update nunca interrompe ditado, notificação ou HUD — só espera
        if updateCard, update != nil { return .update }
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
    /// O alerta do sistema vive ~30s; o card espelhado acompanha.
    private let actionableDuration: TimeInterval = 30.0
    private let hudDuration: TimeInterval = 1.5
    private var pendingWork: DispatchWorkItem?
    private var queue: [NotchNotification] = []
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
                // digitar na nota não pode ser interrompido por um mouse que
                // saiu da área — Esc solta o foco e aí o hover-out volta a
                // valer. Só na tela dona: uma nota focada no monitor A não
                // pode congelar o card do monitor B.
                guard !self.typingNote, !self.linkAberto else { return }
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
        marcarEvento(.mensagens)
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

    /// Abre a conversa daquele peer na seção Mensagens.
    func openThread(peerID: String) {
        requestDismissIncoming()
        selectedThreadPeerID = peerID
        pedirFoco(.mensagens)
    }

    /// Pede foco numa seção e garante o card aberto. Com o card **já** aberto o
    /// slot `focoPendente` não serve: quem o consome é o `recalcularSecoes`
    /// disparado pelo `onChange(of: expanded)`, e sem mudança de `expanded` o
    /// pedido ficaria preso até a próxima abertura. Ex.: card aberto por hover
    /// + mensagem LAN chegando + clique no card.
    func pedirFoco(_ section: NotchSection) {
        guard expanded else {
            focoPendente = section
            setExpandedDirect(true)
            return
        }
        // seção que ainda não entrou na ordem congelada volta pro slot e espera
        // o próximo recálculo — some em silêncio se `focar` só desistisse
        if secoes.contains(section) { focar(section) } else { focoPendente = section }
    }

    // MARK: - Notificações

    func enqueue(_ notification: NotchNotification) {
        NotificationHistory.shared.record(notification)
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
        // digitando: enfileira em vez de mostrar. Só esconder pelo `mode` não
        // bastaria — o auto-dismiss de 5s correria invisível e a notificação
        // morreria sem ninguém ver.
        if activeNotification == nil, !typingNote {
            show(notification)
        } else {
            queue.append(notification)
        }
    }

    /// Fim da digitação: solta a notificação que esperou. Chamado pela view
    /// quando `QuickNote.editing` cai (Esc, clique fora, interruptor desligado).
    func resumePendingNotifications() {
        guard activeNotification == nil, !typingNote, !queue.isEmpty else { return }
        show(queue.removeFirst())
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
        // card com botões espera uma decisão: 5s não dá tempo nem de ler
        let duration = activeNotification?.actionTitles.isEmpty == false
            ? actionableDuration : notificationDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// Ação do card (Aceitar/Recusar) → o app aciona o botão real do alerta.
    var onNotificationAction: ((UUID, Int) -> Void)?
    /// Envio por AirDrop que mostra estado no notch. O `AppDelegate` liga; o
    /// harness de snapshot deixa nil e o shelf cai no envio mudo.
    var onAirDrop: (([URL]) -> Void)?

    // MARK: - HUD de som

    func showHUD(_ state: HUDState, duration: TimeInterval? = nil) {
        // HUD é transitório: enquanto a nota tem o teclado ele não aparece e
        // não espera fila — guardar um nível de volume de 3s atrás pra mostrar
        // depois seria pior que não mostrar.
        guard !typingNote else { return }
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

    /// Controles do card do Pomodoro (view → engine no AppDelegate).
    var onPomodoroPause: (() -> Void)?
    var onPomodoroResume: (() -> Void)?
    var onPomodoroSkip: (() -> Void)?
    var onPomodoroReset: (() -> Void)?
    var onPomodoroStartNext: (() -> Void)?
    var onPomodoroSettings: (() -> Void)?

}
