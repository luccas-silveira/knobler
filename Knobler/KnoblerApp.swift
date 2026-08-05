//
//  KnoblerApp.swift
//  Knobler — Dynamic Island para o notch do MacBook
//

import AppKit
import Combine
import Security
import SwiftUI

@main
@MainActor
enum KnoblerMain {
    static let delegate = AppDelegate()

    static func main() {
        // Modo provisionamento (cask postflight): baixa o modelo e sai, sem UI.
        if CommandLine.arguments.contains(DictationModelProvisioner.flag) {
            DictationModelProvisioner.runAndExit()
        }
        // Self-check headless do shim de exceção (sem UI): prova que o crash-proofing
        // do installTap funciona no binário compilado.
        // Diagnóstico de permissões (suporte remoto): imprime e sai, sem UI.
        if CommandLine.arguments.contains("--permissoes") {
            print(Permission.diagnostico())
            exit(0)
        }
        if CommandLine.arguments.contains("--selfcheck") {
            let ok = MicRecorder.exceptionGuardWorks()
                && DictationController._clipboardSelfCheck()
                && DictationController._flashSelfCheck()
                && DictationController._enginePolicySelfCheck()
                && DictationController._stopSelfCheck()
            print(ok ? "selfcheck: dictation OK" : "selfcheck: FALHOU")
            exit(ok ? 0 : 1)
        }
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct ScreenNotch {
        let window: NotchWindow
        let viewModel: NotchViewModel
    }

    private var notches: [CGDirectDisplayID: ScreenNotch] = [:]
    private var statusItem: NSStatusItem?
    private let media = MediaController()
    private var interceptor: NotificationInterceptor?
    private let volumeHUD = VolumeHUDController()
    private let audioLevels = SystemAudioLevels()
    private let battery = BatteryMonitor()
    private let bluetooth = BluetoothMonitor()
    private let micMonitor = MicMonitor()
    private let agentRequestToken = AppDelegate.makeAgentRequestToken()
    private lazy var apiServer = NotchAPIServer(agentRequestToken: agentRequestToken)
    // Única fonte de estado da feature Ask, compartilhada por todas as telas.
    private var askStore: AskStore?
    private var agentRequestStore: AgentRequestStore?
    private var lanCancellables = Set<AnyCancellable>()
    /// ponytail: `@EnvironmentObject` exige o tipo, não aceita opcional — sem a
    /// peça Mensagens instalada não há `MensagensServico`, então as views que
    /// recebem `.environmentObject(lanMessaging)`/`(messageStore)` ganham estas
    /// instâncias ociosas (nunca chamam `.start()`/populam nada sozinhas). A
    /// seção `mensagens` do card e o painel de Ajustes já somem sem a peça
    /// (F3), então nenhuma view de Mensagens de fato usa o que é injetado
    /// aqui. Teto: se uma 3ª peça precisar do mesmo truque, vale extrair um
    /// wrapper genérico em vez de duplicar o par de instâncias ociosas.
    private let lanMessagingOcioso = LANMessaging()
    private let messageStoreOcioso = MessageStore()
    /// ponytail: `SettingsView(webhookClient:)` exige o tipo, não aceita
    /// opcional — sem a peça Notificações externas instalada não há
    /// `WebhookClient` vivo. Mesmo truque do par acima: nunca chama
    /// `start()`, fica inerte (o painel `webhooks` já some da barra lateral
    /// sem a peça, F3).
    private let webhookClientOcioso = WebhookClient()
    private let devAvisos = DevAvisosController()
    /// Botões dos avisos do desenvolvedor: token do card → URLs (só https).
    /// Existe porque o `actionToken` normal resolve num `AXUIElement` vivo do
    /// interceptor, e um aviso vindo de JSON não tem banner nenhum atrás.
    private var avisoActionURLs: [UUID: [String]] = [:]
    private let calendar = CalendarCountdown()
    /// Reunião com link de call acontecendo agora (vem do `CalendarCountdown`).
    private var emReuniao = false
    /// Instante em que o microfone acendeu; `nil` = apagado. Vira "chamada em
    /// curso" depois do limiar de `NotificationRules.micIndicaChamada`.
    private var micDesde: Date?
    /// Quem sabe que peças estão instaladas e cria só essas. Peça desligada não
    /// tem objeto — é disso que o "custo zero" depende.
    private let plugins = PluginHost.shared
    /// `nil` = a peça Pomodoro está desinstalada. Todo uso daqui pra baixo passa
    /// por `?`, e é isso que faz o timer de 1 s não existir.
    private var pomodoro: Pomodoro? { plugins.servico(.pomodoro) }
    /// `nil` = a peça Lembretes está desinstalada.
    private var reminderScheduler: ReminderScheduler? { plugins.servico(.lembretes) }
    /// `nil` = a peça Descanso está desinstalada.
    private var descansoServico: DescansoServico? { plugins.servico(.descanso) }
    /// `nil` = a peça Mensagens está desinstalada.
    private var mensagensServico: MensagensServico? { plugins.servico(.mensagens) }
    /// `nil` = a peça Notificações externas está desinstalada.
    private var webhookClient: WebhookClient? { plugins.servico(.webhooks) }
    /// `nil` = a peça Ditado está desinstalada.
    private var dictation: DictationController? { plugins.servico(.ditado) }
    /// Pra `.environmentObject(_:)`: com a peça viva, os objetos do serviço;
    /// sem ela, as instâncias ociosas (ver comentário na declaração delas).
    private var lanMessagingParaInjetar: LANMessaging { mensagensServico?.lanMessaging ?? lanMessagingOcioso }
    private var messageStoreParaInjetar: MessageStore { mensagensServico?.messageStore ?? messageStoreOcioso }
    /// Botões de adiamento no card do lembrete. Dois: o "já já" e o "mais tarde".
    static let snoozeOptions: [(title: String, minutes: Int)] =
        [("Adiar 5 min", 5), ("30 min", 30)]
    private let descanso = DescansoController()
    private let annotation = AnnotationController.shared
    private let shelf = ShelfStore()
    private let screenshots = ScreenshotWatcher()
    private var screenshotPeekWork: DispatchWorkItem?
    private var apiCancellable: AnyCancellable?
    private var updaterCancellable: AnyCancellable?
    // Observa apenas o ciclo de vida da API para invalidar callbacks Ask obsoletos.
    private var askLocalAPICancellable: AnyCancellable?
    private var askPresentationGeneration: UInt64 = 0
    /// Evita reabrir o espelho a cada tick se o usuário fechou antes da call.
    private var mirrorAutoOpened = false

    // três fontes de atividade, em ordem de prioridade: envio de AirDrop (ação
    // que você acabou de disparar), API (explícita) e calendário (ambiente)
    private var apiActivity: NotchActivity?
    private var calendarActivity: NotchActivity?
    private var airdropActivity: NotchActivity?
    /// Espelha `pomodoro.runState != .idle` pra não recalcular a atividade a cada
    /// tique do timer — só quando ele começa ou para.
    private var pomodoroAtivo = false
    private var currentActivity: NotchActivity? {
        // com o Pomodoro na tela o evento já mora no card dele: publicar a
        // atividade também duplicaria a informação, e como ela se atualiza a cada
        // 30s a seção subiria ao topo sem parar, tirando o Pomodoro da frente.
        airdropActivity ?? apiActivity ?? (pomodoroAtivo ? nil : calendarActivity)
    }

    private func pushActivity() {
        let display = currentActivity
        notches.values.forEach { $0.viewModel.activity = display }
    }

    /// Envia por AirDrop mostrando o estado no notch: atividade
    /// **indeterminada** enquanto vai (o `NSSharingService` não expõe bytes
    /// transferidos — ver `AirDropState`) e card no fim.
    func airdropComEstado(_ urls: [URL]) {
        Sharing.airdrop(urls) { [weak self] in self?.aplicarEstadoAirDrop($0) }
    }

    private func aplicarEstadoAirDrop(_ state: AirDropState) {
        switch state {
        case .enviando(let label):
            airdropActivity = NotchActivity(
                id: "airdrop",
                title: "Enviando por AirDrop",
                detail: label,
                progress: nil,
                updatedAt: Date())
        case .enviado(let label):
            airdropActivity = nil
            publicar(NotchNotification(
                appName: "AirDrop", title: "Enviado", body: label, iconEmoji: "📤"))
        case .cancelado:
            airdropActivity = nil
        case .falhou(let motivo):
            airdropActivity = nil
            publicar(NotchNotification(
                appName: "AirDrop", title: "Não deu pra enviar", body: motivo,
                iconEmoji: "📤"))
        }
        pushActivity()
    }
    /// Empurra o lembrete pra daqui a `minutes`. Um `oneShot` já foi desligado
    /// pelo `onFire` quando o card apareceu — religa, senão o tick o ignoraria e
    /// o adiamento nunca venceria.
    private func snooze(_ reminder: Reminder, by minutes: Int) {
        if case .oneShot = reminder.schedule,
           let i = AppSettings.shared.reminders.firstIndex(where: { $0.id == reminder.id }) {
            AppSettings.shared.reminders[i].enabled = true
        }
        reminderScheduler?.snooze(reminder, minutes: minutes)
    }

    private var levelsCancellable: AnyCancellable?
    private var pausedCancellable: AnyCancellable?

    // gesto de swipe no notch (monitor local de scroll)
    private var scrollMonitor: Any?
    private var scrollAccumX: CGFloat = 0
    private var scrollAccumY: CGFloat = 0
    private var scrollActed = false
    /// Gesto que COMEÇOU com uma lista rolável no card rola a lista, não age
    /// no notch. Sem isso, o mesmo puxão seguiria trocando a seção em foco.
    private var scrollStartedInHistory = false
    /// Timestamp e zona do último evento de scroll — é com eles que
    /// `NotchGesture.isGestureStart` reconhece começo de gesto sem `.began`
    /// (mouse de rodinha) ou de gesto que entrou arrastando na zona.
    private var lastScrollAt: TimeInterval = 0
    private var lastScrollInZone = false
    private var scrollStartedInLink = false

    // ilha simulada nos monitores sem notch físico
    private static let simulatedNotchSize = CGSize(width: 190, height: 30)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nenhuma permissão é pedida no launch: quem pede Acessibilidade é o
        // painel Permissões, aberto depois da janela de boas-vindas — duas
        // janelas disputando foco foi o bug que criou o asyncAfter original.
        // Até lá o interceptor de notificação e o gatilho do ditado ficam
        // mudos, mas os três consumidores repolam o trust a cada 3 s e se
        // religam sozinhos, sem relaunch. Não recoloque o prompt aqui.
        #if DEBUG
        Permission._selfCheck()
        #endif
        configureAskFeature()
        configureAgentRequestFeature()
        observeAskLifecycle()

        setupStatusItem()
        placeWindows()

        // notificações aparecem em TODAS as telas, como os HUDs
        let interceptor = NotificationInterceptor { [weak self] notch in
            self?.publicar(notch)
        }
        interceptor.start()
        self.interceptor = interceptor


        // HUDs são estado global do sistema: aparecem em TODAS as telas
        volumeHUD.onHUD = { [weak self] state in
            self?.notches.values.forEach { $0.viewModel.showHUD(state) }
        }
        // o health-check do tap já sonda a Acessibilidade a cada 3s: o badge
        // pega carona em vez de abrir um timer só pra ele
        volumeHUD.onAXTrust = { [weak self] _ in self?.refreshAccessibilityBadge() }
        volumeHUD.start()

        // ditado: gancho global (a ⌥ direita é do VolumeHUD, feature de
        // fábrica — não é plugin→plugin, ver `DitadoEfeitos` em
        // `Plugin.swift`). Sem a peça instalada `dictation` é `nil` e o
        // encaminhamento vira no-op sozinho.
        volumeHUD.onRightOption = { [weak self] pressed in
            self?.dictation?.rightOptionChanged(pressed)
        }

        // capturas de tela entram na prateleira e o notch dá um peek
        screenshots.onScreenshot = { [weak self] url in
            guard let self else { return }
            self.shelf.add(url)
            self.peekShelf()
        }

        battery.onEvent = { [weak self] level, charging in
            guard AppSettings.shared.batteryAlerts else { return }
            self?.notches.values.forEach {
                $0.viewModel.showHUD(
                    .init(kind: .battery, level: level, charging: charging),
                    duration: 2.5
                )
            }
        }
        battery.start()

        // AirPods: card no connect + faixa de bateria enquanto conectado.
        // start()/stop() ficam no sink de settings (reage ao toggle).
        bluetooth.onAnnounce = { [weak self] ap in
            self?.notches.values.forEach {
                $0.viewModel.airpods = ap
                $0.viewModel.showAirPodsCard()
            }
        }
        bluetooth.onUpdate = { [weak self] ap in
            self?.notches.values.forEach { $0.viewModel.airpods = ap }
        }
        bluetooth.onDisconnect = { [weak self] in
            self?.notches.values.forEach {
                $0.viewModel.airpods = nil
                $0.viewModel.airpodsCard = false
            }
        }

        // Atualizações: o Updater publica, o notch reflete. O card só abre uma
        // vez por versão — "Depois" grava a dispensada e o aviso fica só nos Ajustes.
        Updater.shared.automatic = AppSettings.shared.checkForUpdates
        updaterCancellable = Updater.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.notches.values.forEach { notch in
                    notch.viewModel.update = state
                    notch.viewModel.updateCanInstall = Updater.shared.canInstall
                    switch state {
                    case .available:
                        notch.viewModel.updateCard = !Updater.shared.isSkipped
                    case .installing, .failed:
                        notch.viewModel.updateCard = true
                    case .none:
                        notch.viewModel.updateCard = false
                    }
                }
            }
        Updater.shared.start()

