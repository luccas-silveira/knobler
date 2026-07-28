//
//  Permissions.swift
//  Knobler
//
//  Inventário único das permissões que o app usa: estado, por quê e o link
//  pro painel certo do Ajustes do Sistema. Existe porque o painel de Ajustes
//  precisa dos 7 estados de uma vez e os deep links viviam copiados em 6
//  arquivos diferentes.
//
//  Só LÊ estado — quem pede continua sendo cada subsistema, no primeiro uso
//  real da feature (ver o painel .permissoes em SettingsView).
//

import AVFoundation
import ApplicationServices
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
    case acessibilidade, microfone, camera, calendario, redeLocal, arquivos, audioSistema

    var id: String { rawValue }

    var title: String {
        switch self {
        case .acessibilidade: return "Acessibilidade"
        case .microfone: return "Microfone"
        case .camera: return "Câmera"
        case .calendario: return "Calendários"
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
    static func promptAccessibilityOnce() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
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
