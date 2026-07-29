//
//  Sharing.swift
//  Knobler
//
//  Enviar arquivo do shelf: AirDrop direto ou o menu de compartilhamento do
//  sistema. O app é LSUIElement com painel nonactivating — sem ativar antes, a
//  janela do AirDrop nasce atrás de tudo.
//

import AppKit

enum Sharing {
    /// Só o que ainda existe no disco: o shelf guarda paths e o arquivo pode ter
    /// sido movido/apagado depois de entrar na prateleira.
    static func existing(_ urls: [URL]) -> [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Abre a janela de AirDrop do sistema com os arquivos já engatilhados.
    static func airdrop(_ urls: [URL]) {
        let items = existing(urls)
        guard !items.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: items)
        else {
            NSLog("knobler: AirDrop indisponível para \(urls.count) item(ns)")
            NSSound.beep()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: items)
    }

    /// Menu nativo de compartilhamento (Mensagens, Mail, Notas… e o AirDrop).
    /// Ancorado na janela do notch, que é a única view real que temos.
    static func share(_ urls: [URL]) {
        let items = existing(urls)
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        guard let view = anchorView() else {
            // sem âncora o picker não tem onde nascer — cai no AirDrop, que é o
            // destino que este menu existe pra alcançar
            airdrop(items)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    /// O notch é o painel visível do app (os Ajustes são NSWindow comum).
    /// Testar por `NSPanel` em vez do tipo concreto deixa este arquivo compilar
    /// isolado no `sharingcheck`.
    private static func anchorView() -> NSView? {
        let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }
        return (panel ?? NSApp.keyWindow ?? NSApp.windows.first)?.contentView
    }
}