        // Avisos do desenvolvedor: JSON público a cada 24 h. Passa pelo
        // `publicar` como qualquer coisa vinda de fora — logo respeita o
        // silêncio de reunião, inclusive o crítico (silenciar não descarta: o
        // card está no Histórico quando a call acabar).
        devAvisos.ligadoProvider = { AppSettings.shared.avisosDoDesenvolvedor }
        devAvisos.onAviso = { [weak self] aviso in
            guard let self else { return }
            // som antes do publicar: em reunião o card não aparece, e um bipe
            // sem card na tela é pior que silêncio
            let card = self.notificacao(de: aviso)
            self.publicar(card)
            if aviso.som, !self.silenciando {
                NSSound(named: "Pop")?.play()   // mesmo som do webhook
            }
        }
        devAvisos.start()

        // pontinho laranja enquanto algum app usa o microfone
        micMonitor.onChange = { [weak self] inUse in
            guard let self else { return }
            // marca desde quando está aceso — o gate de silêncio só considera
            // chamada depois do limiar
            self.micDesde = inUse ? (self.micDesde ?? Date()) : nil
            let show = inUse && AppSettings.shared.micIndicator
            self.notches.values.forEach { $0.viewModel.micInUse = show }
        }
        micMonitor.start()

        // tap de áudio só enquanto o player ativo toca (visualizador reativo real);
        // reavaliado quando o player muda e quando o toggle muda nos Ajustes
        levelsCancellable = media.$state
            .map { _ in () }
            .merge(with: AppSettings.shared.objectWillChange.map { _ in () })
            .sink { [weak self] in
                DispatchQueue.main.async { self?.updateAudioTap() }
            }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // pausado, a música se esconde do notch (peek no hover)
        pausedCancellable = media.$state
            .map { $0 != nil && $0?.isPlaying != true }
            .removeDuplicates()
            .sink { [weak self] paused in
                self?.notches.values.forEach { $0.viewModel.musicPaused = paused }
            }

        setupSwipeGestures()

