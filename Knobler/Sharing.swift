//
//  Sharing.swift
//  Knobler
//
//  Enviar arquivo do shelf: AirDrop direto ou o menu de compartilhamento do
//  sistema. O app é LSUIElement com painel nonactivating — sem ativar antes, a
//  janela do AirDrop nasce atrás de tudo.
//

import AppKit

/// O que o notch consegue saber de um envio por AirDrop.
///
/// **Não existe percentual aqui, e não é esquecimento**: `NSSharingService` só
/// avisa começou / terminou / falhou — bytes transferidos não são expostos por
/// nenhuma API pública. Quem mostra a régua de progresso é a janela do próprio
/// sistema. Por isso o card do notch usa atividade indeterminada.
/// `label` é "foto.png" pra um arquivo e "3 arquivos" pra vários — quem envia
/// pelo menu da barra só descobre isso depois do painel, então o estado carrega
/// o rótulo pronto em vez de obrigar o chamador a guardá-lo.
enum AirDropState: Equatable {
    case enviando(label: String)
    case enviado(label: String)
    /// Janela do AirDrop fechada sem escolher destino. Não é erro, e não vira card.
    case cancelado
    case falhou(String)
}

enum Sharing {
    /// Só o que ainda existe no disco: o shelf guarda paths e o arquivo pode ter
    /// sido movido/apagado depois de entrar na prateleira.
    static func existing(_ urls: [URL]) -> [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Rótulo do card: um arquivo mostra o nome, vários mostram a contagem.
    static func label(for urls: [URL]) -> String {
        urls.count == 1
            ? urls[0].lastPathComponent
            : "\(urls.count) arquivos"
    }

    /// Sessões vivas. O `NSSharingService` **não** retém o delegate, e sem isto
    /// ele morre no fim desta função — os callbacks nunca chegariam.
    private static var sessions: [AirDropSession] = []

    /// Abre a janela de AirDrop do sistema com os arquivos já engatilhados.
    /// `onState` acompanha o envio (ver `AirDropState` pro que dá pra saber).
    static func airdrop(_ urls: [URL], onState: ((AirDropState) -> Void)? = nil) {
        let items = existing(urls)
        guard !items.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: items)
        else {
            NSLog("knobler: AirDrop indisponível para \(urls.count) item(ns)")
            NSSound.beep()
            onState?(.falhou("AirDrop indisponível"))
            return
        }
        if let onState {
            let session = AirDropSession(label: label(for: items), onState: onState)
            session.onFinish = { [weak session] in
                sessions.removeAll { $0 === session }
            }
            sessions.append(session)
            service.delegate = session
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

    /// Escolher arquivo do disco e mandar por AirDrop, sem passar pela
    /// prateleira. O menu da barra chama isto.
    static func airdropFromPanel(onState: ((AirDropState) -> Void)? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Enviar"
        panel.message = "Escolha o que enviar por AirDrop"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        airdrop(panel.urls, onState: onState)
    }

    /// O notch é o painel visível do app (os Ajustes são NSWindow comum).
    /// Testar por `NSPanel` em vez do tipo concreto deixa este arquivo compilar
    /// isolado no `sharingcheck`.
    private static func anchorView() -> NSView? {
        let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible }
        return (panel ?? NSApp.keyWindow ?? NSApp.windows.first)?.contentView
    }
}

/// Delegate de um envio. Vive enquanto o envio existir e se remove sozinho no
/// fim — daí o `onFinish`.
final class AirDropSession: NSObject, NSSharingServiceDelegate {
    private let label: String
    private let onState: (AirDropState) -> Void
    var onFinish: (() -> Void)?

    init(label: String, onState: @escaping (AirDropState) -> Void) {
        self.label = label
        self.onState = onState
    }

    func sharingService(_ service: NSSharingService, willShareItems items: [Any]) {
        onState(.enviando(label: label))
    }

    func sharingService(_ service: NSSharingService, didShareItems items: [Any]) {
        onState(.enviado(label: label))
        onFinish?()
    }

    func sharingService(
        _ service: NSSharingService, didFailToShareItems items: [Any], error: Error
    ) {
        // fechar a janela do AirDrop sem escolher destino chega aqui como
        // cancelamento — não é falha e não merece card de erro
        onState(Self.isCancel(error) ? .cancelado : .falhou(error.localizedDescription))
        onFinish?()
    }

    /// Cancelamento do usuário — fechar a janela do AirDrop sem escolher destino.
    static func isCancel(_ error: Error) -> Bool {
        let e = error as NSError
        return e.domain == NSCocoaErrorDomain && e.code == NSUserCancelledError
    }
}
