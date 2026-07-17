//
//  ScreenshotPreviewSuppressor.swift
//  Knobler
//
//  Esconde o preview flutuante nativo do print (com.apple.screencapture
//  show-thumbnail) — o Knobler já captura no shelf. Restaura no quit/desligar,
//  mas só reverte se NÓS mudamos (se o usuário já tinha off, não mexemos).
//  Bônus: com o thumbnail off o print grava em disco na hora (shelf mais rápido).
//  Mesmo padrão do OSDSuppressor: default de outro domínio + restore.
//

import Foundation

enum ScreenshotPreviewSuppressor {
    private static let changedKey = "screenshotPreviewSuppressedByUs"

    static func suppress() {
        let current = UserDefaults(suiteName: "com.apple.screencapture")?
            .object(forKey: "show-thumbnail") as? Bool
        guard current != false else { return } // já off (nosso ou escolha do usuário)
        run("/usr/bin/defaults",
            ["write", "com.apple.screencapture", "show-thumbnail", "-bool", "false"])
        UserDefaults.standard.set(true, forKey: changedKey)
        // screencapture lê a pref a cada print — killall costuma ser desnecessário.
        // Se precisar: run("/usr/bin/killall", ["SystemUIServer"])
    }

    static func restore() {
        guard UserDefaults.standard.bool(forKey: changedKey) else { return }
        run("/usr/bin/defaults", ["delete", "com.apple.screencapture", "show-thumbnail"])
        UserDefaults.standard.set(false, forKey: changedKey)
    }

    private static func run(_ path: String, _ args: [String], wait: Bool = false) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
        if wait { process.waitUntilExit() }
    }
}