        // API local: scripts publicam cards no notch (diferencial do Knobler)
        apiServer.onNotification = { [weak self] notification in
            self?.publicar(notification)
        }
        // atividade é global: aparece em todos os monitores
        apiServer.onActivity = { [weak self] activity in
            self?.apiActivity = activity
            self?.pushActivity()
        }
        calendar.onActivity = { [weak self] activity in
            self?.calendarActivity = activity
            self?.pushActivity()
        }
        calendar.onNextEvent = { [weak self] aviso in
            self?.notches.values.forEach { $0.viewModel.calendarAviso = aviso }
        }
        calendar.onMeeting = { [weak self] emReuniao in
            self?.emReuniao = emReuniao
        }
        // A montagem do Pomodoro mora na ficha da peça (`montarPomodoro`, em
        // Plugin.swift). Aqui ficam só os efeitos que passam por AppKit —
        // ajustes, telas, som e o overlay do Descanso.
        plugins.pomodoroEfeitos = PomodoroEfeitos(
            config: { AppSettings.shared.pomodoroConfig },
            publicarEstado: { [weak self] state in
                self?.notches.values.forEach { $0.viewModel.pomodoro = state }
            },
            atividadeMudou: { [weak self] ativo in
                self?.pomodoroAtivo = ativo
                self?.pushActivity()
            },
            fimDeFase: { [weak self] ended, next in
                guard let self else { return }
                let (title, body) = Self.pomodoroNotice(ended: ended, next: next)
                // uma notificação só, montada FORA do laço: o id é um UUID novo a
                // cada init, então uma por tela viraria N linhas no histórico (o
                // dedupe do record() é por id). Os outros pontos de entrada já
                // montam assim.
                let notice = NotchNotification(appName: "Pomodoro", title: title, body: body)
                self.notches.values.forEach { $0.viewModel.enqueue(notice) }
                if AppSettings.shared.pomodoroSound { NSSound(named: "Glass")?.play() }
            },
            // Travar a tela nas pausas do Pomodoro (opt-in): o mesmo overlay do
            // Descanso, pela duração da pausa que acabou de começar a rodar.
            // Fala com o SERVIÇO (`plugins.servico(.descanso)`), não com uma
            // referência fixa — sem a peça instalada, `montarPomodoro` já nem
            // chama este efeito (`deps.instalado(.descanso)`, Plugin.swift).
            pausaComecou: { [weak self] dur in
                guard AppSettings.shared.pomodoroLockScreen else { return }
                self?.descansoServico?.begin(label: "Pausa do Pomodoro", duration: dur)
            })
        // A montagem dos Lembretes mora na ficha da peça (`montarLembretes`, em
        // Plugin.swift). Aqui ficam só os efeitos que passam por AppKit — os
        // itens, o card + som do disparo, e o registro do wake.
        plugins.lembretesEfeitos = LembretesEfeitos(
            itens: { AppSettings.shared.reminders },
            disparou: { [weak self] r in
                guard let self else { return }
                // fora do laço pelo mesmo motivo do Pomodoro: uma notificação por
                // tela teria um id diferente cada e empilharia N linhas iguais no
                // histórico
                let card = NotchNotification(
                    appName: nil, title: r.title, body: r.body, openURL: r.openURL,
                    // token = id do lembrete: o card oferece "Adiar" sem abrir Ajustes
                    actionTitles: Self.snoozeOptions.map(\.title), actionToken: r.id)
                self.notches.values.forEach { $0.viewModel.enqueue(card) }
                if let sound = r.soundName { NSSound(named: NSSound.Name(sound))?.play() }
            },
            desligarUmaVez: { r in
                if let i = AppSettings.shared.reminders.firstIndex(where: { $0.id == r.id }) {
                    AppSettings.shared.reminders[i].enabled = false
                }
            },
            registrarWake: { tick in
                // Wake: NSWorkspace.didWakeNotification é postado no notificationCenter
                // do NSWorkspace, NÃO no default — observar no center errado = handler mudo.
                let token = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
                ) { _ in tick() }
                return { NSWorkspace.shared.notificationCenter.removeObserver(token) }
            })
        // A montagem do Descanso mora na ficha da peça (`montarDescanso`,
        // Plugin.swift). Aqui ficam só os efeitos que passam por AppKit — o
        // overlay (`DescansoController`, compartilhado com a pausa do
        // Pomodoro) e o registro do wake.
        plugins.descansoEfeitos = DescansoEfeitos(
            itens: { AppSettings.shared.screenBreaks },
            iniciarBloqueio: { [weak self] label, dur in
                self?.descanso.begin(label: label, duration: dur)
            },
            pararBloqueioSeAtivo: { [weak self] in
                guard let self, self.descanso.isActive else { return }
                self.descanso.abort()
            },
            estaAtivo: { [weak self] in self?.descanso.isActive ?? false },
            desligarUmaVez: { b in
                if let i = AppSettings.shared.screenBreaks.firstIndex(where: { $0.id == b.id }) {
                    AppSettings.shared.screenBreaks[i].enabled = false
                }
            },
            registrarWake: { tick in
                let token = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
                ) { _ in tick() }
                return { NSWorkspace.shared.notificationCenter.removeObserver(token) }
            })
        // A montagem de Mensagens mora na ficha da peça (`montarMensagens`,
        // Plugin.swift). Aqui ficam só os efeitos que passam por AppSettings/
        // AppKit/SwiftUI — o perfil próprio, o card + busca de avatar quando
        // uma mensagem chega, e o observer de nome/foto mudado nos Ajustes.
        plugins.mensagensEfeitos = MensagensEfeitos(
            perfilProprio: { AppSettings.shared.myProfile() },
            mensagemChegou: { [weak self] msg, profile, media in
                guard let self, let servico = self.mensagensServico else { return }
                let name = profile?.name ?? servico.messageStore.name(for: msg.peerID) ?? "?"
                servico.messageStore.rememberName(name, for: msg.peerID)
                var msg = msg
                msg.mediaFile = media.flatMap { servico.messageStore.saveMedia($0.0, ext: $0.1.ext) }
                servico.messageStore.append(msg)
                let mediaHeight = msg.mediaFile.flatMap { servico.messageStore.mediaURL($0) }
                    .map { MessageMedia.cardHeight($0) } ?? 0
                self.notches.values.forEach {
                    $0.viewModel.showIncoming(.init(peerID: msg.peerID, name: name,
                                                    text: msg.text, allowReply: msg.allowReply,
                                                    mediaFile: msg.mediaFile,
                                                    mediaHeight: mediaHeight))
                }
                if let peer = servico.lanMessaging.peer(withID: msg.peerID) {
                    servico.lanMessaging.fetchProfile(from: peer) { prof in
                        if let jpeg = prof?.avatarJPEG {
                            servico.messageStore.cacheAvatar(jpeg, for: msg.peerID)
                        } else if prof != nil {
                            // perfil veio sem foto = o peer removeu; fetch falho (nil) não apaga
                            servico.messageStore.removeAvatar(for: msg.peerID)
                        }
                    }
                }
            },
            registrarMudancaNome: { tick in
                // trocar nome/foto nos Ajustes re-anuncia o Bonjour (nome novo na lista dos outros)
                let cancellable = AppSettings.shared.$displayName
                    .dropFirst()
                    .sink { _ in tick() }
                return { cancellable.cancel() }
            })
        // A montagem de Notificações externas mora na ficha da peça
        // (`montarWebhooks`, Plugin.swift). Aqui ficam só o card quando a
        // notificação chega e o observer do ajuste opt-in
        // (`webhookNotifications`), que exigem AppKit/Combine.
        plugins.webhooksEfeitos = WebhooksEfeitos(
            notificacaoChegou: { [weak self] notification in
                self?.publicar(notification)
            },
            ativado: { AppSettings.shared.webhookNotifications },
            registrarMudancaAjuste: { tick in
                let cancellable = AppSettings.shared.$webhookNotifications
                    .dropFirst()
                    .sink { _ in tick() }
                return { cancellable.cancel() }
            })
        // A montagem do Ditado mora na ficha da peça (`montarDitado`,
        // Plugin.swift), mas ao contrário das outras o `nascer` inteiro é
        // emprestado daqui — `DictationController` importa FluidAudio, que o
        // `plugincheck` (swiftc avulso) não resolve (ver o `ponytail:` em
        // `DitadoEfeitos`, Plugin.swift).
        plugins.ditadoEfeitos = DitadoEfeitos(nascer: { [weak self] in
            guard let self else { return nil }
            let d = DictationController()
            d.onState = { [weak self] phase in
                self?.notches.values.forEach { $0.viewModel.dictation = phase }
            }
            d.destinationProvider = { [weak self] in
                if let id = self?.askStore?.state.active?.id {
                    return .ask(id: id)
                }
                guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
                    return nil
                }
                return .application(pid: pid)
            }
            d.transcriptSink = { [weak self] text, destination in
                guard case .ask(let id) = destination,
                      self?.askStore?.state.active?.id == id else {
                    return false
                }
                self?.askStore?.send(.appendText(id: id, text: text))
                return true
            }
            d.start()
            return d
        })
        // A montagem do Desenho mora na ficha da peça (`montarAnotacao`,
        // Plugin.swift), mas ao contrário das outras o `nascer` inteiro é
        // emprestado daqui — `AnnotationController` é AppKit puro e é
        // `.shared` (singleton: as views o consomem direto, converter em
        // peça não vira instância). Ligar é `start()`; o `PluginServico` é o
        // próprio singleton, cujo `parar()` (`AnnotationController.swift`)
        // desliga o tap, o observer de tela e os painéis por display.
        plugins.anotacaoEfeitos = AnotacaoEfeitos(nascer: {
            AnnotationController.shared.start()
            return AnnotationController.shared
        })
        // O nascimento das peças instaladas. Quem está desligado nem é visitado.
        plugins.subir()
        // espelho automático: abre 2min antes da call, fecha quando ela começa
        calendar.onMirrorMoment = { [weak self] imminent in
            guard let self else { return }
            if imminent, AppSettings.shared.mirrorBeforeMeetings, !self.mirrorAutoOpened {
                self.mirrorAutoOpened = true
                if let vm = self.viewModelUnderMouse() {
                    MirrorController.activate(on: vm, expand: true)
                }
            } else if !imminent, self.mirrorAutoOpened {
                self.mirrorAutoOpened = false
                self.notches.values.forEach {
                    guard $0.viewModel.mirrorOn else { return }
                    $0.viewModel.mirrorOn = false
                    $0.viewModel.setExpandedDirect(false)
                }
            }
        }
        calendar.start()

        apiServer.onMirror = { [weak self] on in
            guard let self else { return }
            if on {
                if let vm = self.viewModelUnderMouse() {
                    MirrorController.activate(on: vm, expand: true)
                }
            } else {
                self.notches.values.forEach {
                    guard $0.viewModel.mirrorOn else { return }
                    $0.viewModel.mirrorOn = false
                    $0.viewModel.setExpandedDirect(false)
                }
            }
        }

        apiServer.statusProvider = { [weak self] in
            var status = self?.volumeHUD.diagnostics ?? [:]
            status["annotation"] = self?.annotation.diagnostics ?? [:]
            status["visualizerTapped"] = self?.tappedBundleID ?? "none"
            status["player"] = self?.media.activeBundleID ?? "none"
            status.merge(MirrorController.shared.diagnostics) { _, new in new }
            status["micInUse"] = self?.micMonitor.isRunning ?? false
            status["silenciando"] = self?.silenciando ?? false
            status["notches"] = (self?.notches ?? [:]).map { id, notch in
                let mode: NotchViewModel.Mode = self?.askStore?.state.active != nil
                    || self?.agentRequestStore?.state.active != nil
                    ? .question : notch.viewModel.mode
                return [
                    "display": Int(id),
                    "mode": "\(mode)",
                    // qual seção o card está mostrando — dá pra um script
                    // perguntar o que o notch tem na cara agora
                    "focus": notch.viewModel.focus?.rawValue ?? "",
                    "hasNotification": notch.viewModel.activeNotification != nil,
                    "visible": notch.window.isVisible,
                    "frame": "\(notch.window.frame)",
                ] as [String: Any]
            }
            status["dictation"] = self?.dictation?.diagnostics ?? [:]
            status["ask"] = self?.apiServer.askDiagnostics ?? [:]
            status["agentRequests"] = self?.apiServer.agentRequestDiagnostics ?? [:]
            status["lanMessaging"] = self?.mensagensServico?.lanMessaging.diagnostics ?? [:]
            // uma pergunta só em vez de descobrir batendo em rota
            status["plugins"] = PluginID.allCases
                .filter(PluginHost.shared.estaInstalado)
                .map(\.rawValue)
            return status
        }
        apiCancellable = AppSettings.shared.objectWillChange
            .prepend(())
            .sink { [weak self] in
                DispatchQueue.main.async {
                    if AppSettings.shared.localAPI {
                        self?.apiServer.start()
                    } else {
                        self?.clearAskPresentation()
                        self?.apiServer.stop()
                    }
                    if AppSettings.shared.screenshotsToShelf {
                        self?.screenshots.start()
                    } else {
                        self?.screenshots.stop()
                    }
                    if AppSettings.shared.airpodsNotch {
                        self?.bluetooth.start()
                    } else {
                        self?.bluetooth.stop()
                    }
                    Updater.shared.automatic = AppSettings.shared.checkForUpdates
                    // o aviso depende do toggle do ditado, não só da permissão
                    self?.refreshAccessibilityBadge()
                    // indicador de mic é persistente: re-publica quando o toggle muda
                    self?.micMonitor.publish()
                    // OSD nativo suprimido enquanto algum HUD nosso estiver ativo
                    let hudsOn = AppSettings.shared.volumeHUD || AppSettings.shared.brightnessHUD
                    // preview do print some só se o shelf captura E o toggle está on
                    let hidePreview = AppSettings.shared.screenshotsToShelf
                        && AppSettings.shared.hideScreenshotPreview
                    DispatchQueue.global(qos: .utility).async {
                        hudsOn ? OSDSuppressor.suppress() : OSDSuppressor.restore()
                        hidePreview ? ScreenshotPreviewSuppressor.suppress()
                                    : ScreenshotPreviewSuppressor.restore()
                    }
                }
            }

        // atalho de desenvolvimento: abre os Ajustes direto (screenshots de UI).
        // "--ajustes" ou "--ajustes=<painel>" (ex.: --ajustes=pomodoro)
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--ajustes") }) {
            let pane = arg.split(separator: "=").last
                .flatMap { SettingsPane(rawValue: String($0)) }
            showSettings(pane: pane)
        } else if CommandLine.arguments.contains("--boas-vindas") {
            // modo de captura: mostra tudo e não grava nada
            mostrarBoasVindas(paraVersao: 0, gravando: false)
        } else {
            apresentarBoasVindasSeNecessario()
        }
    }

    /// O app é LSUIElement: sem janela e sem ícone no Dock, quem instala não tem
    /// onde procurar nem o app nem as permissões. A janela de boas-vindas conta
    /// isso na primeira abertura; o painel Permissões vem logo depois que ela
    /// fecha, e é ele quem pede Acessibilidade.
    ///
    /// Passo novo numa versão futura reabre a janela só com ele — quem já viu o
    /// resto não revê (ver `Onboarding.versaoAtual`).
    private func apresentarBoasVindasSeNecessario() {
        // Saúde da instalação é problema de agora, não novidade: vai direto pro
        // painel, sem passar pelo wizard nem pelo versionamento.
        if Permission.installIssue != nil {
            showSettings(pane: .permissoes)
            return
        }
        let vista = Onboarding.versaoVista()
        guard !Onboarding.visiveis(paraVersao: vista).isEmpty else { return }
        // Permissões só na primeira execução de verdade: quem só está vendo um
        // passo novo já passou por esse painel.
        mostrarBoasVindas(paraVersao: vista, gravando: true, depoisPermissoes: vista == 0)
    }

    private var onboardingWindow: NSWindow?
    private var onboardingObserver: NSObjectProtocol?

    private func mostrarBoasVindas(paraVersao vista: Int,
                                   gravando: Bool,
                                   depoisPermissoes: Bool = false) {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Bem-vindo ao Knobler"
            window.contentView = NSHostingView(rootView: OnboardingView(
                passos: Onboarding.visiveis(paraVersao: vista),
                mostrarNovidade: vista > 0,
                aoConcluir: { [weak window] in window?.close() },
                aoIgnorar: { [weak window] in window?.close() }
            )
            // O NSHostingView adota o fitting size do conteúdo e o setContentSize
            // abaixo não o segura: sem esta moldura a janela nasce com milhares
            // de pontos de altura (o texto de cada linha se estica sem limite).
            .frame(width: 800, height: 520))
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 800, height: 520))
            window.center()
            onboardingWindow = window
            // Nenhuma janela do projeto tem delegate: o X e os dois botões caem
            // todos aqui, e a versão é gravada num lugar só.
            onboardingObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if let obs = self.onboardingObserver {
                    NotificationCenter.default.removeObserver(obs)
                }
                self.onboardingObserver = nil
                self.onboardingWindow = nil
                // No modo de captura (--boas-vindas) tirar print não pode
                // queimar o onboarding da máquina.
                guard gravando else { return }
                Onboarding.marcarVisto()
                if depoisPermissoes { self.showSettings(pane: .permissoes) }
            }
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Porta de volta: quem pede de propósito quer ver tudo.
    @objc private func openOnboarding() {
        mostrarBoasVindas(paraVersao: 0, gravando: true)
    }

    /// Compõe o domínio Ask com o gateway HTTP antes que o listener possa
    /// receber requisições. O store e os callbacks são registrados de forma
    /// síncrona na Main Actor, antes de qualquer chamada a apiServer.start();
    /// as closures capturam o servidor fracamente para não formar ciclo.
    private func configureAskFeature() {
        guard askStore == nil else { return }

        let server = apiServer
        askStore = AskStore(
            dependencies: .init(
                // O servidor mantém API síncrona e o adaptador async apenas
                // atende ao contrato de efeitos do AskStore.
                resolve: { [weak server] id, answers in
                    server?.resolveAsk(id: id, answers: answers)
                },
                cancel: { [weak server] id in
                    _ = server?.cancelAsk(id: id)
                }
            )
        )

        // Perguntas do Claude Code entram uma única vez no store compartilhado.
        apiServer.onAsk = { [weak self] request in
            guard let self else { return }
            let generation = self.askPresentationGeneration
            Task { @MainActor [weak self] in
                guard let self,
                      self.askPresentationGeneration == generation,
                      AppSettings.shared.localAPI
                else { return }
                NSSound(named: "Pop")?.play()  // uma vez, na chegada
                self.askStore?.send(.enqueue(request))
            }
        }
        apiServer.onAskDismiss = { [weak self] id in
            guard let self else { return }
            let generation = self.askPresentationGeneration
            Task { @MainActor [weak self] in
                guard let self,
                      self.askPresentationGeneration == generation,
                      AppSettings.shared.localAPI
                else { return }
                self.askStore?.send(.externalDismiss(id: id))
            }
        }
    }

    /// Cria o segredo da sessão antes de o listener aceitar conexões. Ele não
    /// vai para defaults, logs ou saída do CLI; adaptadores locais leem o arquivo.
    private static func makeAgentRequestToken() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            NSLog("knobler api: não gerou token de solicitações")
            return nil
        }
        let token = Data(bytes).base64EncodedString()
        do {
            let manager = FileManager.default
            let support = try manager.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("Knobler", isDirectory: true)
            try manager.createDirectory(
                at: support, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let tokenURL = support.appendingPathComponent("agent-request-token")
            try Data(token.utf8).write(to: tokenURL, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
            return token
        } catch {
            NSLog("knobler api: não gravou token de solicitações: \(error.localizedDescription)")
            return nil
        }
    }

    /// Espelha o domínio autenticado no store compartilhado. O servidor é a
    /// autoridade para a corrida; o reducer só apresenta o vencedor.
    private func configureAgentRequestFeature() {
        guard agentRequestStore == nil else { return }
        let server = apiServer
        agentRequestStore = AgentRequestStore(
            resolveRemote: { [weak server] id, action in
                server?.resolveAgentRequest(id: id, action: action, responder: .nob) ?? false
            },
            dismissRemote: { [weak server] id in
                _ = server?.dismissAgentRequest(id: id, responder: .nob)
            }
        )
        apiServer.onAgentRequest = { [weak self] request in
            guard AppSettings.shared.localAPI else { return }
            self?.agentRequestStore?.send(.enqueue(request))
        }
        apiServer.onAgentRequestResolved = { [weak self] id, action, responder in
            self?.agentRequestStore?.send(.resolve(id: id, action: action, responder: responder))
        }
        apiServer.onAgentRequestExpired = { [weak self] id in
            self?.agentRequestStore?.send(.expire(id: id))
        }
    }

    /// Invalida callbacks Ask já entregues quando a API local é desligada ou
    /// ligada novamente. O subscription é mantido separado do observador geral
    /// de settings porque só mudanças reais em `localAPI` devem avançar a geração.
    private func observeAskLifecycle() {
        askLocalAPICancellable = AppSettings.shared.$localAPI
            .removeDuplicates()
            .dropFirst()
            .sink { @MainActor [weak self] _ in
                self?.askPresentationGeneration &+= 1
            }
    }

    /// O servidor limpa seus pendingAsks ao parar, mas não emite dismiss.
    /// Limpa somente o store compartilhado, sem fan-out por monitor.
    private func clearAskPresentation() {
        guard let askStore else { return }
        let ids = ([askStore.state.active?.id] + askStore.state.queue.map(\.id)).compactMap { $0 }
        for id in ids {
            askStore.send(.externalDismiss(id: id))
        }
    }

    /// Liga/desliga o tap conforme o estado atual — idempotente, barato.
    private var tappedBundleID: String?
    private func updateAudioTap() {
        let wanted: String? = (AppSettings.shared.liveAudioVisualizer
            && media.state?.isPlaying == true) ? media.activeBundleID : nil
        guard wanted != tappedBundleID else { return }
        tappedBundleID = wanted
        audioLevels.stop()
        if let wanted,
           let app = NSRunningApplication.runningApplications(
               withBundleIdentifier: wanted).first {
            audioLevels.start(pid: app.processIdentifier)
        }
    }

    // MARK: - Swipe no notch

    /// Dois dedos sobre o notch: pra baixo abre a música, pra cima fecha,
    /// horizontal pula/volta faixa (como o Dynamic Island).
    private func setupSwipeGestures() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak self] event in
            self?.handleScroll(event) ?? event
        }
        // drag das miniaturas do shelf via monitor (o hit-testing do SwiftUI
        // engole eventos de mouse nas NSViews embutidas do notch)
        ShelfDragMonitor.shared.start()
    }

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
        else { return event }
        let id = Self.displayID(of: screen)
        guard let vm = notches[id]?.viewModel else { return event }

        // zona do gesto: o notch fechado ou o card aberto. Os dois eixos moram
        // no NotchGesture, que é testável sem NSEvent — é ele que sabe somar a
        // folga de hover e aguentar a altura ainda não publicada
        let expanded = vm.mode == .music
        let inZone = NotchGesture.naZonaHorizontal(mouseX: mouse.x,
                                                   screenMidX: screen.frame.midX,
                                                   expanded: expanded)
            && NotchGesture.inZone(mouseY: mouse.y,
                                   screenMaxY: screen.frame.maxY,
                                   expanded: expanded,
                                   alturaAtual: vm.alturaAtual,
                                   notchHeight: vm.notchSize.height)
        guard inZone else {
            // um gesto que entra arrastando na zona precisa saber que o evento
            // anterior estava fora — é o que o faz contar como gesto novo
            lastScrollInZone = false
            return event
        }

        // o reset vem antes de tudo: um gesto que começa precisa resincronizar
        // o próprio estado mesmo que o card tenha fechado por fora (o
        // setHover fecha sozinho quando o mouse sai), senão a flag velha
        // engole o gesto novo inteiro
        let novoGesto = NotchGesture.isGestureStart(
            began: event.phase == .began,
            momentum: !event.momentumPhase.isEmpty,
            sinceLastEvent: event.timestamp - lastScrollAt,
            previousInZone: lastScrollInZone,
            hasPhase: !event.phase.isEmpty || !event.momentumPhase.isEmpty)
        lastScrollAt = event.timestamp
        lastScrollInZone = true

        if novoGesto {
            scrollAccumX = 0
            scrollAccumY = 0
            scrollActed = false
            // handoff só quando há de fato uma lista rolável na tela: com a
            // nota ligada ou com o histórico vazio a seção não tem ScrollView
            // nenhuma, e entregar o eixo vertical a ela mataria o gesto — sem
            // abrir e sem fechar
            scrollStartedInHistory = vm.focus == .historico
                && !NotificationHistory.shared.items.isEmpty
                && !QuickNote.shared.hosted(by: id)
            // a página do link rola sozinha: o vertical é dela, senão a primeira
            // rolada fecharia o card em cima do que o usuário foi ler
            scrollStartedInLink = vm.focus == .link && LinkPreview.shared.hosted(by: id)
        }

        // histórico em foco: o vertical é da lista, pra ela rolar de verdade —
        // inclusive a inércia, que chega depois dos dedos saírem e por isso
        // não passa pelo reset acima
        if scrollStartedInHistory || scrollStartedInLink,
           abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) {
            return event
        }

        // inércia não conta como gesto; ainda assim é engolida na zona
        guard event.momentumPhase.isEmpty else { return nil }

        scrollAccumX += event.scrollingDeltaX
        scrollAccumY += event.scrollingDeltaY

        // vertical: alvo é função do acumulado, então recuar dentro do mesmo
        // gesto desfaz. Idempotente — aplicar o mesmo alvo duas vezes não custa.
        if let target = NotchGesture.verticalTarget(accumY: scrollAccumY, accumX: scrollAccumX) {
            switch target {
            case .closed:
                vm.setExpandedDirect(false)
            case .expanded:
                vm.setExpandedDirect(true)
            }
        } else if !scrollActed, abs(scrollAccumX) > 50 {
            scrollActed = true
            if expanded {
                // card aberto: horizontal anda um passo na faixa de seções —
                // inclusive saindo da nota. Soltar a trava do `editing` é do
                // `focar`, que todo caminho de troca de seção atravessa. Sair
                // da seção não encerra a nota: `active` e `text` seguem
                // intactos, e o ícone continua na faixa pra voltar.
                withAnimation(.easeOut(duration: 0.22)) {
                    vm.focarVizinho(avancando: scrollAccumX < 0)
                }
            } else if media.state != nil {
                if scrollAccumX < 0 { media.nextTrack() } else { media.previousTrack() }
            }
        }
        return nil // engole o scroll na zona — a janela de trás não rola junto
    }

    @objc private func screensChanged() {
        placeWindows()
    }

    /// Expande o card mostrando a prateleira por 1,5s e fecha. Pergunta ou
    /// ditado na tela têm prioridade → só adiciona, sem peek. Nova captura
    /// renova o timer; mouse em cima segura: o fechamento pula quem está sob o cursor.
    private func peekShelf() {
        let busy = notches.values.contains {
            $0.viewModel.dictation != nil
        } || askStore?.state.active != nil || agentRequestStore?.state.active != nil
        guard !busy else { return }

        notches.values.forEach { $0.viewModel.setExpandedDirect(true) }
        screenshotPeekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            // não fecha o que o usuário está usando: mouse sobre o notch mantém
            // aberto; o hover-exit fecha depois, pela via normal do setHover
            self?.notches.values.forEach {
                guard !$0.viewModel.isHovering else { return }
                $0.viewModel.setExpandedDirect(false)
            }
        }
        screenshotPeekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Notificações e HUD vão pro monitor onde o mouse está (onde está a atenção).
    private func viewModelUnderMouse() -> NotchViewModel? {
        let mouse = NSEvent.mouseLocation
        let target = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        return target.flatMap { notches[Self.displayID(of: $0)]?.viewModel }
            ?? notches.values.first?.viewModel
    }

    // ponytail: janela sempre no tamanho expandido máximo; o SwiftUI desenha só o
    // necessário. Redimensionar NSWindow durante animação é fonte de jank.
    private func placeWindows() {
        guard let askStore, let agentRequestStore else { return }
        var seen = Set<CGDirectDisplayID>()

        for screen in NSScreen.screens {
            let id = Self.displayID(of: screen)
            seen.insert(id)

            let notch: ScreenNotch
            if let existing = notches[id] {
                notch = existing
            } else {
                let viewModel = NotchViewModel()
                viewModel.displayID = id
                viewModel.restaurarFocoSalvo()
                let panel = NotchWindow(
                    contentRect: .zero,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.contentView = NSHostingView(
                    rootView: NotchView(
                        vm: viewModel, askStore: askStore, agentRequestStore: agentRequestStore,
                        media: media, levels: audioLevels, shelf: shelf,
                        onKeyboardEligibilityChanged: { [weak panel] active in
                            panel?.allowsKeyboard = active
                            if !active, panel?.isKeyWindow == true { panel?.resignKey() }
                        })
                        .environmentObject(lanMessagingParaInjetar)
                        .environmentObject(messageStoreParaInjetar)
                        .environmentObject(AppSettings.shared))
                notch = ScreenNotch(window: panel, viewModel: viewModel)
                notches[id] = notch

                // botão do card → adia o lembrete (token = id dele) ou, quando o
                // token é de um alerta interceptado, aciona o botão real do sistema.
                // Nos dois casos o card sai de todas as telas.
                viewModel.onNotificationAction = { [weak self] token, index in
                    guard let self else { return }
                    if let urls = self.avisoActionURLs.removeValue(forKey: token) {
                        // só https chega aqui (DevAvisos.saneadas), mas a guarda
                        // fica: é o último ponto antes de abrir o navegador
                        if urls.indices.contains(index), let url = URL(string: urls[index]),
                           url.scheme?.lowercased() == "https" {
                            NSWorkspace.shared.open(url)
                        }
                    } else if let reminder = AppSettings.shared.reminders.first(where: { $0.id == token }),
                       Self.snoozeOptions.indices.contains(index) {
                        self.snooze(reminder, by: Self.snoozeOptions[index].minutes)
                    } else {
                        self.interceptor?.perform(token: token, index: index)
                    }
                    self.notches.values.forEach { $0.viewModel.dismissActiveNotification() }
                }
                viewModel.onAirDrop = { [weak self] urls in
                    self?.airdropComEstado(urls)
                }

                // controles do card do Pomodoro → engine (onState reprograma todas as vms)
                viewModel.onPomodoroPause = { [weak self] in self?.pomodoro?.pause() }
                viewModel.onPomodoroResume = { [weak self] in self?.pomodoro?.resume() }
                viewModel.onPomodoroSkip = { [weak self] in self?.pomodoro?.skip() }
                viewModel.onPomodoroReset = { [weak self] in self?.pomodoro?.reset() }
                viewModel.onPomodoroStartNext = { [weak self] in self?.pomodoro?.startNext() }
                viewModel.onPomodoroSettings = { [weak self] in
                    self?.showSettings(pane: .pomodoro)
                }

                // resposta rápida do card → envia, grava o outgoing e some em todas as telas
                viewModel.onSendReply = { [weak self] peerID, text in
                    guard let self, let servico = self.mensagensServico,
                          let peer = servico.lanMessaging.peer(withID: peerID) else { return }
                    servico.lanMessaging.send(text, to: peer, allowReply: true) { ok in
                        servico.messageStore.append(PeerMessage(id: UUID().uuidString, peerID: peerID,
                            incoming: false, text: text, allowReply: true, at: Date(), delivered: ok))
                    }
                    self.notches.values.forEach { $0.viewModel.dismissIncoming() }
                }
                // fechar o card (X) ou abrir a conversa fecha em TODAS as telas
                viewModel.onDismissEverywhere = { [weak self] in
                    self?.notches.values.forEach { $0.viewModel.dismissIncoming() }
                }

                // botões do card de atualização
                viewModel.onUpdateInstall = {
                    // Sem brew e sem asset instalável o botão diz "Ver release"
                    // — e é isso que ele tem que fazer.
                    if Updater.shared.canInstall {
                        Updater.shared.install()
                    } else if let url = Updater.shared.releaseURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                viewModel.onUpdateSkip = { [weak self] in
                    Updater.shared.skipCurrent()
                    self?.notches.values.forEach { $0.viewModel.updateCard = false }
                }
                // Rede Local: liga o Bonjour quando Mensagens entra em foco no card
                // (app ativo → prompt num momento sensato). start() é idempotente.
                viewModel.$focus
                    .filter { $0 == .mensagens }
                    .sink { [weak self] _ in self?.mensagensServico?.lanMessaging.start() }
                    .store(in: &lanCancellables)

            }

            notch.viewModel.notchSize = Self.notchSize(of: screen)
            notch.viewModel.hasRealNotch = screen.safeAreaInsets.top > 0
            notch.viewModel.musicPaused =
                media.state != nil && media.state?.isPlaying != true
            notch.viewModel.activity = currentActivity

            // altura comporta o card com espelho; área transparente não intercepta cliques
            let size = NSSize(width: 700, height: 520)
            let frame = NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            )
            notch.window.setFrame(frame, display: true)
            notch.window.orderFrontRegardless()
        }

        // remove janelas de monitores desconectados
        for (id, notch) in notches where !seen.contains(id) {
            // a nota mora numa tela só: se foi essa que sumiu, desliga junto —
            // senão ela fica `active` (com o tique no menu) hospedada num
            // display que não existe mais, invisível e sem jeito de fechar
            if QuickNote.shared.hosted(by: id) { QuickNote.shared.active = false }
            notch.window.orderOut(nil)
            notches.removeValue(forKey: id)
        }
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    private static func notchSize(of screen: NSScreen) -> CGSize {
        let height = screen.safeAreaInsets.top
        guard height > 0 else { return simulatedNotchSize }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return CGSize(width: right.minX - left.maxX, height: height)
        }
        return CGSize(width: 200, height: max(height, 32))
    }

    /// Título/corpo da notificação de fim de fase, conforme o que acabou e o que vem.
    private static func pomodoroNotice(ended: PomodoroPhase,
                                       next: PomodoroPhase) -> (String, String) {
        let s = AppSettings.shared
        switch next {
        case .focus:
            return ("Pausa acabou", "Bora focar — \(s.pomodoroFocus) min")
        case .shortBreak:
            return ("Foco concluído", "Hora da pausa — \(s.pomodoroShortBreak) min")
        case .longBreak:
            return ("Foco concluído", "Pausa longa — \(s.pomodoroLongBreak) min")
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.statusImage()
        item.button?.imagePosition = .imageLeading
        item.button?.title = Self.statusTitle(needsAccessibility: needsAccessibility)
        let menu = NSMenu()
        menu.delegate = self   // itens do Pomodoro reconstroem a cada abertura
        item.menu = menu
        statusItem = item
    }

    /// Ditado ligado mas sem Acessibilidade = falha 100% silenciosa: o CGEventTap
    /// nem é criado, a ⌥ direita nunca chega e nada no app reage. A pílula do
    /// launch passa despercebida, então o ícone da barra fica marcado até conceder.
    private var needsAccessibility: Bool {
        AppSettings.shared.dictation && !AXIsProcessTrusted()
    }

    /// A marca do produto (a mesma silhueta do site) na barra. Desenhada aqui
    /// em vez de virar asset: a forma já existe em código e um PNG a mais
    /// significaria manter dois tamanhos em sincronia à mão.
    ///
    /// `isTemplate` é o que faz o ícone acompanhar claro/escuro e o realce do
    /// menu aberto — sem isso ele fica preto sobre preto na barra escura.
    static func statusImage() -> NSImage {
        let size = NSSize(width: 18, height: 18 * 9 / 22)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let path = NotchShape(topCornerRadius: rect.width * 3 / 22,
                                  bottomCornerRadius: rect.width * 5 / 22)
                .path(in: rect)
            ctx.addPath(path.cgPath)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Só o aviso: a marca vem da imagem ao lado. Vazio some da barra.
    static func statusTitle(needsAccessibility: Bool) -> String {
        needsAccessibility ? " ⚠" : ""
    }

    private func refreshAccessibilityBadge() {
        statusItem?.button?.title = Self.statusTitle(needsAccessibility: needsAccessibility)
    }

    /// Vai pro painel de Permissões, não direto pro Ajustes do Sistema: lá o
    /// usuário lê o que quebrou e por quê antes de sair do app.
    @objc private func openAccessibilityPane() {
        showSettings(pane: .permissoes)
    }

    // MARK: - Menu (reconstruído por estado do Pomodoro)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if needsAccessibility {
            let it = menu.addItem(withTitle: "⚠ Ditado precisa de Acessibilidade…",
                                  action: #selector(openAccessibilityPane), keyEquivalent: "")
            it.target = self
            menu.addItem(.separator())
        }
        // sem a peça instalada não há linha de Pomodoro nenhuma no menu
        if let pomodoro {
            let s = AppSettings.shared
            switch pomodoro.runState {
            case .idle:
                addPomodoroItem(menu, "▶ Iniciar foco (\(s.pomodoroFocus) min)", #selector(pomStart))
            case .running:
                addPomodoroItem(menu, "⏸ Pausar", #selector(pomPause))
                addPomodoroItem(menu, "⏭ Pular fase", #selector(pomSkip))
                addPomodoroItem(menu, "↺ Resetar", #selector(pomReset))
            case .paused:
                addPomodoroItem(menu, "▶ Retomar", #selector(pomResume))
                addPomodoroItem(menu, "⏭ Pular fase", #selector(pomSkip))
                addPomodoroItem(menu, "↺ Resetar", #selector(pomReset))
            case .waiting:
                let mins = Int(Pomodoro.duration(of: pomodoro.phase,
                                                 config: s.pomodoroConfig) / 60)
                let label = pomodoro.phase == .focus
                    ? "▶ Iniciar foco (\(mins) min)"
                    : "▶ Iniciar pausa (\(mins) min)"
                addPomodoroItem(menu, label, #selector(pomStartNext))
                addPomodoroItem(menu, "↺ Resetar", #selector(pomReset))
            }
            menu.addItem(.separator())
        }
        // a anotação inteira (ligar, ferramentas, cores, fundo) mora na seção
        // Anotação do card — o menu não duplica nada disso.
        let nota = menu.addItem(
            withTitle: "✎ Nota rápida", action: #selector(toggleQuickNote), keyEquivalent: "")
        nota.target = self
        nota.state = QuickNote.shared.active ? .on : .off
        let picker = menu.addItem(
            withTitle: "◉ Selecionar cor…", action: #selector(pickColor), keyEquivalent: "")
        picker.target = self
        // ponto de envio que não passa pela prateleira: mandar um arquivo não
        // devia obrigar a arrastá-lo pro notch antes
        let airdrop = menu.addItem(
            withTitle: "↗ Enviar por AirDrop…", action: #selector(sendAirDrop), keyEquivalent: "")
        airdrop.target = self
        menu.addItem(.separator())
        let boasVindas = menu.addItem(
            withTitle: "Boas-vindas…", action: #selector(openOnboarding), keyEquivalent: "")
        boasVindas.target = self
        let settings = menu.addItem(
            withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Knobler",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func addPomodoroItem(_ menu: NSMenu, _ title: String, _ sel: Selector) {
        let it = menu.addItem(withTitle: title, action: sel, keyEquivalent: "")
        it.target = self
    }

    /// Interruptor da nota. Ligar abre o card na hora — esperar o hover
    /// depois de escolher no menu seria um passo a mais sem motivo.
    ///
    /// A nota tem UMA tela dona: a que estava sob o mouse quando ligou. Só ela
    /// abre e só ela fecha. Sem dono, ligar expandia todos os monitores e nada
    /// os recolhia — o hover-out precisa de um hover-in anterior, e depois do
    /// menu o ponteiro está no item da barra, não sobre o card. Ficaria um
    /// notch aberto pra sempre, que o PRODUCT.md proíbe.
    @objc private func toggleQuickNote() {
        let note = QuickNote.shared
        if note.active {
            let host = note.hostDisplayID
            note.active = false  // didSet limpa texto, editing e o dono
            if let host, let vm = notches[host]?.viewModel { vm.setExpandedDirect(false) }
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen, let vm = notches[Self.displayID(of: screen)]?.viewModel else { return }
        note.hostDisplayID = Self.displayID(of: screen)
        // A trava do `recalcularSecoes` é `typingNote` (= hospedada E editando), e
        // neste instante o `TextEditor` ainda nem entrou na árvore — `editing` é
        // false. Sem pedir o foco aqui, o card abriria no Histórico ou na Música
        // (a nota é a última da ordem padrão) e o painel tomaria a janela-chave
        // sem campo nenhum focado: teclas engolidas em silêncio.
        //
        // A ordem destas três linhas é load-bearing: `note.active = true` vira
        // o `hasNota` que a `AberturaDoCard` capturou, e é esse valor já
        // atualizado que o `recalcularSecoes` disparado pelo
        // `onChange(of: expanded)` lê. Ligar a nota DEPOIS de expandir faria o
        // recálculo rodar sem a seção nota na lista — o pedido de foco esperaria
        // um recálculo que só o `onChange(of: hasNota)` traria depois.
        vm.focoPendente = .nota
        note.active = true
        vm.setExpandedDirect(true)
    }

    /// Manda a notificação pras telas — ou, em reunião, só pro histórico.
    ///
    /// Só passa por aqui o que chega **de fora**: app interceptado, API local e
    /// webhook. Pomodoro, lembretes e conta-gotas continuam indo direto ao
    /// `enqueue`, porque são coisas que *você* agendou — engoli-las seria perder
    /// o alarme que você mesmo pediu, não filtrar ruído.
    ///
    /// Silenciar nunca descarta: o `record` roda igual, e o card silenciado está
    /// na seção Histórico quando a reunião acabar.
    private func publicar(_ notification: NotchNotification) {
        guard silenciando else {
            notches.values.forEach { $0.viewModel.enqueue(notification) }
            return
        }
        NotificationHistory.shared.record(notification)
    }

    /// Silêncio em curso: reunião no calendário, ou microfone aceso há tempo o
    /// bastante pra ser uma chamada. Cada gatilho tem o seu interruptor.
    ///
    /// ponytail: o ditado do próprio Knobler também acende o microfone, e não há
    /// código aqui pra descontar isso — ele dura segundos, fica abaixo do limiar,
    /// e mesmo se passasse o card iria pro Histórico do mesmo jeito.
    private var silenciando: Bool {
        let settings = AppSettings.shared
        if emReuniao, settings.silenciarEmReuniao { return true }
        return settings.silenciarComMicrofone
            && NotificationRules.micIndicaChamada(desde: micDesde, agora: Date())
    }

    /// Aviso do desenvolvedor → card. O `actionToken` aqui não é o handle do
    /// interceptor: é só a chave que liga os botões deste card às URLs em
    /// `avisoActionURLs`. O card só renderiza botão quando há token
    /// (`NotchView.swift:1401`), então sem ação não geramos nenhum.
    private func notificacao(de aviso: Aviso) -> NotchNotification {
        let token = aviso.acoes.isEmpty ? nil : UUID()
        if let token {
            // teto de segurança: cada aviso deixa uma entrada, e só o clique a
            // consome. Sem isto um feed rajado vazaria memória devagar.
            if avisoActionURLs.count > 20 { avisoActionURLs.removeAll() }
            avisoActionURLs[token] = aviso.acoes.map(\.url)
        }
        return NotchNotification(
            appName: "Knobler",
            title: aviso.titulo,
            body: aviso.corpo,
            iconEmoji: aviso.iconEmoji ?? (aviso.critico ? "🚨" : "📣"),
            actionTitles: aviso.acoes.map(\.titulo),
            actionToken: token,
            actionURLs: aviso.acoes.map(\.url),
            // mesmo id substitui em vez de empilhar, igual ao webhook
            webhookID: "aviso:\(aviso.id)")
    }

    /// Conta-gotas: lupa nativa, HEX no clipboard, card no notch com os outros
    /// formatos. Cancelar (Esc) não mostra nada.
    @objc private func pickColor() {
        ColorPicker.pick(format: .hex) { [weak self] color in
            guard let self, let color else { return }
            let notification = NotchNotification(
                appName: "Knobler",
                title: "\(ColorPicker.hex(color)) copiado",
                body: ColorPicker.detail(color, copied: .hex),
                iconColor: color)
            self.notches.values.forEach { $0.viewModel.enqueue(notification) }
        }
    }

    @objc private func sendAirDrop() {
        Sharing.airdropFromPanel { [weak self] in self?.aplicarEstadoAirDrop($0) }
    }

    @objc private func pomStart() { pomodoro?.start() }
    @objc private func pomStartNext() { pomodoro?.startNext() }
    @objc private func pomPause() { pomodoro?.pause() }
    @objc private func pomResume() { pomodoro?.resume() }
    @objc private func pomSkip() { pomodoro?.skip() }
    @objc private func pomReset() { pomodoro?.reset() }

    // Cmd+Q escapa do quiosque (não é coberto pelas flags) → recusar enquanto trava.
    // Sem a peça Descanso instalada não há serviço, logo não há veto — nunca
    // há overlay em curso pra travar o quit (005/comportamento esperado).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (descansoServico?.isActive ?? false) ? .terminateCancel : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // a nota morre com o app; desligar aqui é o que joga o texto no
        // clipboard antes (o didSet de `active`) em vez de sumir com ele
        QuickNote.shared.active = false
        // devolve o OSD nativo — sem o Knobler o usuário fica sem HUD nenhum
        OSDSuppressor.restore()
        // devolve o preview do print (senão ficaria sem preview E sem shelf)
        ScreenshotPreviewSuppressor.restore()
        // fecha o socket de push e libera os recursos do relay; sem a peça
        // instalada não há o que fechar (nada nasceu)
        webhookClient?.parar()
        // grava o histórico de mensagens e desliga o Bonjour da Rede Local —
        // é o mesmo par que `MensagensServico.parar()` faz; sem a peça
        // instalada não há o que gravar/desligar (nada nasceu).
        mensagensServico?.parar()
        // o das notificações também: o debounce de 1s não sobrevive ao quit
        NotificationHistory.shared.flush()
    }

    private var settingsWindow: NSWindow?
    private let settingsRouter = SettingsRouter()

    @objc private func openSettings() { showSettings(pane: nil) }

    private func showSettings(pane: SettingsPane?) {
        // sheet aberto (ex.: MappingEditor com edições) → não trocar o painel,
        // senão o detalhe é recriado e o sheet morre levando o que foi digitado
        if let pane, settingsWindow?.attachedSheet == nil { settingsRouter.pane = pane }
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Ajustes do Knobler"
            window.contentView = NSHostingView(
                rootView: SettingsView(router: settingsRouter,
                                        webhookClient: webhookClient ?? webhookClientOcioso)
                    // o painel Permissões liga o Bonjour pra sondar a Rede local
                    .environmentObject(lanMessagingParaInjetar))
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 800, height: 520))
            window.contentMinSize = NSSize(width: 720, height: 470)
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
