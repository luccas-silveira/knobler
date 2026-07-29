//
//  tools/main.swift — harness de snapshot do Knobler
//
//  Renderiza a NotchView em cada estado, offscreen, e salva PNGs em
//  Snapshots/. Uso: tools/snapshot.sh (compila e roda).
//  Serve pra validar o design visualmente antes de entregar.
//

import AppKit
import Network
import SwiftUI

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Snapshots"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// capa de disco fake (gradiente) pra simular artwork do Spotify
func fakeArtwork() -> NSImage {
    let size = NSSize(width: 300, height: 300)
    let image = NSImage(size: size)
    image.lockFocus()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.85, green: 0.35, blue: 0.30, alpha: 1),
        NSColor(calibratedRed: 0.25, green: 0.15, blue: 0.45, alpha: 1),
    ])!.draw(in: NSRect(origin: .zero, size: size), angle: -60)
    // "vinil" no centro só pra ter forma reconhecível
    NSColor.black.withAlphaComponent(0.35).setFill()
    NSBezierPath(ovalIn: NSRect(x: 90, y: 90, width: 120, height: 120)).fill()
    image.unlockFocus()
    return image
}

func fakeState(playing: Bool = true) -> MediaController.PlaybackState {
    .init(
        isPlaying: playing,
        title: "Paranoid Android",
        artist: "Radiohead",
        album: "OK Computer",
        duration: 386,
        position: 143,
        fetchedAt: Date(),
        artworkURL: nil
    )
}

struct Scenario {
    let name: String
    let realNotch: Bool
    let configure: @MainActor (NotchViewModel, MediaController, AskStore) -> Void
    let agentRequest: AgentRequest?
    let agentRequestExpanded: Bool
    let resolveAgentRequest: (AgentRequestAction, AgentRequestResponder)?
    let terminalFirstRace: Bool
    let frameHeight: CGFloat

    init(
        name: String,
        realNotch: Bool,
        agentRequest: AgentRequest? = nil,
        agentRequestExpanded: Bool = false,
        resolveAgentRequest: (AgentRequestAction, AgentRequestResponder)? = nil,
        terminalFirstRace: Bool = false,
        frameHeight: CGFloat = 240,
        configure: @escaping @MainActor (NotchViewModel, MediaController, AskStore) -> Void
    ) {
        self.name = name
        self.realNotch = realNotch
        self.agentRequest = agentRequest
        self.agentRequestExpanded = agentRequestExpanded
        self.resolveAgentRequest = resolveAgentRequest
        self.terminalFirstRace = terminalFirstRace
        self.frameHeight = frameHeight
        self.configure = configure
    }
}

/// Autoridade mínima da corrida do snapshot: a primeira chamada aceita, as
/// seguintes apenas registram a tentativa sem poder sobrescrever o vencedor.
@MainActor
final class SnapshotAgentArbiter {
    private(set) var winner: AgentRequestResult?
    private(set) var attempts: [AgentRequestResponder] = []

    func resolve(action: AgentRequestAction, responder: AgentRequestResponder) -> Bool {
        attempts.append(responder)
        guard winner == nil else { return false }
        winner = AgentRequestResult(action: action, responder: responder)
        return true
    }
}

// prateleira do cenário corrente (recriada por cenário no loop)
var currentShelf = ShelfStore()

func fakeShelfFiles() -> [URL] {
    let dir = FileManager.default.temporaryDirectory
    return ["Relatório.pdf", "foto.png", "notas.txt"].map { name in
        let url = dir.appendingPathComponent(name)
        try? "x".data(using: .utf8)?.write(to: url)
        return url
    }
}

