//
//  NotificationInterceptor.swift
//  Knobler
//
//  Intercepta banners de notificação do macOS via Accessibility:
//  observa o processo do Notification Center (AXObserver + polling de
//  segurança), lê o conteúdo do banner, fecha o balão do sistema e
//  repassa pro notch. Mecânica dos subroles/actions baseada no
//  notification-sherpa (github.com/noma4i/notification-sherpa, MIT).
//

import AppKit
import ApplicationServices

struct NotchNotification: Identifiable, Equatable {
    let id = UUID()
    let appName: String?
    let title: String
    let body: String
    /// Bundle ID do app de origem (banners interceptados) — ícone/abrir exatos.
    var bundleID: String? = nil
    /// Alvo de sessão do Supacode: clique na notificação foca worktree/tab.
    var supacodeWorktree: String? = nil  // ID do worktree (path percent-encoded)
    var supacodeTab: String? = nil  // UUID da tab
    /// Lembrete do usuário: clique abre esta URL (http/https/file/app).
    var openURL: String? = nil
    /// Avatar remoto (webhook): URL https carregada com guardas no card.
    var iconURL: String? = nil
    /// ID de dedupe do webhook: mesmo id substitui em vez de empilhar (progresso).
    var webhookID: String? = nil
    let date = Date()
}

final class NotificationInterceptor {
    private static let ncBundleID = "com.apple.notificationcenterui"
    private static let bannerSubroles: Set<String> = [
        "AXNotificationCenterBanner", "AXNotificationCenterAlert",
    ]
    private static let windowSubroles: Set<String> =
        bannerSubroles.union(["AXSystemDialog"])
    // ação de fechar pode vir com nome cru ou localizado
    private static let closeActionHints = ["close", "clear", "fechar", "limpar"]

    private let onNotification: (NotchNotification) -> Void
    private var observer: AXObserver?
    private var observedPid: pid_t = 0
    private var handled = Set<CFHashCode>()
    private var lastContentKey = ""
    private var lastContentDate = Date.distantPast
    private var attachTimer: Timer?
    private var fallbackTimer: Timer?

