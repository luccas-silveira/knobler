//
//  OSDSuppressor.swift
//  Knobler
//
//  Por que existe (root cause confirmada em 2026-07-16):
//  - No macOS Tahoe (26) o OSD de volume/brilho é desenhado pelo ControlCenter
//    (janela na layer 2005), não mais pelo OSDUIHelper.
//  - Teclas de brilho de teclado Apple EXTERNO são consumidas ABAIXO do
//    CGEventTap (nenhum evento NX/keyDown chega à sessão) — interceptar é
//    impossível nessa camada; o balão nativo aparecia mesmo com o tap ativo.
//  Supressão em duas partes (testada de ponta a ponta nesta máquina):
//    1. EnableSystemBanners=false → OSD volta ao estilo Sequoia (OSDUIHelper)
//    2. OSDUIHelper congelado com SIGSTOP (truque do SlimHUD): launchd o vê
//       vivo e não reinicia; SIGKILL descongela (respawn limpo) no restore.
//  O brilho continua mudando (CoreBrightness age abaixo); nossa pílula aparece
//  via poll do VolumeHUDController. Quebra no macOS 27 beta — reavaliar lá.
//

import Foundation

enum OSDSuppressor {
    static func suppress() {
        // reiniciar o ControlCenter pisca a barra de menus — só se a pref mudou
        let banners = UserDefaults(suiteName: "com.apple.controlcenter")?
            .object(forKey: "EnableSystemBanners") as? Bool
        if banners != false {
            run("/usr/bin/defaults",
                ["write", "com.apple.controlcenter", "EnableSystemBanners", "-bool", "false"])
            run("/usr/bin/killall", ["ControlCenter"])
        }
        // OSDUIHelper só sobe sob demanda — kickstart garante que exista pra congelar
        run("/bin/launchctl", ["kickstart", "gui/\(getuid())/com.apple.OSDUIHelper"], wait: true)
        usleep(500_000)
        run("/usr/bin/killall", ["-STOP", "OSDUIHelper"])
    }

    static func restore() {
        run("/usr/bin/killall", ["-9", "OSDUIHelper"]) // launchd respawna descongelado
        // EnableSystemBanners fica: é a escolha do produto. Reverter na mão:
        //   defaults delete com.apple.controlcenter EnableSystemBanners; killall ControlCenter
    }

    private static func run(_ path: String, _ args: [String], wait: Bool = false) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
        if wait { process.waitUntilExit() }
    }
}
