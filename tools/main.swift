//
//  tools/main.swift — harness de snapshot do Knobler
//
//  Renderiza a NotchView em cada estado, offscreen, e salva PNGs em
//  Snapshots/. Uso: tools/snapshot.sh (compila e roda).
//  Serve pra validar o design visualmente antes de entregar.
//

import AppKit
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
    let configure: (NotchViewModel, MediaController) -> Void
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
    Scenario(name: "closed-idle", realNotch: true) { _, _ in },
    Scenario(name: "closed-music", realNotch: true) { _, media in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
    },
    Scenario(name: "closed-music-external", realNotch: false) { _, media in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
    },
    // pausado: escondida (deve parecer ilha vazia, não miniatura)
    Scenario(name: "closed-paused-hidden", realNotch: false) { vm, media in
        media.injectPreview(state: fakeState(playing: false), artwork: fakeArtwork())
        vm.musicPaused = true
    },
    // pausado + hover: espiada (asinhas com pontinhos)
    Scenario(name: "closed-paused-peek", realNotch: true) { vm, media in
        media.injectPreview(state: fakeState(playing: false), artwork: fakeArtwork())
        vm.musicPaused = true
        vm.peeking = true
    },
    Scenario(name: "hud-volume", realNotch: true) { vm, _ in
        vm.hud = .init(level: 0.6, muted: false)
    },
    Scenario(name: "hud-muted", realNotch: true) { vm, _ in
        vm.hud = .init(level: 0, muted: true)
    },
    Scenario(name: "hud-volume-external", realNotch: false) { vm, _ in
        vm.hud = .init(level: 0.6, muted: false)
    },
    Scenario(name: "hud-brightness", realNotch: true) { vm, _ in
        vm.hud = .init(kind: .brightness, level: 0.75)
    },
    Scenario(name: "hud-battery-charging", realNotch: true) { vm, _ in
        vm.hud = .init(kind: .battery, level: 0.74, charging: true)
    },
    Scenario(name: "hud-battery-low", realNotch: true) { vm, _ in
        vm.hud = .init(kind: .battery, level: 0.18, charging: false)
    },
    Scenario(name: "music-expanded", realNotch: true) { vm, media in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.expanded = true
    },
    Scenario(name: "music-expanded-paused", realNotch: true) { vm, media in
        media.injectPreview(state: fakeState(playing: false), artwork: fakeArtwork())
        vm.expanded = true
    },
    // prateleira de arquivos no card expandido (com música junto)
    Scenario(name: "expanded-shelf", realNotch: true) { vm, media in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        fakeShelfFiles().forEach { currentShelf.add($0) }
        vm.expanded = true
    },
    Scenario(name: "expanded-shelf-only", realNotch: true) { vm, _ in
        fakeShelfFiles().forEach { currentShelf.add($0) }
        vm.expanded = true
    },
    // atividade da API: anel na asinha (fechado) e linha no card (aberto)
    Scenario(name: "closed-activity", realNotch: false) { vm, _ in
        vm.activity = NotchActivity(
            id: "deploy", title: "Deploy zoi-studio", detail: "rsync…",
            progress: 0.42, updatedAt: Date())
    },
    Scenario(name: "closed-activity-music", realNotch: true) { vm, media in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.activity = NotchActivity(
            id: "deploy", title: "Deploy zoi-studio", detail: "rsync…",
            progress: 0.42, updatedAt: Date())
    },
    Scenario(name: "expanded-activity-music", realNotch: true) { vm, media in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.activity = NotchActivity(
            id: "deploy", title: "Deploy zoi-studio", detail: "rsync pra produção",
            progress: 0.42, updatedAt: Date())
        vm.expanded = true
    },
    Scenario(name: "expanded-activity-only", realNotch: true) { vm, _ in
        vm.activity = NotchActivity(
            id: "build", title: "Compilando Knobler", detail: "xcodebuild",
            progress: nil, updatedAt: Date())
        vm.expanded = true
    },
    Scenario(name: "notification", realNotch: true) { vm, _ in
        vm.activeNotification = NotchNotification(
            appName: "Finder",
            title: "Backup concluído",
            body: "O Time Machine terminou o backup de hoje às 14:32."
        )
    },
    Scenario(name: "dictation-recording", realNotch: true) { vm, _ in
        vm.dictation = .recording(level: 0.6)
    },
    Scenario(name: "dictation-transcribing", realNotch: true) { vm, _ in
        vm.dictation = .transcribing
    },
    Scenario(name: "dictation-error", realNotch: false) { vm, _ in
        vm.dictation = .error("Sem acesso ao microfone")
    },
    Scenario(name: "ask-simple", realNotch: true) { vm, _ in
        vm.ask = AskRequest(id: "s1", questions: [
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
        ], receivedAt: Date())
    },
    Scenario(name: "ask-multiselect", realNotch: true) { vm, _ in
        vm.ask = AskRequest(id: "s2", questions: [
            AskQuestion(
                question: "Quais checagens rodar?", header: "Validação",
                multiSelect: true,
                options: [
                    AskOption(label: "Build Release", description: "xcodebuild", preview: nil),
                    AskOption(label: "Snapshots", description: "harness visual", preview: nil),
                    AskOption(label: "E2E manual", description: "roteiro no app real", preview: nil),
                ])
        ], receivedAt: Date())
    },
    Scenario(name: "ask-preview", realNotch: true) { vm, _ in
        vm.ask = AskRequest(id: "s3", questions: [
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
        ], receivedAt: Date())
    },
    Scenario(name: "ask-paged", realNotch: true) { vm, _ in
        vm.ask = AskRequest(id: "s4", questions: [
            AskQuestion(question: "Pergunta um?", header: "Um", multiSelect: false,
                        options: [AskOption(label: "A", description: "", preview: nil)]),
            AskQuestion(question: "Pergunta dois de três?", header: "Dois", multiSelect: false,
                        options: [
                            AskOption(label: "Sim", description: "segue", preview: nil),
                            AskOption(label: "Não", description: "para", preview: nil),
                        ]),
            AskQuestion(question: "Pergunta três?", header: "Três", multiSelect: false,
                        options: [AskOption(label: "B", description: "", preview: nil)]),
        ], receivedAt: Date())
        vm.askPage = 1
    },
    Scenario(name: "pomodoro-focus", realNotch: true) { vm, _ in
        vm.pomodoro = PomodoroState(phase: .focus, runState: .running, remaining: 23 * 60 + 14, completedFocus: 1, cyclesUntilLong: 4)
    },
    Scenario(name: "pomodoro-break", realNotch: true) { vm, _ in
        vm.pomodoro = PomodoroState(phase: .shortBreak, runState: .running, remaining: 4 * 60 + 32, completedFocus: 1, cyclesUntilLong: 4)
    },
    Scenario(name: "pomodoro-paused", realNotch: true) { vm, _ in
        vm.pomodoro = PomodoroState(phase: .focus, runState: .paused, remaining: 12 * 60 + 3, completedFocus: 1, cyclesUntilLong: 4)
    },
    Scenario(name: "pomodoro-waiting", realNotch: false) { vm, _ in
        vm.pomodoro = PomodoroState(phase: .shortBreak, runState: .waiting, remaining: 5 * 60, completedFocus: 1, cyclesUntilLong: 4)
    },
    // pausa longa em espera NO NOTCH REAL: o rótulo mais comprido não pode
    // escorregar sob a câmera (asa esquerda ~85pt)
    Scenario(name: "pomodoro-waiting-long", realNotch: true) { vm, _ in
        vm.pomodoro = PomodoroState(phase: .longBreak, runState: .waiting, remaining: 15 * 60, completedFocus: 4, cyclesUntilLong: 4)
    },
    // card expandido (hover): foco/pausado/espera + confirmar que a música some
    Scenario(name: "pomodoro-card-focus", realNotch: true) { vm, _ in
        vm.pomodoro = PomodoroState(phase: .focus, runState: .running, remaining: 23 * 60 + 14, completedFocus: 1, cyclesUntilLong: 4)
        vm.expanded = true
    },
    Scenario(name: "pomodoro-card-paused", realNotch: true) { vm, _ in
        vm.pomodoro = PomodoroState(phase: .focus, runState: .paused, remaining: 12 * 60 + 3, completedFocus: 1, cyclesUntilLong: 4)
        vm.expanded = true
    },
    Scenario(name: "pomodoro-card-waiting", realNotch: true) { vm, _ in
        vm.pomodoro = PomodoroState(phase: .shortBreak, runState: .waiting, remaining: 5 * 60, completedFocus: 1, cyclesUntilLong: 4)
        vm.expanded = true
    },
    Scenario(name: "pomodoro-card-with-music", realNotch: true) { vm, media in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.pomodoro = PomodoroState(phase: .focus, runState: .running, remaining: 23 * 60 + 14, completedFocus: 1, cyclesUntilLong: 4)
        vm.expanded = true
    },
    // AirPods: card de conexão (transitório), faixa junto da música,
    // card dedicado sem música, e aviso de bateria baixa.
    Scenario(name: "airpods-connect", realNotch: true) { vm, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-connect-external", realNotch: false) { vm, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-strip-music", realNotch: true) { vm, media in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31)
        vm.expanded = true
    },
    Scenario(name: "airpods-card-nomusic", realNotch: true) { vm, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31)
        vm.expanded = true
    },
    Scenario(name: "airpods-low", realNotch: false) { vm, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 8, right: 74, case_: nil)
        vm.airpodsCard = true
    },
]

MainActor.assumeIsolated {
for scenario in scenarios {
    currentShelf = ShelfStore()
    let vm = NotchViewModel()
    let media = MediaController()
    media.injectPreview(state: nil, artwork: nil)
    vm.hasRealNotch = scenario.realNotch
    vm.notchSize = scenario.realNotch
        ? CGSize(width: 200, height: 32)
        : CGSize(width: 190, height: 30)
    scenario.configure(vm, media)

    // wallpaper claro atrás: revela a silhueta e as bordas da forma
    let view = ZStack(alignment: .top) {
        LinearGradient(
            colors: [Color(red: 0.72, green: 0.78, blue: 0.88),
                     Color(red: 0.90, green: 0.86, blue: 0.80)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        NotchView(
            vm: vm, media: media, levels: SystemAudioLevels(),
            shelf: currentShelf, dropTargetsEnabled: false)
    }
    .frame(width: 560, height: 240)

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
renderOverlay("descanso", label: "Almoço", hold: 0)
renderOverlay("descanso-hold", label: "Almoço", hold: 0.6)
}
