//
//  AppSettings.swift
//  Knobler
//
//  Preferências persistidas em UserDefaults + tela de Ajustes.
//  Cada módulo consulta o toggle no momento do evento — desligar vale
//  na hora, sem reiniciar.
//

import AppKit
import Collaboration
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
    /// `uniqueID` da câmera do espelho; "" = automática (embutida primeiro).
    /// Guardamos o ID e não o índice: a lista muda quando um USB entra/sai.
    @Published var mirrorDeviceID: String {
        didSet {
            UserDefaults.standard.set(mirrorDeviceID, forKey: "mirrorDeviceID")
            MirrorController.shared.switchDevice()
        }
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

    /// Nome que os outros veem nas Mensagens LAN. Começa com o do macOS.
    @Published var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: "displayName") }
    }
    /// UUID estável desta instalação — chaveia histórico e foto. Gerado 1x.
    let myID: String

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
        mirrorDeviceID = defaults.string(forKey: "mirrorDeviceID") ?? ""  // "" = automática
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

        if let existing = defaults.string(forKey: "myID") {
            myID = existing
        } else {
            let generated = UUID().uuidString
            defaults.set(generated, forKey: "myID")
            myID = generated
        }
        displayName = defaults.string(forKey: "displayName") ?? AppSettings.macOSFullName()
    }

    // MARK: - Identidade das Mensagens LAN

    /// Foto de perfil em App Support (me.jpg). nil se o usuário não definiu.
    private var myAvatarURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Knobler", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("me.jpg")
    }

    func myAvatarJPEG() -> Data? { try? Data(contentsOf: myAvatarURL) }

    func removeMyAvatar() {
        try? FileManager.default.removeItem(at: myAvatarURL)
        objectWillChange.send()
    }

    func setMyAvatar(_ image: NSImage) {
        guard let jpeg = AppSettings.jpegThumbnail(image) else { return }
        try? jpeg.write(to: myAvatarURL)
        objectWillChange.send()
    }

    func myProfile() -> PeerProfile {
        PeerProfile(id: myID, name: displayName, avatarJPEG: myAvatarJPEG())
    }

    static func macOSFullName() -> String {
        let name = NSFullUserName()
        return name.isEmpty ? NSUserName() : name
    }

    static func macOSAvatar() -> NSImage? {
        CBUserIdentity(posixUID: getuid(), authority: .default())?.image
    }

    /// Corta o centro em quadrado e gera um JPEG `side`×`side` real (~alguns KB).
    /// Usa um NSBitmapImageRep explícito de `side` px — não escala pelo backing
    /// Retina (senão sairia 2×) — e recorta a fonte pra não distorcer não-quadradas.
    static func jpegThumbnail(_ image: NSImage, side: Int = 64) -> Data? {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return nil }
        let edge = min(s.width, s.height)                       // maior quadrado central
        let crop = NSRect(x: (s.width - edge) / 2, y: (s.height - edge) / 2,
                          width: edge, height: edge)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: side, height: side)            // 1 px = 1 unidade
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: crop, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
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
