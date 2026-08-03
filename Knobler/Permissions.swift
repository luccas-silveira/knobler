//
//  Permissions.swift
//  Knobler
//
//  Inventário único das permissões que o app usa: estado, por quê e o link
//  pro painel certo do Ajustes do Sistema. Existe porque o painel de Ajustes
//  precisa dos 8 estados de uma vez e os deep links viviam copiados em 6
//  arquivos diferentes.
//
//  Só LÊ estado — quem pede continua sendo cada subsistema, no primeiro uso
//  real da feature (ver o painel .permissoes em SettingsView).
//

import AVFoundation
import AppKit
import ApplicationServices
import CoreBluetooth
import EventKit
import Foundation

enum PermissionStatus {
    case concedida
    case negada
    case naoPedida
    /// Sem API pública de status: só sabemos depois que a feature roda uma vez.
    case naoVerificada
}

enum Permission: String, CaseIterable, Identifiable {
    case acessibilidade, microfone, camera, calendario, bluetooth, redeLocal, arquivos,
         audioSistema

    var id: String { rawValue }

    var title: String {
        switch self {
        case .acessibilidade: return "Acessibilidade"
        case .microfone: return "Microfone"
        case .camera: return "Câmera"
        case .calendario: return "Calendários"
        case .bluetooth: return "Bluetooth"
        case .redeLocal: return "Rede local"
        case .arquivos: return "Arquivos e pastas"
        case .audioSistema: return "Gravação de áudio do sistema"
        }
    }

    /// O que quebra sem ela — é isso que o usuário precisa ler pra decidir.
    var why: String {
        switch self {
        case .acessibilidade:
            return "Lê as teclas de volume e brilho pros HUDs, detecta a ⌥ direita do ditado e cola o texto transcrito onde o cursor estiver. Sem ela o ditado não tem como nem começar."
        case .microfone:
            return "Grava sua voz enquanto você segura a ⌥ direita."
        case .camera:
            return "Mostra o espelho no notch antes de reuniões."
        case .calendario:
            return "Mostra a contagem regressiva do próximo evento na asinha do notch."
        case .bluetooth:
            return "Vê os AirPods conectarem e lê a bateria deles. Pedida na abertura, junto com a Acessibilidade — desligue \"AirPods no notch\" pra evitar."
        case .redeLocal:
            return "Encontra outros Macs com Knobler pra trocar mensagens."
        case .arquivos:
            return "Lê as capturas de tela que entram na prateleira."
        case .audioSistema:
            return "Anima o visualizador com o áudio real do player, em vez do sintético."
        }
    }