let scenarios: [Scenario] = [
    Scenario(name: "closed-idle", realNotch: true) { _, _, _ in },
    Scenario(name: "closed-music", realNotch: true) { _, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
    },
    Scenario(name: "closed-music-external", realNotch: false) { _, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
    },
    // pausado: escondida (deve parecer ilha vazia, não miniatura)
    Scenario(name: "closed-paused-hidden", realNotch: false) { vm, media, _ in
        media.injectPreview(state: fakeState(playing: false), artwork: fakeArtwork())
        vm.musicPaused = true
    },
    // pausado + hover: espiada (asinhas com pontinhos)
    Scenario(name: "closed-paused-peek", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(playing: false), artwork: fakeArtwork())
        vm.musicPaused = true
        vm.peeking = true
    },
    Scenario(name: "hud-volume", realNotch: true) { vm, _, _ in
        vm.hud = .init(level: 0.6, muted: false)
    },
    Scenario(name: "hud-muted", realNotch: true) { vm, _, _ in
        vm.hud = .init(level: 0, muted: true)
    },
    Scenario(name: "hud-volume-external", realNotch: false) { vm, _, _ in
        vm.hud = .init(level: 0.6, muted: false)
    },
    Scenario(name: "hud-brightness", realNotch: true) { vm, _, _ in
        vm.hud = .init(kind: .brightness, level: 0.75)
    },
    Scenario(name: "hud-battery-charging", realNotch: true) { vm, _, _ in
        vm.hud = .init(kind: .battery, level: 0.74, charging: true)
    },
    Scenario(name: "hud-battery-low", realNotch: true) { vm, _, _ in
        vm.hud = .init(kind: .battery, level: 0.18, charging: false)
    },
    Scenario(name: "music-expanded", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.expanded = true
    },
    Scenario(name: "music-expanded-paused", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(playing: false), artwork: fakeArtwork())
        vm.expanded = true
    },
    // prateleira de arquivos no card expandido (com música junto)
    Scenario(name: "expanded-shelf", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        fakeShelfFiles().forEach { currentShelf.add($0) }
        vm.expanded = true
    },
    Scenario(name: "expanded-shelf-only", realNotch: true) { vm, _, _ in
        fakeShelfFiles().forEach { currentShelf.add($0) }
        vm.expanded = true
    },
    // atividade da API: anel na asinha (fechado) e linha no card (aberto)
    Scenario(name: "closed-activity", realNotch: false) { vm, _, _ in
        vm.activity = NotchActivity(
            id: "deploy", title: "Deploy zoi-studio", detail: "rsync…",
            progress: 0.42, updatedAt: Date())
    },
    Scenario(name: "closed-activity-music", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.activity = NotchActivity(
            id: "deploy", title: "Deploy zoi-studio", detail: "rsync…",
            progress: 0.42, updatedAt: Date())
    },
    Scenario(name: "expanded-activity-music", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.activity = NotchActivity(
            id: "deploy", title: "Deploy zoi-studio", detail: "rsync pra produção",
            progress: 0.42, updatedAt: Date())
        vm.expanded = true
    },
    Scenario(name: "expanded-activity-only", realNotch: true) { vm, _, _ in
        vm.activity = NotchActivity(
            id: "build", title: "Compilando Knobler", detail: "xcodebuild",
            progress: nil, updatedAt: Date())
        vm.expanded = true
    },
    Scenario(name: "notification", realNotch: true) { vm, _, _ in
        vm.activeNotification = NotchNotification(
            appName: "Finder",
            title: "Backup concluído",
            body: "O Time Machine terminou o backup de hoje às 14:32."
        )
    },
    Scenario(name: "expanded-history-empty", realNotch: true) { vm, _, _ in
        vm.expanded = true
        vm.historyOpen = true
    },
    Scenario(name: "expanded-history", realNotch: true) { vm, _, _ in
        let h = NotificationHistory.shared
        h.record(NotchNotification(appName: "Slack", title: "Ana Paula",
                                   body: "revisei o PR, pode subir"))
        h.record(NotchNotification(appName: "Knobler", title: "Deploy concluído",
                                   body: "produção · 2m14s"))
        h.record(NotchNotification(appName: "Lembretes", title: "Alongar",
                                   body: "a cada 50 min"))
        vm.expanded = true
        vm.historyOpen = true
    },
    Scenario(name: "dictation-recording", realNotch: true) { vm, _, _ in
        vm.dictation = .recording(level: 0.6)
    },
    Scenario(name: "dictation-transcribing", realNotch: true) { vm, _, _ in
        vm.dictation = .transcribing
    },
    Scenario(name: "dictation-error", realNotch: false) { vm, _, _ in
        vm.dictation = .error("Sem acesso ao microfone")
    },
    Scenario(name: "ask-simple", realNotch: true) { _, _, askStore in
        askStore.send(.enqueue(AskRequest(id: "s1", questions: [
            AskQuestion(
                question: "Qual abordagem seguir?", header: "Abordagem",
                multiSelect: false,
                options: [
                    AskOption(label: "Hook PreToolUse",
                              description: "Intercepta toda pergunta e envia pro notch",
                              preview: nil),
                    AskOption(label: "Servidor MCP",
                              description: "Tool dedicada configurada por projeto",
                              preview: nil),
                ])
        ], receivedAt: Date(timeIntervalSince1970: 1_000))))
    },
    Scenario(name: "ask-multiselect", realNotch: true) { _, _, askStore in
        askStore.send(.enqueue(AskRequest(id: "s2", questions: [
            AskQuestion(
                question: "Quais checagens rodar?", header: "Validação",
                multiSelect: true,
                options: [
                    AskOption(label: "Build Release", description: "xcodebuild", preview: nil),
                    AskOption(label: "Snapshots", description: "harness visual", preview: nil),
                    AskOption(label: "E2E manual", description: "roteiro no app real", preview: nil),
                ])
        ], receivedAt: Date(timeIntervalSince1970: 1_000))))
    },
    Scenario(name: "ask-preview", realNotch: true) { _, _, askStore in
        askStore.send(.enqueue(AskRequest(id: "s3", questions: [
            AskQuestion(
                question: "Qual layout do card?", header: "Layout",
                multiSelect: false,
                options: [
                    AskOption(label: "Split",
                              description: "opções + preview",
                              preview: "+----------+-----------+\n| opções   | preview   |\n|          |  ascii    |\n+----------+-----------+"),
                    AskOption(label: "Empilhado",
                              description: "preview embaixo",
                              preview: "+----------------------+\n|        opções        |\n+----------------------+\n|       preview        |\n+----------------------+"),
                ])
        ], receivedAt: Date(timeIntervalSince1970: 1_000))))
    },
    Scenario(name: "ask-paged", realNotch: true) { _, _, askStore in
        let request = AskRequest(id: "s4", questions: [
            AskQuestion(question: "Pergunta um?", header: "Um", multiSelect: false,
                        options: [AskOption(label: "A", description: "", preview: nil)]),
            AskQuestion(question: "Pergunta dois de três?", header: "Dois", multiSelect: false,
                        options: [
                            AskOption(label: "Sim", description: "segue", preview: nil),
                            AskOption(label: "Não", description: "para", preview: nil),
                        ]),
            AskQuestion(question: "Pergunta três?", header: "Três", multiSelect: false,
                        options: [AskOption(label: "B", description: "", preview: nil)]),
        ], receivedAt: Date(timeIntervalSince1970: 1_000))
        askStore.send(.enqueue(request))
        // O cenário permanece na página 1 por uma transição de domínio real.
        askStore.send(.submit(labels: ["A"], text: nil))
    },
    Scenario(
        name: "agent-permission-compact", realNotch: true,
        agentRequest: AgentRequest(
            id: "permission-compact", agent: .claude, kind: .permission,
            title: "Permissão de comando",
            summary: "Executar git status para conferir as alterações locais antes de preparar a revisão.",
            details: "command: git status --short\ncwd: /Users/luccassilveira/Desktop/Projetos/knobler",
            source: .terminal, actions: [.allow, .deny]
        )
    ) { _, _, _ in },
    Scenario(
        name: "agent-permission-expanded", realNotch: true,
        agentRequest: AgentRequest(
            id: "permission-expanded", agent: .codex, kind: .permission,
            title: "Aplicar alteração de arquivo",
            summary: "O agente quer atualizar o painel do notch com o card de aprovação.",
            details: "path: Knobler/NotchView.swift\n--- a/Knobler/NotchView.swift\n+++ b/Knobler/NotchView.swift\n+ AgentRequestCard(request: request)",
            source: .cli, actions: [.allow, .allowForSession, .deny]
        ),
        agentRequestExpanded: true,
        frameHeight: 360
    ) { _, _, _ in },
    Scenario(
        name: "agent-question", realNotch: true,
        agentRequest: AgentRequest(
            id: "question", agent: .claude, kind: .question,
            title: "Escolha uma abordagem",
            summary: "Como o agente deve continuar com a integração?",
            source: .ide, actions: [.option("Manter o fluxo atual"), .option("Usar a ponte local")]
        )
    ) { _, _, _ in },
    Scenario(
        name: "agent-request-race", realNotch: true,
        agentRequest: AgentRequest(
            id: "race", agent: .codex, kind: .permission,
            title: "Corrida de resolução", summary: "A resposta externa chegou primeiro.",
            source: .cli, actions: [.allow, .deny]
        ),
        terminalFirstRace: true
    ) { _, _, _ in },
    Scenario(name: "pomodoro-focus", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .focus, runState: .running, remaining: 23 * 60 + 14, completedFocus: 1, cyclesUntilLong: 4)
    },
    Scenario(name: "pomodoro-break", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .shortBreak, runState: .running, remaining: 4 * 60 + 32, completedFocus: 1, cyclesUntilLong: 4)
    },
    Scenario(name: "pomodoro-paused", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .focus, runState: .paused, remaining: 12 * 60 + 3, completedFocus: 1, cyclesUntilLong: 4)
    },
    Scenario(name: "pomodoro-waiting", realNotch: false) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .shortBreak, runState: .waiting, remaining: 5 * 60, completedFocus: 1, cyclesUntilLong: 4)
    },
    // pausa longa em espera NO NOTCH REAL: o rótulo mais comprido não pode
    // escorregar sob a câmera (asa esquerda ~85pt)
    Scenario(name: "pomodoro-waiting-long", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .longBreak, runState: .waiting, remaining: 15 * 60, completedFocus: 4, cyclesUntilLong: 4)
    },
    // card expandido (hover): foco/pausado/espera + confirmar que a música some
    Scenario(name: "pomodoro-card-focus", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .focus, runState: .running, remaining: 23 * 60 + 14, completedFocus: 1, cyclesUntilLong: 4)
        vm.expanded = true
    },
    Scenario(name: "pomodoro-card-paused", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .focus, runState: .paused, remaining: 12 * 60 + 3, completedFocus: 1, cyclesUntilLong: 4)
        vm.expanded = true
    },
    Scenario(name: "pomodoro-card-waiting", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .shortBreak, runState: .waiting, remaining: 5 * 60, completedFocus: 1, cyclesUntilLong: 4)
        vm.expanded = true
    },
    Scenario(name: "pomodoro-card-with-music", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.pomodoro = PomodoroState(phase: .focus, runState: .running, remaining: 23 * 60 + 14, completedFocus: 1, cyclesUntilLong: 4)
        vm.expanded = true
    },
    // AirPods: card de conexão (transitório), faixa junto da música,
    // card dedicado sem música, e aviso de bateria baixa.
    Scenario(name: "airpods-connect", realNotch: true) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-connect-external", realNotch: false) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-strip-music", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31)
        vm.expanded = true
    },
    Scenario(name: "airpods-card-nomusic", realNotch: true) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31)
        vm.expanded = true
    },
    Scenario(name: "airpods-low", realNotch: false) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 8, right: 74, case_: nil)
        vm.airpodsCard = true
    },
    // Update: card de versão nova e o estado de instalação.
    Scenario(name: "update-card", realNotch: true) { vm, _, _ in
        vm.update = .available(Release(
            version: "0.9.0",
            notes: "Fixed\nDitado não cai mais a cada release",
            url: URL(string: "https://github.com/luccas-silveira/knobler/releases/tag/v0.9.0")!,
            asset: nil))
        vm.updateCard = true
    },
    Scenario(name: "update-installing", realNotch: true) { vm, _, _ in
        vm.update = .installing
        vm.updateCard = true
    },
]