    init(onNotification: @escaping (NotchNotification) -> Void) {
        self.onNotification = onNotification
    }

    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        // tenta anexar até ter permissão; re-anexa se o Notification Center reiniciar
        attachTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.attachIfPossible()
        }
        attachIfPossible()

        // ponytail: rede de segurança do sherpa — AXObserver às vezes perde evento;
        // um scan a cada 3s custa ~nada
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    // MARK: - Observer

    private func attachIfPossible() {
        guard AXIsProcessTrusted() else { return }
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.ncBundleID
        ).first else { return }

        let pid = app.processIdentifier
        guard observer == nil || pid != observedPid else { return }

        if let old = observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .commonModes)
        }

        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<NotificationInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            // o settle de renderização fica no process(), não aqui
            DispatchQueue.main.async { me.scan() }
        }

        var newObserver: AXObserver?
        guard AXObserverCreate(pid, callback, &newObserver) == .success, let obs = newObserver else {
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(obs, appElement, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)

        observer = obs
        observedPid = pid
        scan()
    }

    // MARK: - Scan e parse

    fileprivate func scan() {
        // desligado: banners ficam com o sistema (não fecha nem repassa)
        guard AppSettings.shared.notchNotifications else { return }
        guard AXIsProcessTrusted() else { return }
        let banners = currentBanners()
        var present = Set<CFHashCode>()

        for banner in banners {
            let hash = CFHash(banner)
            present.insert(hash)
            guard !handled.contains(hash) else { continue }
            handled.insert(hash)

            // banner recém-criado ainda está montando o texto (o scan do timer
            // chegava a ler corpo pela metade) — espera assentar antes de parsear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.process(banner)
            }
        }

        handled.formIntersection(present)
    }

    private func process(_ banner: AXUIElement) {
        guard let parsed = parse(banner) else { return }

        // dedupe por conteúdo (o mesmo banner pode reaparecer com outro handle)
        let key = "\(parsed.appName ?? "")|\(parsed.title)|\(parsed.body)"
        if key == lastContentKey, Date().timeIntervalSince(lastContentDate) < 2 { return }
        lastContentKey = key
        lastContentDate = Date()

        NSLog("knobler intercepted: title=%@", parsed.title)
        close(banner)
        onNotification(NotchNotification(
            appName: Self.appName(forBundleID: Self.defaultBundleID),
            title: parsed.title,
            body: parsed.body,
            bundleID: Self.defaultBundleID
        ))
    }

    /// O Tahoe não expõe o app de origem no banner (AXStackingIdentifier foi
    /// removido) e o banco da Central de Notificações some com a notificação
    /// quando ela é lida rápido — nenhuma fonte confiável em tempo real. Como
    /// o WhatsApp é o único app com notificação ligada neste Mac, todo banner
    /// interceptado usa o ícone dele. Trocar aqui se habilitar outro app.
    private static let defaultBundleID = "net.whatsapp.WhatsApp"

    private func currentBanners() -> [AXUIElement] {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.ncBundleID
        ).first else { return [] }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = copyAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement] ?? []

        return windows.flatMap { window -> [AXUIElement] in
            guard let subrole = stringAttribute(window, kAXSubroleAttribute),
                  Self.windowSubroles.contains(subrole)
            else { return [] }
            if Self.bannerSubroles.contains(subrole) { return [window] }
            return bannerDescendants(of: window)
        }
    }

    private func bannerDescendants(of element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth <= 8 else { return [] }
        if let subrole = stringAttribute(element, kAXSubroleAttribute),
           Self.bannerSubroles.contains(subrole) {
            return [element]
        }
        return children(of: element).flatMap { bannerDescendants(of: $0, depth: depth + 1) }
    }

    private func parse(_ banner: AXUIElement) -> (appName: String?, title: String, body: String)? {
        var texts: [String] = []
        collectStaticTexts(banner, into: &texts)
        texts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !texts.isEmpty else { return nil }

        // heurística: banners padrão vêm como [app, título, corpo...];
        // com 2 textos assume [título, corpo]; com 1, só título
        switch texts.count {
        case 1: return (nil, texts[0], "")
        case 2: return (nil, texts[0], texts[1])
        default: return (texts[0], texts[1], texts[2...].joined(separator: " — "))
        }
    }

    private static func appName(forBundleID bundleID: String) -> String? {
        if let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID).first {
            return app.localizedName
        }
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private func collectStaticTexts(_ element: AXUIElement, into texts: inout [String], depth: Int = 0) {
        guard depth <= 8, texts.count < 6 else { return }
        if stringAttribute(element, kAXRoleAttribute) == (kAXStaticTextRole as String),
           let value = stringAttribute(element, kAXValueAttribute) {
            texts.append(value)
        }
        for child in children(of: element) {
            collectStaticTexts(child, into: &texts, depth: depth + 1)
        }
    }

    private func close(_ banner: AXUIElement) {
        if performCloseAction(on: banner) { return }
        // fallback: procura um filho com ação de fechar (botão X)
        var stack = children(of: banner)
        var depth = 0
        while !stack.isEmpty, depth < 200 {
            depth += 1
            let element = stack.removeFirst()
            if performCloseAction(on: element) { return }
            stack.append(contentsOf: children(of: element))
        }
    }

    private func performCloseAction(on element: AXUIElement) -> Bool {
        for action in actionNames(of: element) {
            let lowered = action.lowercased()
            if Self.closeActionHints.contains(where: { lowered.contains($0) }) {
                return AXUIElementPerformAction(element, action as CFString) == .success
            }
        }
        return false
    }

    // MARK: - Helpers AX

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private func actionNames(of element: AXUIElement) -> [String] {
        var namesRef: CFArray?
        guard AXUIElementCopyActionNames(element, &namesRef) == .success else { return [] }
        return namesRef as? [String] ?? []
    }
}
