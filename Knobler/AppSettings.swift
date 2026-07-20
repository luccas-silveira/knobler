//
//  AppSettings.swift
//  Knobler
//
//  Preferências persistidas em UserDefaults + tela de Ajustes.
//  Cada módulo consulta o toggle no momento do evento — desligar vale
//  na hora, sem reiniciar.
//

import Security
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
    /// Card de AirPods no notch (connect + bateria L/R/estojo no hover).
    @Published var airpodsNotch: Bool {
        didSet { UserDefaults.standard.set(airpodsNotch, forKey: "airpodsNotch") }
    }
    /// Segurar ⌥ direita grava, soltar transcreve e insere no cursor.
    @Published var dictation: Bool {
        didSet { UserDefaults.standard.set(dictation, forKey: "dictation") }
    }
    /// Engine cloud (Deepgram) no lugar do modelo local.
    @Published var dictationCloud: Bool {
        didSet { UserDefaults.standard.set(dictationCloud, forKey: "dictationCloud") }
    }
    /// Passa o transcript por um LLM local (Ollama/LM Studio) pra limpar fillers,
    /// falsos começos e pontuação antes de colar. Opt-in: adiciona ~1s de latência.
    @Published var formatTranscript: Bool {
        didSet { UserDefaults.standard.set(formatTranscript, forKey: "formatTranscript") }
    }
    @Published var formatEndpoint: String {
        didSet { UserDefaults.standard.set(formatEndpoint, forKey: "formatEndpoint") }
    }
    @Published var formatModel: String {
        didSet { UserDefaults.standard.set(formatModel, forKey: "formatModel") }
    }
    /// Toda captura de tela do macOS entra na prateleira automaticamente.
    @Published var screenshotsToShelf: Bool {
        didSet { UserDefaults.standard.set(screenshotsToShelf, forKey: "screenshotsToShelf") }
    }
    /// Esconde o preview flutuante nativo do print (o shelf já mostra).
    @Published var hideScreenshotPreview: Bool {
        didSet { UserDefaults.standard.set(hideScreenshotPreview, forKey: "hideScreenshotPreview") }
    }
    /// Recebe notificações externas via webhook (relay push.appzoi.com.br). Opt-in.
    @Published var webhookNotifications: Bool {
        didSet { UserDefaults.standard.set(webhookNotifications, forKey: "webhookNotifications") }
    }
    /// Baixa o avatar remoto das notificações de webhook (expõe o IP do Mac ao remetente).
    @Published var loadRemoteImages: Bool {
        didSet { UserDefaults.standard.set(loadRemoteImages, forKey: "loadRemoteImages") }
    }

    /// Lembretes programados do usuário (JSON em UserDefaults).
    @Published var reminders: [Reminder] {
        didSet {
            if let data = try? JSONEncoder().encode(reminders) {
                UserDefaults.standard.set(data, forKey: "reminders")
            }
        }
    }

    /// Bloqueios de tela agendados ("Descanso") — JSON em UserDefaults.
    @Published var screenBreaks: [ScreenBreak] {
        didSet {
            if let data = try? JSONEncoder().encode(screenBreaks) {
                UserDefaults.standard.set(data, forKey: "screenBreaks")
            }
        }
    }
    /// Travar a tela (bloqueio forçado) nas pausas do Pomodoro.
    @Published var pomodoroLockScreen: Bool {
        didSet { UserDefaults.standard.set(pomodoroLockScreen, forKey: "pomodoroLockScreen") }
    }

    // MARK: Pomodoro (durações em minutos)
    @Published var pomodoroFocus: Int {
        didSet { UserDefaults.standard.set(pomodoroFocus, forKey: "pomodoroFocus") }
    }
    @Published var pomodoroShortBreak: Int {
        didSet { UserDefaults.standard.set(pomodoroShortBreak, forKey: "pomodoroShortBreak") }
    }
    @Published var pomodoroLongBreak: Int {
        didSet { UserDefaults.standard.set(pomodoroLongBreak, forKey: "pomodoroLongBreak") }
    }
    @Published var pomodoroCyclesLong: Int {
        didSet { UserDefaults.standard.set(pomodoroCyclesLong, forKey: "pomodoroCyclesLong") }
    }
    /// Som curto ao trocar de fase (fim de foco/pausa).
    @Published var pomodoroSound: Bool {
        didSet { UserDefaults.standard.set(pomodoroSound, forKey: "pomodoroSound") }
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
        airpodsNotch = flag("airpodsNotch")
        dictation = flag("dictation")
        dictationCloud = defaults.bool(forKey: "dictationCloud") // default false: local-first
        formatTranscript = defaults.bool(forKey: "formatTranscript") // default false: opt-in
        formatEndpoint = defaults.string(forKey: "formatEndpoint") ?? "http://localhost:11434/v1/chat/completions"
        formatModel = defaults.string(forKey: "formatModel") ?? "gemma3:4b"
        screenshotsToShelf = flag("screenshotsToShelf")
        hideScreenshotPreview = flag("hideScreenshotPreview")
        webhookNotifications = defaults.bool(forKey: "webhookNotifications") // default false: opt-in
        loadRemoteImages = flag("loadRemoteImages")                           // default true

        if let data = defaults.data(forKey: "reminders"),
           let decoded = try? JSONDecoder().decode([Reminder].self, from: data) {
            reminders = decoded
        } else {
            reminders = []
        }

        if let data = defaults.data(forKey: "screenBreaks"),
           let decoded = try? JSONDecoder().decode([ScreenBreak].self, from: data) {
            screenBreaks = decoded
        } else {
            screenBreaks = []
        }
        pomodoroLockScreen = defaults.bool(forKey: "pomodoroLockScreen") // default false: opt-in

        func intOr(_ key: String, _ d: Int) -> Int {
            let v = defaults.integer(forKey: key); return v == 0 ? d : v
        }
        pomodoroFocus = intOr("pomodoroFocus", 25)
        pomodoroShortBreak = intOr("pomodoroShortBreak", 5)
        pomodoroLongBreak = intOr("pomodoroLongBreak", 15)
        pomodoroCyclesLong = intOr("pomodoroCyclesLong", 4)
        pomodoroSound = flag("pomodoroSound")   // default true
    }
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var webhookClient: WebhookClient
    @State private var deepgramKey = DeepgramKeyStore.load()

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Geral", systemImage: "gearshape") }
            RemindersView()
                .tabItem { Label("Lembretes", systemImage: "bell.badge") }
            DescansoTabView()
                .tabItem { Label("Descanso", systemImage: "moon.zzz") }
            WebhookSettingsView(client: webhookClient)
                .tabItem { Label("Notificações externas", systemImage: "bell.and.waves.left.and.right") }
        }
        .frame(width: 400, height: 580)
    }

    private var generalTab: some View {
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
                Toggle("AirPods no notch", isOn: $settings.airpodsNotch)
                Toggle("Capturas de tela vão pro shelf", isOn: $settings.screenshotsToShelf)
                if settings.screenshotsToShelf {
                    Toggle("Esconder preview nativo do print", isOn: $settings.hideScreenshotPreview)
                }
            }
            Section {
                Toggle("API local", isOn: $settings.localAPI)
            } footer: {
                Text("POST http://localhost:4477/notify · {\"title\", \"body\", \"app\"}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section("Ditado") {
                Toggle("Ditado (segurar ⌥ direita)", isOn: $settings.dictation)
                Toggle("Usar Deepgram (cloud)", isOn: $settings.dictationCloud)
                if settings.dictationCloud {
                    SecureField("API key do Deepgram", text: $deepgramKey)
                        .onChange(of: deepgramKey) { _, new in
                            DeepgramKeyStore.save(new)
                        }
                }
                Toggle("Formatar com IA (local)", isOn: $settings.formatTranscript)
                if settings.formatTranscript {
                    TextField("Endpoint", text: $settings.formatEndpoint)
                    TextField("Modelo", text: $settings.formatModel)
                }
            }
            Section("Pomodoro") {
                Stepper("Foco: \(settings.pomodoroFocus) min",
                        value: $settings.pomodoroFocus, in: 1...120)
                Stepper("Pausa curta: \(settings.pomodoroShortBreak) min",
                        value: $settings.pomodoroShortBreak, in: 1...60)
                Stepper("Pausa longa: \(settings.pomodoroLongBreak) min",
                        value: $settings.pomodoroLongBreak, in: 1...60)
                Stepper("Focos até pausa longa: \(settings.pomodoroCyclesLong)",
                        value: $settings.pomodoroCyclesLong, in: 1...12)
                Toggle("Som ao trocar de fase", isOn: $settings.pomodoroSound)
                Toggle("Travar a tela nas pausas", isOn: $settings.pomodoroLockScreen)
            }
            Section("Geral") {
                Toggle("Abrir no login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

/// API key do Deepgram no Keychain — segredo não vai pro UserDefaults.
enum DeepgramKeyStore {
    private static let service = "com.zoi.knobler.deepgram"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(base as CFDictionary)
        guard !key.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