MainActor.assumeIsolated {
for scenario in scenarios {
    // ShelfStore() relê o UserDefaults — sem o clear, os arquivos fake de um
    // cenário vazavam pros seguintes
    currentShelf = ShelfStore()
    currentShelf.clear()
    let vm = NotchViewModel()
    let media = MediaController()
    let askStore = AskStore(dependencies: .init(
        resolve: { _, _ in },
        cancel: { _ in }
    ))
    let arbiter = scenario.terminalFirstRace ? SnapshotAgentArbiter() : nil
    let agentRequestStore = AgentRequestStore(
        resolveRemote: { _, action in
            guard let arbiter else { return false }
            return await MainActor.run { arbiter.resolve(action: action, responder: .nob) }
        },
        dismissRemote: { _ in }
    )
    media.injectPreview(state: nil, artwork: nil)
    vm.hasRealNotch = scenario.realNotch
    vm.notchSize = scenario.realNotch
        ? CGSize(width: 200, height: 32)
        : CGSize(width: 190, height: 30)
    scenario.configure(vm, media, askStore)
    if let request = scenario.agentRequest {
        agentRequestStore.send(.enqueue(request))
        if scenario.terminalFirstRace, let arbiter {
            precondition(arbiter.resolve(action: .deny, responder: .terminal))
            agentRequestStore.send(.resolve(id: request.id, action: .deny, responder: .terminal))
            var nobAccepted: Bool?
            Task { @MainActor in
                nobAccepted = await agentRequestStore.resolve(id: request.id, action: .allow)
            }
            let deadline = Date().addingTimeInterval(1)
            while nobAccepted == nil && RunLoop.current.run(mode: .default, before: deadline) && Date() < deadline {}
            precondition(nobAccepted == false)
            precondition(arbiter.attempts == [.terminal, .nob])
            precondition(arbiter.winner == AgentRequestResult(action: .deny, responder: .terminal))
            precondition(agentRequestStore.state.active == nil)
            precondition(agentRequestStore.state.results[request.id] == arbiter.winner)
            print("agent race: terminal deny won; NOB allow rejected")
        } else if let result = scenario.resolveAgentRequest {
            agentRequestStore.send(.resolve(id: request.id, action: result.0, responder: result.1))
        }
    }

    // wallpaper claro atrás: revela a silhueta e as bordas da forma
    let view = ZStack(alignment: .top) {
        LinearGradient(
            colors: [Color(red: 0.72, green: 0.78, blue: 0.88),
                     Color(red: 0.90, green: 0.86, blue: 0.80)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        NotchView(
            vm: vm, askStore: askStore, agentRequestStore: agentRequestStore,
            media: media, levels: SystemAudioLevels(), shelf: currentShelf,
            dropTargetsEnabled: false,
            agentRequestInitiallyExpanded: scenario.agentRequestExpanded)
    }
    .frame(width: 560, height: scenario.frameHeight)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2

    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        print("FALHOU: \(scenario.name)")
        exit(1)
    }
    let path = "\(outputDir)/\(scenario.name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("ok \(path)")
}

// Cenários de Mensagens LAN — precisam de LANMessaging/MessageStore no
// ambiente, que os demais cenários não usam.
@MainActor func renderMessageScenario(
    _ name: String, realNotch: Bool, frameHeight: CGFloat = 240,
    configure: (NotchViewModel, LANMessaging, MessageStore) -> Void
) {
    let vm = NotchViewModel()
    let media = MediaController()
    let askStore = AskStore(dependencies: .init(
        resolve: { _, _ in },
        cancel: { _ in }
    ))
    let agentRequestStore = AgentRequestStore(
        resolveRemote: { _, _ in false }, dismissRemote: { _ in }
    )
    media.injectPreview(state: nil, artwork: nil)
    let lan = LANMessaging()
    let store = MessageStore()
    vm.hasRealNotch = realNotch
    vm.notchSize = realNotch
        ? CGSize(width: 200, height: 32)
        : CGSize(width: 190, height: 30)
    configure(vm, lan, store)

    let view = ZStack(alignment: .top) {
        LinearGradient(
            colors: [Color(red: 0.72, green: 0.78, blue: 0.88),
                     Color(red: 0.90, green: 0.86, blue: 0.80)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    NotchView(
        vm: vm, askStore: askStore, agentRequestStore: agentRequestStore,
        media: media, levels: SystemAudioLevels(), shelf: currentShelf,
        dropTargetsEnabled: false)
            .environmentObject(lan)
            .environmentObject(store)
    }
    .frame(width: 560, height: frameHeight)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { print("FALHOU: \(name)"); exit(1) }
    let path = "\(outputDir)/\(name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("ok \(path)")
}

// Overlay do Descanso (bloqueio forçado) — render à parte, não usa NotchView.
@MainActor func renderOverlay(_ name: String, label: String, hold: Double) {
    let model = BreakOverlayModel()
    model.endDate = Date().addingTimeInterval(872)   // ~14:32 no contador
    model.label = label
    model.holdProgress = hold
    let view = ZStack {
        LinearGradient(
            colors: [Color(red: 0.72, green: 0.78, blue: 0.88),
                     Color(red: 0.90, green: 0.86, blue: 0.80)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        BreakOverlayView(model: model)
    }
    .frame(width: 560, height: 360)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { print("FALHOU: \(name)"); exit(1) }
    let path = "\(outputDir)/\(name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("ok \(path)")
}
// frameHeight maior que o padrão 240: o painel de Mensagens (chrome + 272,
// ver NotchView.currentSize case .music com tab == .messages) rende mais
// alto que os demais cenários e cortava embaixo com o frame default.
renderMessageScenario("messages-online", realNotch: true, frameHeight: 390) { vm, lan, _ in
    vm.expanded = true
    vm.tab = .messages
    lan.injectPreview(peers: [
        Peer(id: "p1", name: "Marina", endpoint: .hostPort(host: "127.0.0.1", port: 1)),
        Peer(id: "p2", name: "Diego", endpoint: .hostPort(host: "127.0.0.1", port: 2)),
    ])
}
renderMessageScenario("messages-incoming", realNotch: true) { vm, _, _ in
    vm.incoming = NotchViewModel.IncomingMessage(
        peerID: "p1", name: "Marina", text: "Bora almoçar daqui a pouco?", allowReply: true)
}

// settings-*.png e mapping-editor.png NÃO são gerados por este harness: o
// SettingsView usa NavigationSplitView e o MappingEditorView usa HSplitView,
// e nenhum dos dois renderiza via ImageRenderer offscreen neste toolchain —
// vira um ícone de "proibido" no lugar do conteúdo (confirmado com um repro
// mínimo: até um NavigationSplitView vazio quebra do mesmo jeito). Esses 9
// PNGs são capturados manualmente: rodar
//   Knobler.app/Contents/MacOS/Knobler --ajustes=<painel>
// (painéis: geral, notch, ditado, pomodoro, lembretes, descanso, webhooks,
// mensagens) e tirar o screenshot da janela real. mapping-editor.png sai de
// dentro do painel "webhooks" clicando "…" → "Mapear campos…" num perfil.

renderOverlay("descanso", label: "Almoço", hold: 0)
renderOverlay("descanso-hold", label: "Almoço", hold: 0.6)
}
