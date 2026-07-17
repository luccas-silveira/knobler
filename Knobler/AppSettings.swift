//
//  AppSettings.swift
//  Knobler
//
//  Preferências persistidas em UserDefaults + tela de Ajustes.
//  Cada módulo consulta o toggle no momento do evento — desligar vale
//  na hora, sem reiniciar.
//

import ServiceManagement
import SwiftUI

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var notchNotifications: Bool {
        didSet { UserDefaults.standard.set(notchNotifications, forKey: "notchNotifications") }
    }
    @Published var volumeHUD: Bool {
        didSet { UserDefaults.standard.set(volumeHUD, forKey: "volumeHUD") }
    }
    @Published var brightnessHUD: Bool {
        didSet { UserDefaults.standard.set(brightnessHUD, forKey: "brightnessHUD") }
    }
    @Published var batteryAlerts: Bool {
        didSet { UserDefaults.standard.set(batteryAlerts, forKey: "batteryAlerts") }
    }
    @Published var liveAudioVisualizer: Bool {
        didSet { UserDefaults.standard.set(liveAudioVisualizer, forKey: "liveAudioVisualizer") }
    }
    @Published var localAPI: Bool {
        didSet { UserDefaults.standard.set(localAPI, forKey: "localAPI") }
    }
    @Published var calendarCountdown: Bool {
        didSet { UserDefaults.standard.set(calendarCountdown, forKey: "calendarCountdown") }
    }
    /// Espelho abre sozinho 2min antes de evento com link de call
    /// (requer a contagem do calendário ligada).
    @Published var mirrorBeforeMeetings: Bool {
        didSet { UserDefaults.standard.set(mirrorBeforeMeetings, forKey: "mirrorBeforeMeetings") }
    }
    @Published var micIndicator: Bool {
        didSet { UserDefaults.standard.set(micIndicator, forKey: "micIndicator") }
    }

    /// Estado real no launchd — não é persistido por nós.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("knobler login item: %@", error.localizedDescription)
            }
            objectWillChange.send()
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        notchNotifications = flag("notchNotifications")
        volumeHUD = flag("volumeHUD")
        brightnessHUD = flag("brightnessHUD")
        batteryAlerts = flag("batteryAlerts")
        liveAudioVisualizer = flag("liveAudioVisualizer")
        localAPI = flag("localAPI")
        calendarCountdown = flag("calendarCountdown")
        mirrorBeforeMeetings = flag("mirrorBeforeMeetings")
        micIndicator = flag("micIndicator")
    }
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Notch") {
                Toggle("Notificações no notch", isOn: $settings.notchNotifications)
                Toggle("HUD de som", isOn: $settings.volumeHUD)
                Toggle("HUD de brilho", isOn: $settings.brightnessHUD)
                Toggle("Avisos de bateria", isOn: $settings.batteryAlerts)
                Toggle("Visualizador com áudio real", isOn: $settings.liveAudioVisualizer)
                Toggle("Contagem do calendário", isOn: $settings.calendarCountdown)
                Toggle("Espelho antes de reuniões", isOn: $settings.mirrorBeforeMeetings)
                Toggle("Indicador de microfone", isOn: $settings.micIndicator)
            }
            Section {
                Toggle("API local", isOn: $settings.localAPI)
            } footer: {
                Text("POST http://localhost:4477/notify · {\"title\", \"body\", \"app\"}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section("Geral") {
                Toggle("Abrir no login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize()
    }
}
