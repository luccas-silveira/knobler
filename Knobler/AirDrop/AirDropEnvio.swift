//
//  AirDropEnvio.swift
//  Knobler
//
//  Enviar por AirDrop. O app é LSUIElement com painel nonactivating — sem
//  ativar antes, a janela do AirDrop nasce atrás de tudo.
//

import AppKit

/// O que o notch consegue saber de um envio por AirDrop.
///
/// **Não existe percentual aqui, e não é esquecimento**: `NSSharingService` só
/// avisa começou / terminou / falhou, e o sistema não publica `NSProgress` de
/// envio. O `destino` vem da janela do AirDrop por Acessibilidade (nil sem ela).
/// `label` é "foto.png" pra um arquivo e "3 arquivos" pra vários — quem envia
/// pelo menu da barra só descobre isso depois do painel, então o estado carrega
/// o rótulo pronto em vez de obrigar o chamador a guardá-lo.
enum AirDropState: Equatable {
    case enviando(label: String, destino: String?)
    case enviado(label: String, destino: String?, urls: [URL])
    /// Janela do AirDrop fechada sem escolher destino. Não é erro, e não vira card.
    case cancelado
    case falhou(String)
}

enum AirDropEnvio {
    /// Sessões vivas. O `NSSharingService` **não** retém o delegate, e sem isto
    /// ele morre no fim desta função — os callbacks nunca chegariam.
    private static var sessions: [AirDropSession] = []

    /// Abre a janela de AirDrop do sistema com os arquivos já engatilhados.
    /// `onState` acompanha o envio (ver `AirDropState` pro que dá pra saber).
    static func enviar(_ urls: [URL], onState: ((AirDropState) -> Void)? = nil) {
        let items = Sharing.existing(urls)
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
            let session = AirDropSession(label: AirDropRegras.rotulo(items), urls: items, onState: onState)
            session.onFinish = { [weak session] in
                sessions.removeAll { $0 === session }
            }
            sessions.append(session)
            service.delegate = session
        }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: items)
    }

    /// Escolher arquivo do disco e mandar por AirDrop, sem passar pela
    /// prateleira. O menu da barra chama isto.
    static func enviarDoPainel(onState: ((AirDropState) -> Void)? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Enviar"
        panel.message = "Escolha o que enviar por AirDrop"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        enviar(panel.urls, onState: onState)
    }

    /// A janela do AirDrop nasce no processo de quem compartilha — aqui, no
    /// próprio Knobler. Cada aparelho é um `AXButton` "<nome>, Enviando|Enviado".
    static func destinoAtual() -> (aparelho: String, enviado: Bool)? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(getpid())
        var janelas: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &janelas)
        for janela in (janelas as? [AXUIElement]) ?? [] {
            var pilha = [janela]; var vistos = 0
            while let el = pilha.popLast(), vistos < 300 {
                vistos += 1
                var desc: AnyObject?
                AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &desc)
                if let d = desc as? String, let achado = AirDropRegras.destino(deDescricao: d) {
                    return achado
                }
                var filhos: AnyObject?
                AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &filhos)
                pilha += (filhos as? [AXUIElement]) ?? []
            }
        }
        return nil
    }
}

/// Delegate de um envio. Vive enquanto o envio existir e se remove sozinho no
/// fim — daí o `onFinish`.
final class AirDropSession: NSObject, NSSharingServiceDelegate {
    private let label: String
    private let urls: [URL]
    private let onState: (AirDropState) -> Void
    private var destino: String?
    private var timer: Timer?
    var onFinish: (() -> Void)?

    init(label: String, urls: [URL], onState: @escaping (AirDropState) -> Void) {
        self.label = label; self.urls = urls; self.onState = onState
    }

    func sharingService(_ service: NSSharingService, willShareItems items: [Any]) {
        onState(.enviando(label: label, destino: nil))
        // o destino só existe depois que o usuário clica no aparelho: sonda a
        // janela até ele aparecer. ponytail: polling de 0,5 s, trocar por
        // AXObserver se a sonda pesar
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.destino == nil,
                  let d = AirDropEnvio.destinoAtual() else { return }
            self.destino = d.aparelho
            self.onState(.enviando(label: self.label, destino: d.aparelho))
        }
    }

    func sharingService(_ service: NSSharingService, didShareItems items: [Any]) {
        timer?.invalidate()
        onState(.enviado(label: label, destino: destino ?? AirDropEnvio.destinoAtual()?.aparelho, urls: urls))
        onFinish?()
    }

    func sharingService(
        _ service: NSSharingService, didFailToShareItems items: [Any], error: Error
    ) {
        timer?.invalidate()
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