    /// Painel do Ajustes do Sistema. O host `com.apple.preference.security`
    /// segue valendo no macOS 26 — o Ajustes redireciona pra Privacidade.
    var settingsURL: URL {
        let anchor: String
        switch self {
        case .acessibilidade: anchor = "Privacy_Accessibility"
        case .microfone: anchor = "Privacy_Microphone"
        case .camera: anchor = "Privacy_Camera"
        case .calendario: anchor = "Privacy_Calendars"
        case .bluetooth: anchor = "Privacy_Bluetooth"
        case .redeLocal: anchor = "Privacy_LocalNetwork"
        case .arquivos: anchor = "Privacy_FilesAndFolders"
        // ponytail: âncora só existe no macOS 14.4+; em 14.2/14.3 o Ajustes
        // abre a raiz de Privacidade, que ainda é melhor que não abrir nada.
        case .audioSistema: anchor = "Privacy_AudioCapture"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    var status: PermissionStatus {
        switch self {
        case .acessibilidade:
            // AXIsProcessTrusted() não distingue negada de nunca pedida.
            return AXIsProcessTrusted() ? .concedida : .naoPedida
        case .microfone:
            return Self.capture(AVCaptureDevice.authorizationStatus(for: .audio))
        case .camera:
            return Self.capture(AVCaptureDevice.authorizationStatus(for: .video))
        case .calendario:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return .concedida
            case .notDetermined: return .naoPedida
            default: return .negada
            }
        case .bluetooth:
            // Quem pede é o IOBluetooth do BluetoothMonitor, não o CoreBluetooth
            // — mas os dois batem no mesmo TCC (kTCCServiceBluetoothAlways), e
            // só o CoreBluetooth expõe o estado sem instanciar nada.
            switch CBManager.authorization {
            case .allowedAlways: return .concedida
            case .notDetermined: return .naoPedida
            default: return .negada
            }
        case .redeLocal, .arquivos, .audioSistema:
            return Self.recorded(self)
        }
    }

    private static func capture(_ s: AVAuthorizationStatus) -> PermissionStatus {
        switch s {
        case .authorized: return .concedida
        case .notDetermined: return .naoPedida
        default: return .negada
        }
    }

    // MARK: - Estado das opacas
    //
    // Rede Local, Arquivos e Áudio do Sistema não expõem status. O subsistema
    // grava o resultado do primeiro uso real e o painel lê daqui.

    private static func key(_ p: Permission) -> String { "perm.used.\(p.rawValue)" }

    private static func recorded(_ p: Permission) -> PermissionStatus {
        guard let ok = UserDefaults.standard.object(forKey: key(p)) as? Bool else {
            return .naoVerificada
        }
        return ok ? .concedida : .negada
    }

    /// Chamado pelo subsistema quando a feature de fato funcionou (ou não).
    static func record(_ p: Permission, worked: Bool) {
        UserDefaults.standard.set(worked, forKey: key(p))
    }

    // MARK: - Acessibilidade

    /// Único lugar do app que abre o diálogo de Acessibilidade.
    ///
    /// Ela não tem "primeiro uso" detectável: sem ela o CGEventTap nem é criado,
    /// então o flagsChanged da ⌥ direita nunca chega e o gatilho do ditado é
    /// invisível. Por isso é a única pedida no launch — e uma vez só, em vez de
    /// um pedido no Dictation e outro no NotificationInterceptor.
    ///
    /// O diálogo do sistema só aparece enquanto o TCC não tem decisão gravada;
    /// depois disso a chamada vira no-op silenciosa. Por isso o painel de
    /// Permissões chama isto de novo **e** oferece o caminho manual (Revelar no
    /// Finder + arrastar pra lista), que é o único que funciona quando o app
    /// nem aparece na lista do Ajustes do Sistema.
    static func promptAccessibilityOnce() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Abre o Finder com o .app selecionado, pra arrastar direto pra lista do
    /// Ajustes do Sistema. É a saída quando o app não aparece na lista.
    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    // MARK: - Pedido direto
    //
    // O balão do sistema é sempre melhor que mandar o usuário pro Ajustes: ele
    // concede sem sair do app. Mas o TCC só o mostra enquanto não tem decisão
    // gravada — depois de negada, a chamada retorna false na hora e o único
    // caminho é o painel do Ajustes do Sistema. Por isso `canRequest` casa com
    // `.naoPedida`, e a UI só oferece "Permitir" nesse estado.

    /// Tem API de pedido E ainda dá pro balão aparecer.
    var canRequest: Bool {
        guard status == .naoPedida else { return false }
        switch self {
        case .acessibilidade, .microfone, .camera, .calendario: return true
        // Bluetooth: quem pede é o BluetoothMonitor na abertura (IOBluetooth).
        // Rede local, Arquivos e Áudio do sistema: sem API de pedido — o balão
        // é efeito colateral do primeiro uso real do recurso.
        case .bluetooth, .redeLocal, .arquivos, .audioSistema: return false
        }
    }

    /// Abre o balão do sistema. `completion` roda na main quando houver resposta
    /// (a Acessibilidade não tem callback: o painel repolla o status no foco).
    func request(completion: @escaping () -> Void) {
        let done = { DispatchQueue.main.async(execute: completion) }
        switch self {
        case .acessibilidade:
            Self.promptAccessibilityOnce()
            done()
        case .microfone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in done() }
        case .camera:
            AVCaptureDevice.requestAccess(for: .video) { _ in done() }
        case .calendario:
            // O store precisa viver até o callback — a closure segura a referência.
            let store = EKEventStore()
            store.requestFullAccessToEvents { _, _ in _ = store; done() }
        case .bluetooth, .redeLocal, .arquivos, .audioSistema:
            done()
        }
    }

