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

    @Published private(set) var expanded = false
    private var opening = NotchOpening()
    private var openingWork: DispatchWorkItem?
    var questionIsActive: () -> Bool = { false }
    @Published var availableSize = CGSize(width: 900, height: 900)
    private(set) var presentation: NotchPresentation?
    private var sectionInputs = NotchSectionInputs()
    private var receivedSections = false

    func updateSections(_ inputs: NotchSectionInputs) {
        let membershipChanged = inputs.note != sectionInputs.note
            || inputs.messages != sectionInputs.messages || inputs.link != sectionInputs.link
            || inputs.agentes != sectionInputs.agentes
        sectionInputs = inputs
        receivedSections = true
        if expanded && (secoes.isEmpty || membershipChanged) { reconcileSections() }
    }

    private func reconcileSections() {
        if sectionInputs.annotation { focoPendente = .anotacao }
        recalcularSecoes(estadoDasSecoes(hasMusic: sectionInputs.music, hasShelf: sectionInputs.shelf,
            hasHistory: sectionInputs.history, hasMensagens: sectionInputs.messages,
            hasNota: sectionInputs.note, hasLink: sectionInputs.link,
            hasAgentes: sectionInputs.agentes), travadaNaNota: typingNote)
    }


    func publishPresentation(_ value: NotchPresentation) {
        presentation = value
        publicarAltura(value.size.height)
    }

    @Published var mirrorOn = false {
        didSet { if mirrorOn != oldValue { marcarEvento(.espelho) } }
    }
    /// Algum app está capturando o microfone (pontinho laranja no notch).
    @Published var micInUse = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    /// true = notch físico (câmera no meio); false = ilha simulada em monitor externo
    @Published var hasRealNotch = false
    @Published var activeNotification: NotchNotification?
    /// Mouse sobre o card de notificação: o timer para e o texto abre inteiro.
    @Published private(set) var notificationHeld = false
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
    /// Próximo evento do calendário. Sem `didSet`: não é mudança de seção, só
    /// alimenta a linha extra do card do Pomodoro e a pílula fechada.
    @Published var calendarAviso: CalendarAviso?
    @Published var monitoresSelecionado: UInt32?
    @Published var monitoresDisponiveis = false
    @Published var monitoresArrastando = false
    @Published var monitoresContraste = false
    var onMonitoresSettings: ((UInt32) -> Void)?
    var onLembretesView: (() -> AnyView)?
    var onAtualizarLembretes: (() -> Void)?
    @Published var lembretesEditando = false
    var editandoLembretes: Bool { expanded && focus == .lembretesApple && lembretesEditando }
    var lembretesRolavel: Bool { mode == .music && focus == .lembretesApple }
    func atualizarEdicaoLembretes(_ editing: Bool) {
        lembretesEditando = editing
        if !editing { resumePendingNotifications() }
    }
    @Published var agenda = CalendarAgenda()
    private(set) var agendaDeslocamento = 0
    var onConsultarAgenda: ((Date) -> CalendarAgenda)?
    var onAgendaPermissions: (() -> Void)?
    var onAgendaKeyboard: (() -> Void)?
    var onCalendariosAgenda: (() -> [CalendarDestino])?
    var onSalvarAgenda: ((CalendarRascunho, @escaping (Result<Date, CalendarErro>) -> Void) -> Void)?
    @Published var agendaRascunho: CalendarRascunho?
    var agendaRascunhoBinding: Binding<CalendarRascunho>? {
        guard let rascunho = agendaRascunho else { return nil }
        // Controles ainda podem ler/escrever enquanto o editor é desmontado.
        return Binding(
            get: { self.agendaRascunho ?? rascunho },
            set: { if self.agendaRascunho != nil { self.agendaRascunho = $0 } }
        )
    }
    @Published var agendaDestinos: [CalendarDestino] = []
    @Published private(set) var agendaSalvando = false
    @Published var agendaErro: String?
    @Published private(set) var agendaConfirmacao: String?

    var editandoAgenda: Bool { expanded && focus == .agenda && agendaRascunho != nil }
    private var protegeEdicao: Bool { typingNote || editandoAgenda || editandoLembretes }

    func novoEventoAgenda() {
        guard agendaRascunho == nil else { return }
        atualizarAgenda()
        agendaDestinos = onCalendariosAgenda?() ?? []
        var rascunho = CalendarRascunho.novo(no: agenda.dia)
        rascunho.calendarioID = agendaDestinos.first(where: \.padrao)?.id ?? ""
        agendaErro = nil
        agendaConfirmacao = nil
        agendaRascunho = rascunho
        // Cancela um fechamento que já estava na fila antes do clique.
        openingWork?.cancel()
    }

    func cancelarEventoAgenda() {
        guard !agendaSalvando else { return }
        agendaRascunho = nil
        agendaErro = nil
        resumePendingNotifications()
    }

    func salvarEventoAgenda() {
        guard !agendaSalvando, let rascunho = agendaRascunho else { return }
        agendaErro = nil
        do {
            try rascunho.validar(autorizado: agenda.autorizado, destinos: agendaDestinos)
        } catch {
            agendaErro = error.localizedDescription
            return
        }
        guard let salvar = onSalvarAgenda else {
            agendaErro = CalendarErro.gravacao.localizedDescription
            return
        }
        agendaSalvando = true
        salvar(rascunho) { [weak self] resultado in
            DispatchQueue.main.async {
                guard let self, self.agendaSalvando else { return }
                self.agendaSalvando = false
                switch resultado {
                case .success(let inicio):
                    self.agendaRascunho = nil
                    self.agendaDeslocamento = Calendar.current.dateComponents([.day],
                        from: Calendar.current.startOfDay(for: Date()),
                        to: Calendar.current.startOfDay(for: inicio)).day ?? 0
                    self.atualizarAgenda()
                    self.agendaConfirmacao = "Evento criado"
                    self.resumePendingNotifications()
                case .failure(let erro):
                    self.agendaErro = erro.localizedDescription
                    self.atualizarAgenda()
                }
            }
        }
    }

    var agendaRolavel: Bool {
        mode == .music && focus == .agenda
            && (agendaRascunho != nil || (agenda.autorizado && !agenda.eventos.isEmpty))
    }

    func atualizarAgenda(agora: Date = Date()) {
        guard let consultar = onConsultarAgenda,
              let dia = Calendar.current.date(byAdding: .day, value: agendaDeslocamento,
                                               to: Calendar.current.startOfDay(for: agora)) else { return }
        agenda = consultar(dia)
        if agendaRascunho != nil { agendaDestinos = onCalendariosAgenda?() ?? [] }
    }

    func navegarAgenda(_ dias: Int) {
        agendaConfirmacao = nil
        agendaDeslocamento += dias
        atualizarAgenda()
    }

    func agendaHoje() {
        agendaConfirmacao = nil
        agendaDeslocamento = 0
        atualizarAgenda()
    }
    /// AirPods conectados: bateria por componente (nil = desconectado).
    @Published var airpods: AirPodsBattery?
    /// Card grande de AirPods (hover na ilha ou bateria baixa), auto-some.
    @Published var airpodsCard = false
    /// Ilha compacta de conexão dos AirPods, auto-some.
    @Published var airpodsIsland = false
    /// Cursor sobre o card de AirPods: timer suspenso até a saída.
    private(set) var airpodsHeld = false
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
                         hasNota: Bool, hasLink: Bool = false,
                         hasAgentes: Bool = false) -> [NotchSectionState] {
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
            // a anotação é uma PÁGINA fixa do card: as ferramentas moram aqui,
            // não no menu da barra, então a seção não pode depender de estado.
            .anotacao: true,
            // A navegação e o acesso às permissões existem mesmo num dia vazio.
            .agenda: true,
            .lembretesApple: true,
            .monitores: monitoresDisponiveis,
            .agentes: hasAgentes,
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
    @Published var focus: NotchSection? {
        // o foco atravessa o relaunch; ver `restaurarFocoSalvo()`. Só grava
        // valor real: perder as seções (nenhum conteúdo) zera o foco, e gravar
        // esse nil apagaria a escolha do usuário sem que ele tenha escolhido.
        didSet {
            guard let focus, focus != oldValue else { return }
            UserDefaults.standard.set(focus.rawValue, forKey: Self.focoSalvoKey)
            if oldValue == .agenda || oldValue == .lembretesApple { resumePendingNotifications() }
        }
    }
    static let focoSalvoKey = "notchFocus"
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

    /// Reenfileira o foco da sessão anterior como pedido pendente. Não é o
    /// `focus` direto de propósito: `focoPendente` já espera a seção existir E
    /// ter conteúdo, então a restauração nunca abre o card numa seção vazia —
    /// e a trava da nota e uma escolha manual seguem vencendo o pedido.
    ///
    /// Chave única, não por monitor: dois notches restauram o mesmo foco.
    /// Chave por `displayID` quando alguém reclamar.
    func restaurarFocoSalvo() {
        focoPendente = UserDefaults.standard.string(forKey: Self.focoSalvoKey)
            .flatMap(NotchSection.init(rawValue:))
    }

    func recalcularSecoes(_ estados: [NotchSectionState], travadaNaNota: Bool) {
        secoes = NotchSectionOrder.ordenar(base: AppSettings.shared.notchSectionOrder,
                                           estados: estados,
                                           fixadas: AppSettings.shared.notchSectionsFixadas,
                                           agora: Date(),
                                           travadaNaNota: travadaNaNota,
                                           desinstaladas: NotchSection.desinstaladas(),
                                           ocultas: AppSettings.shared.notchSectionsOcultas,
                                           promover: AppSettings.shared.promoverSecoesRecentes)
        // a trava da nota vence até a escolha manual anterior — e descarta o
        // pedido pendente de propósito: digitar é o compromisso mais forte, e
        // deixar o pedido vivo faria o foco pular de seção no instante em que o
        // usuário largasse o teclado.
        if travadaNaNota, secoes.contains(.nota) {
            focus = .nota
            focoPendente = nil
            return
        }
        let comConteudo = Set(estados.filter(\.hasContent).map(\.section))
        // o pedido só é consumido quando a seção pedida entrou na ordem E tem o
        // que mostrar; sem conteúdo ainda, ele espera o próximo recálculo. A
        // presença na ordem não basta desde que existe seção fixada: fixada
        // aparece vazia, e consumir o pedido nela abriria o card no vazio em vez
        // de esperar a mensagem/anexo que motivou o pedido.
        if let pedido = focoPendente, secoes.contains(pedido), comConteudo.contains(pedido) {
            focar(pedido)
            return
        }
        // uma seção fixada aparece vazia; abrir o card em cima dela mostraria
        // "Nada tocando" com música parada, então o foco procura o primeiro
        // conteúdo real e só cai no primeiro da lista quando não há nenhum.
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
        // sair da nota solta a trava AQUI, antes de trocar o foco: o
        // `onDisappear` do TextEditor só zera depois da remontagem, e um
        // `recalcularSecoes` no meio-tempo veria `travadaNaNota` ainda true e
        // puxaria o foco de volta. Vale pro clique na faixa e pro swipe.
        // Sair da seção não encerra a nota: `active` e `text` seguem intactos.
        if focus == .nota, section != .nota, typingNote { QuickNote.shared.editing = false }
        focoPendente = nil
        if focus != section {
            focoTrocadoEm = ProcessInfo.processInfo.systemUptime
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
        focus = section
        focusLocked = true
    }

    private var focoTrocadoEm = -Double.infinity
    private var focoAoFechar: (NotchSection, TimeInterval)?
    static let memoriaDoFoco: TimeInterval = 30

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
        var displayID: UInt32?
        var displayName: String?
        var displayControl: String?
    }

    typealias Mode = NotchMode

    /// Digitando na nota rápida nesta tela — o compromisso mais forte que o
    /// usuário faz com o notch, e por isso ganha de notificação e HUD.
    var typingNote: Bool { QuickNote.shared.typing(on: displayID) }
    /// Link aberto nesta tela: segura o card do mesmo jeito que digitar na nota.
    /// Sem isto a página fecharia assim que o mouse saísse pra ler.
    var linkAberto: Bool { LinkPreview.shared.hosted(by: displayID) }

    func contentState(question: Bool? = nil) -> NotchContentState {
        NotchContentState(question: question ?? questionIsActive(), incoming: incoming != nil,
                          reply: incoming?.allowReply == true, dictation: dictation != nil,
                          typingNote: typingNote, editingAgenda: editandoAgenda, editingReminders: editandoLembretes, notification: activeNotification != nil,
                          hud: hud != nil, update: updateCard && update != nil,
                          airpods: airpodsCard, airpodsIsland: airpodsIsland, expanded: expanded, pomodoro: pomodoro != nil,
                          focus: focus, tecladoBloqueado: TecladoBloqueado.shared.ativo)
    }

    var mode: Mode { contentState().mode }
    var isHovering: Bool { opening.hovering }
    var atrasoDeFechar: TimeInterval { typingNote ? NotchOpening.typingDelay : NotchOpening.closeDelay }
    private let notificationDuration: TimeInterval = 5.0
    /// O alerta do sistema vive ~30s; o card espelhado acompanha.
    private let actionableDuration: TimeInterval = 30.0
    private let hudDuration: TimeInterval = 1.5
    private var queue: [NotchNotification] = []
    private var dismissWork: DispatchWorkItem?
    private var hudWork: DispatchWorkItem?

    func fecharPorHoverOut() {
        guard !linkAberto && !editandoAgenda && !editandoLembretes && !monitoresArrastando else { return }
        setExpandedDirect(false)
    }

    func setHover(_ inside: Bool) {
        openingWork?.cancel()
        let now = ProcessInfo.processInfo.systemUptime
        // trocar de seção pode encolher o card e deixar o cursor do lado de
        // fora sem ele ter saído: a saída logo depois ganha o prazo longo, e
        // voltar o mouse pro card cancela o fechamento
        let settings = AppSettings.shared
        opening.hover(inside, typing: typingNote || now - focoTrocadoEm < 1, now: now,
                      openDelay: settings.notchAtrasoHover, openOnHover: !settings.notchAbrirComClique)
        guard let request = opening.pending else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  let value = self.opening.fire(request, now: ProcessInfo.processInfo.systemUptime,
                                                linkOpen: self.linkAberto || self.editandoAgenda || self.editandoLembretes || self.monitoresArrastando) else { return }
            self.applyExpanded(value)
        }
        openingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, request.deadline - ProcessInfo.processInfo.systemUptime),
                                      execute: work)
    }

    /// Gesto, drop e pedidos externos atravessam o mesmo caminho que o hover.
    func setExpandedDirect(_ value: Bool) {
        openingWork?.cancel()
        opening.setExpanded(value, now: ProcessInfo.processInfo.systemUptime)
        applyExpanded(value)
    }

    private func applyExpanded(_ value: Bool) {
        precondition(Thread.isMainThread, "Apresentação deve mudar na main thread")
        if value && !expanded {
            monitoresSelecionado = displayID
            agendaHoje()
            onAtualizarLembretes?()
        }
        // reabrir logo depois de fechar volta pra seção escolhida à mão
        if value && !expanded, focoPendente == nil, let (secao, quando) = focoAoFechar,
           ProcessInfo.processInfo.systemUptime - quando < Self.memoriaDoFoco {
            focoPendente = secao
        }
        if value && !expanded && receivedSections { reconcileSections() }
        if !value {
            if typingNote { QuickNote.shared.editing = false }
            monitoresArrastando = false
            mirrorOn = false
            focoAoFechar = focusLocked ? focus.map { ($0, ProcessInfo.processInfo.systemUptime) } : nil
            focusLocked = false
            focoPendente = nil
        }
        expanded = value
        if !value { resumePendingNotifications() }
    }

    func suspendPresentation() {
        openingWork?.cancel()
        opening.suspend()
        if typingNote { QuickNote.shared.editing = false }
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
        if activeNotification == nil, !protegeEdicao {
            show(notification)
        } else {
            queue.append(notification)
        }
    }

    /// Fim da digitação: solta a notificação que esperou. Chamado pela view
    /// quando `QuickNote.editing` cai (Esc, clique fora, interruptor desligado).
    func resumePendingNotifications() {
        guard activeNotification == nil, !protegeEdicao, !queue.isEmpty else { return }
        show(queue.removeFirst())
    }

    func dismissActiveNotification() {
        dismissWork?.cancel()
        activeNotification = nil
        notificationHeld = false
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
        notificationHeld = hovering
        if hovering {
            dismissWork?.cancel()
        } else {
            scheduleDismiss()
        }
    }

    private func show(_ notification: NotchNotification) {
        guard !protegeEdicao else { queue.insert(notification, at: 0); return }
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
        guard !protegeEdicao else { return }
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

    /// Conexão abre a ilha (~3 s); bateria baixa abre o card direto (~5 s).
    func showAirPods(_ reason: AirPodsAnnounce) {
        airpodsIsland = reason == .connected
        airpodsCard = reason == .lowBattery
        // cursor já em cima: vira card e espera a saída
        if airpodsHeld { airpodsIsland = false; airpodsCard = true; return }
        scheduleAirPodsDismiss(after: reason == .connected ? 3.0 : 5.0)
    }

    /// Cursor sobre a ilha promove para o card e segura o timer; ao sair,
    /// reagenda curto. Não passa pelo `setHover`: senão o card de música
    /// acordaria por baixo e assumiria quando os AirPods somem.
    func holdAirPods(_ hovering: Bool) {
        guard airpodsIsland || airpodsCard else { return }
        airpodsHeld = hovering
        if hovering {
            airpodsWork?.cancel()
            airpodsIsland = false
            airpodsCard = true
        } else {
            scheduleAirPodsDismiss(after: 1.0)
        }
    }

    func dismissAirPods() {
        airpodsWork?.cancel()
        airpodsHeld = false
        airpodsIsland = false
        airpodsCard = false
    }

    private func scheduleAirPodsDismiss(after duration: TimeInterval) {
        airpodsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissAirPods() }
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

    /// Texto da tela: o ícone na faixa só existe com a peça ligada.
    @Published var textoDaTelaLigado = false
    var onExtrairTexto: (() -> Void)?

}
