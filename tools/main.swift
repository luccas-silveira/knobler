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
    Scenario(name: "notification", realNotch: true) { vm, _ in
        vm.activeNotification = NotchNotification(
            appName: "Finder",
            title: "Backup concluído",
            body: "O Time Machine terminou o backup de hoje às 14:32."
        )
    },
]

MainActor.assumeIsolated {
for scenario in scenarios {
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
        NotchView(vm: vm, media: media, levels: SystemAudioLevels())
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
}