    // MARK: - Saúde da instalação
    //
    // A causa mais comum de "o app não aparece na lista do Ajustes do Sistema"
    // não é a permissão em si: é a cópia rodando de um lugar que o TCC não
    // consegue ancorar (translocada pelo Gatekeeper, ou fora de /Applications,
    // ou com duas cópias disputando a mesma entrada).

    enum InstallIssue: Equatable {
        /// Gatekeeper rodando o app de uma cópia read-only em /private/var/folders.
        /// A entrada do TCC aponta pro caminho fantasma e some no próximo launch.
        case translocado
        /// Fora de /Applications: a entrada do TCC gruda no caminho antigo e o
        /// usuário procura o app na lista pelo lugar errado.
        case foraDeApplications(String)
        /// Marca de quarentena ainda presente — o cask remove no postflight, mas
        /// quem instalou pelo .zip do Releases à mão pode não ter removido.
        case emQuarentena

        var mensagem: String {
            switch self {
            case .translocado:
                return "O macOS está rodando o Knobler de uma cópia temporária (App Translocation). Nesse estado a permissão nunca gruda e o app não aparece na lista do Ajustes do Sistema."
            case .foraDeApplications(let path):
                return "O Knobler está rodando de \(path), fora de /Applications. As permissões ficam presas nesse caminho."
            case .emQuarentena:
                return "A cópia instalada ainda tem a marca de quarentena do Gatekeeper."
            }
        }

        var comoResolver: String {
            switch self {
            case .translocado, .emQuarentena:
                return "Encerre o Knobler, mova o app para /Applications e rode no Terminal:\nxattr -dr com.apple.quarantine /Applications/Knobler.app\nDepois abra o app de novo."
            case .foraDeApplications:
                return "Encerre o Knobler, mova o app para /Applications e abra de lá."
            }
        }
    }

    /// `nil` quando a instalação está sadia.
    static var installIssue: InstallIssue? {
        let url = Bundle.main.bundleURL
        return issue(path: url.path, quarantined: isQuarantined(url), home: NSHomeDirectory())
    }

    /// Parte pura, pra o self-check não depender de onde o binário está.
    static func issue(path: String, quarantined: Bool, home: String) -> InstallIssue? {
        // O Gatekeeper monta a cópia translocada sob /private/var/folders/.../AppTranslocation/
        if path.contains("/AppTranslocation/") { return .translocado }
        if quarantined { return .emQuarentena }
        if !path.hasPrefix("/Applications/") && !path.hasPrefix("\(home)/Applications/") {
            return .foraDeApplications((path as NSString).deletingLastPathComponent)
        }
        return nil
    }

    private static func isQuarantined(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.quarantinePropertiesKey]))?
            .quarantineProperties != nil
    }

    /// Relatório de uma linha por permissão + estado da instalação. Existe pra
    /// suporte remoto: `Knobler --permissoes` num Mac que não é o nosso.
    static func diagnostico() -> String {
        var linhas = ["Knobler — diagnóstico de permissões",
                      "bundle: \(Bundle.main.bundleURL.path)",
                      "instalação: \(installIssue.map { "\($0)" } ?? "ok")"]
        for p in allCases {
            linhas.append("\(p.rawValue): \(p.status)")
        }
        return linhas.joined(separator: "\n")
    }

    #if DEBUG
    static func _selfCheck() {
        let p = Permission.redeLocal
        let saved = UserDefaults.standard.object(forKey: key(p))
        defer { UserDefaults.standard.set(saved, forKey: key(p)) }

        UserDefaults.standard.removeObject(forKey: key(p))
        assert(recorded(p) == .naoVerificada, "sem registro deve ser naoVerificada")
        record(p, worked: true)
        assert(recorded(p) == .concedida, "registro true deve ser concedida")
        record(p, worked: false)
        assert(recorded(p) == .negada, "registro false deve ser negada")
    }
    #endif
}

extension PermissionStatus: Equatable {}
