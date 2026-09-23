import AppKit
import Combine
import CoreAudio

/// Estado de apresentação na thread principal; transportes e gamma em fila serial.
final class Monitores: ObservableObject {
    static let shared = Monitores()
    @Published var displays: [MonitorState] = []
    @Published private(set) var restorationError: String?
    var onHUD: ((MonitorState, MonitorCommand) -> Void)?
    private(set) var running = false
    private var sleeping = false
    private let queue = DispatchQueue(label: "com.zoi.knobler.monitores", qos: .userInitiated)
    private let gate = MonitorWorkGate()
    private var backends: [UInt32: MonitorDisplay] = [:] // somente na fila
    private var restoring: [UInt32: MonitorDisplay] = [:] // preserva gamma original se a restauração falhar
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var appleTimer: Timer?
    private var pending: [UInt32: [MonitorCommand: Double]] = [:]
    private var failed: [UInt32: Set<MonitorCommand>] = [:]
    private var appleReadPending = false
    private var epoch = 0
    private var appleIDs = Set<UInt32>()
    // Injeção restrita aos self-checks: exercita a fila real sem APIs de tela ou persistência.
    private var testWrite: ((UInt32, MonitorCommand, Double, () -> Bool) -> Bool)?
    init() {}
    init(testDisplays: [MonitorState], write: @escaping (UInt32, MonitorCommand, Double, () -> Bool) -> Bool) {
        displays = testDisplays
        testWrite = write
        running = true
    }
    static let shortcutNames: [(title: String, name: KeyboardShortcuts.Name)] = [
        ("Aumentar brilho", .init("brightnessUp")), ("Diminuir brilho", .init("brightnessDown")),
        ("Aumentar volume", .init("volumeUp")), ("Diminuir volume", .init("volumeDown")),
        ("Alternar mudo", .init("mute")),
        ("Aumentar contraste", .init("contrastUp")), ("Diminuir contraste", .init("contrastDown"))
    ]

    func start() {
        guard !running else { return }
        running = true
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.refresh() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) { $0.suspend() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { $0.sleeping = false; $0.refresh() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification) { $0.suspend() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification) { $0.sleeping = false; $0.refresh() }
        for (index, shortcut) in Self.shortcutNames.enumerated() {
            KeyboardShortcuts.enable(shortcut.name)
            KeyboardShortcuts.onKeyDown(for: shortcut.name) { [weak self] in
                let command: MonitorCommand = index < 2 ? .brightness : index < 4 ? .volume : index == 4 ? .mute : .contrast
                _ = self?.handleKey(command, increase: index == 0 || index == 2 || index == 5, fine: NSEvent.modifierFlags.contains([.shift, .option]))
            }
        }
        refresh()
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping (Monitores) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            if let self, self.running { action(self) }
        }
        observers.append((center, token))
    }
    private func suspend() {
        sleeping = true
        clearWork()
    }
    private func clearWork() {
        epoch += 1
        gate.invalidate()
        pending.removeAll()
        failed.removeAll()
        appleReadPending = false
        appleIDs.removeAll()
        appleTimer?.invalidate(); appleTimer = nil
        queue.async {
            self.backends.forEach { self.restoring[$0.key] = $0.value }
            self.backends.removeAll()
            self.restoreRetained()
        }
    }
    // Executada apenas na fila de transportes; a tabela original vive até a confirmação.
    private func restoreRetained() {
        for (id, backend) in restoring where backend.restoreSoftware() { restoring[id] = nil }
        let failed = !restoring.isEmpty
        DispatchQueue.main.async {
            self.restorationError = failed ? "Não foi possível restaurar o brilho original. Tente restaurar novamente." : nil
        }
    }
    func retryRestoration() {
        queue.async {
            self.restoreRetained()
            let restored = self.restoring.isEmpty
            DispatchQueue.main.async { if restored && self.running { self.refresh() } }
        }
    }
    func stop() {
        guard running else { return }
        running = false
        sleeping = false
        observers.forEach { $0.0.removeObserver($0.1) }; observers.removeAll()
        KeyboardShortcuts.removeAllHandlers()
        clearWork()
        displays = []
    }
    /// Encerra apenas depois de restaurar gamma e fechar as sobreposições.
    /// O callback assíncrono mantém AppKit livre para concluir operações já iniciadas.
    func stop(completion: @escaping () -> Void) {
        stop()
        queue.async { DispatchQueue.main.async(execute: completion) }
    }
    func refresh() {
        guard running, !sleeping else { return }
        clearWork()
        let generation = epoch
        let screens = NSScreen.screens.compactMap { screen -> MonitorState? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).takeRetainedValue()
            let identity = CFUUIDCreateString(nil, uuid) as String
            var state = MonitorState(id: id, persistentID: identity, name: screen.localizedName)
            if let data = UserDefaults.standard.data(forKey: "monitores.preferences.\(identity)"),
               let prefs = try? JSONDecoder().decode(MonitorPreferences.self, from: data), prefs.valid {
                state.preferences = prefs
                if !prefs.name.isEmpty { state.name = prefs.name }
            }
            state.busy = true
            return state
        }
        displays = screens
        let ticket = gate.ticket("discovery")
        queue.async {
            let services = Arm64DDC.isArm64 ? Arm64DDC.getServiceMatches(displayIDs: screens.map(\.id)) : []
            for var state in screens {
                guard self.gate.accepts(ticket, key: "discovery") else { return }
                if self.restoring[state.id] != nil {
                    state.error = "Restaure o brilho original antes de continuar."
                    let blocked = state
                    DispatchQueue.main.async {
                        guard self.epoch == generation, let index = self.displays.firstIndex(where: { $0.id == blocked.id }) else { return }
                        self.displays[index] = blocked
                    }
                    continue
                }
                let backend = MonitorDisplay(id: state.id, arm: services.first { $0.displayID == state.id }?.service)
                let result = backend.readInitial(preferences: state.preferences) { self.gate.accepts(ticket, key: "discovery") }
                guard self.gate.accepts(ticket, key: "discovery") else {
                    if !backend.restoreSoftware() { self.restoring[state.id] = backend; self.restoreRetained() }
                    return
                }
                self.backends[state.id] = backend
                state.brightness = result.values[.brightness] ?? 1
                state.contrast = result.values[.contrast]
                state.volume = result.values[.volume]
                state.muted = result.values[.mute] == 1
                state.muteSupported = result.values[.mute] != nil
                state.hardwareBrightness = backend.hardwareBrightness
                state.software = backend.software
                state.busy = false
                if state.preferences.mode == .hardware && !backend.hardwareBrightness {
                    state.error = "Controle de brilho por hardware indisponível."
                }
                for (command, maximum) in result.maxima where command != .mute {
                    switch command {
                    case .brightness: if state.preferences.brightnessCalibration.maximum == 100 { state.preferences.brightnessCalibration.maximum = maximum }
                    case .contrast: if state.preferences.contrastCalibration.maximum == 100 { state.preferences.contrastCalibration.maximum = maximum }
                    case .volume: if state.preferences.volumeCalibration.maximum == 100 { state.preferences.volumeCalibration.maximum = maximum }
                    case .mute: break
                    }
                }
                let isApple = backend.apple
                let ready = state
                DispatchQueue.main.async {
                    guard self.epoch == generation, self.running, let index = self.displays.firstIndex(where: { $0.id == ready.id }) else { return }
                    self.displays[index] = ready
                    if isApple { self.appleIDs.insert(ready.id) }
                    if ready.preferences.restoreLastValues,
                       let saved = UserDefaults.standard.dictionary(forKey: "monitores.values.\(ready.persistentID)") as? [String: Double] {
                        for (key, value) in saved {
                            if let command = MonitorCommand(rawValue: key) { self.set(command, value: value, displayID: ready.id, synchronize: false) }
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                guard self.epoch == generation else { return }
                self.configureAppleObservation()
            }
        }
    }
    func updatePreferences(_ preferences: MonitorPreferences, displayID: UInt32) {
        guard let index = displays.firstIndex(where: { $0.id == displayID }) else { return }
        guard preferences.valid else { displays[index].error = "Confira os limites e códigos DDC da calibração."; return }
        let old = displays[index].preferences
        displays[index].preferences = preferences
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: "monitores.preferences.\(displays[index].persistentID)")
        }
        // Mudanças de transporte exigem leitura nova; preferências de apresentação não escrevem hardware.
        if old.mode != preferences.mode || old.softwareMethod != preferences.softwareMethod ||
            old.brightnessSwitchingPoint != preferences.brightnessSwitchingPoint ||
            old.brightnessCalibration != preferences.brightnessCalibration || old.contrastCalibration != preferences.contrastCalibration ||
            old.volumeCalibration != preferences.volumeCalibration || old.enableMute != preferences.enableMute {
            refresh()
        } else {
            displays[index].name = preferences.name.isEmpty ? (NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == displayID }?.localizedName ?? "Monitor") : preferences.name
            configureAppleObservation()
        }
    }
    func set(_ command: MonitorCommand, value: Double, displayID: UInt32, synchronize: Bool = true) {
        guard running, !sleeping, value.isFinite, let index = displays.firstIndex(where: { $0.id == displayID }), !displays[index].busy else { return }
        let value = min(1, max(0, value))
        let previous = displays[index].brightness
        switch command {
        case .brightness: displays[index].brightness = value
        case .contrast: guard displays[index].contrast != nil else { return }; displays[index].contrast = value
        case .volume: guard displays[index].volume != nil else { return }; displays[index].volume = value
        case .mute: guard displays[index].preferences.enableMute, displays[index].muteSupported, displays[index].volume != nil else { return }; displays[index].muted = value > 0
        }
        let state = displays[index]
        pending[displayID, default: [:]][command] = value
        let key = "\(displayID).\(command.rawValue)"
        let ticket = gate.ticket(key)
        let generation = epoch
        queue.asyncAfter(deadline: .now() + 0.025) {
            guard self.gate.accepts(ticket, key: key) else { return }
            let valid = { self.gate.accepts(ticket, key: key) }
            let success: Bool
            let software: Bool
            if let write = self.testWrite {
                success = write(displayID, command, value, valid)
                software = false
            } else if let backend = self.backends[displayID] {
                success = backend.setSmooth(command, value: value, preferences: state.preferences, valid: valid)
                software = backend.software
            } else { return }
            DispatchQueue.main.async {
                guard self.epoch == generation, self.gate.accepts(ticket, key: key), let current = self.displays.firstIndex(where: { $0.id == displayID }) else { return }
                self.displays[current].software = software
                if success { self.failed[displayID]?.remove(command) }
                else { self.failed[displayID, default: []].insert(command) }
                self.displays[current].error = (self.failed[displayID]?.isEmpty ?? true) ? nil : "O monitor não confirmou o ajuste. Tente novamente."
                if success {
                    self.pending[displayID]?[command] = nil
                    let prefKey = "monitores.values.\(state.persistentID)"
                    var saved = UserDefaults.standard.dictionary(forKey: prefKey) as? [String: Double] ?? [:]
                    saved[command.rawValue] = value
                    if self.testWrite == nil { UserDefaults.standard.set(saved, forKey: prefKey) }
                }
            }
        }
        if command == .brightness && synchronize {
            for (id, target) in MonitorRouting.relativeTargets(displays, source: displayID, delta: value - previous) {
                set(.brightness, value: target, displayID: id, synchronize: false)
            }
        }
    }
    func toggleMute(displayID: UInt32) {
        guard let state = displays.first(where: { $0.id == displayID }) else { return }
        set(.mute, value: state.muted ? 0 : 1, displayID: displayID)
    }
    func retry(displayID: UInt32) {
        if restorationError != nil { retryRestoration(); return }
        if let work = pending[displayID], !work.isEmpty {
            for (command, value) in work { set(command, value: value, displayID: displayID, synchronize: false) }
        } else { refresh() }
    }
    @discardableResult func handleKey(_ command: MonitorCommand, increase: Bool, fine: Bool) -> Bool {
        guard running, !sleeping else { return false }
        let id: UInt32?
        if command == .brightness || command == .contrast {
            id = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
        } else { id = MonitorRouting.audioTarget(displays, uid: Self.activeAudioUID()) }
        guard let id, let state = displays.first(where: { $0.id == id }), state.preferences.keyboardEnabled, !state.busy else { return false }
        if command == .brightness && state.preferences.mode == .hardware && !state.hardwareBrightness { return false }
        if command == .mute {
            guard state.preferences.enableMute, state.muteSupported else { return false }
            toggleMute(displayID: id)
        } else {
            if command == .contrast && state.contrast == nil { return false }
            let current = command == .brightness ? state.brightness : command == .contrast ? state.contrast ?? 0 : state.volume ?? 0
            set(command, value: current + (increase ? 1 : -1) * (fine ? 1.0 / 64 : 1.0 / 16), displayID: id)
        }
        if state.preferences.showHUD, let updated = displays.first(where: { $0.id == id }) { onHUD?(updated, command) }
        return true
    }
    private func configureAppleObservation() {
        appleTimer?.invalidate(); appleTimer = nil
        guard running, !sleeping, displays.filter({ $0.preferences.synchronize }).count > 1, displays.contains(where: { appleIDs.contains($0.id) && $0.preferences.synchronize }) else { return }
        // DisplayServices não publica notificações; só observamos quando a sincronização está em uso.
        appleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.observeAppleBrightness() }
    }
    private func observeAppleBrightness() {
        guard !appleReadPending else { return }
        appleReadPending = true
        let generation = epoch
        let participating = displays.filter { $0.preferences.synchronize && $0.preferences.mode != .software && pending[$0.id]?[.brightness] == nil }
        queue.async {
            let observed = participating.compactMap { state -> (UInt32, Double)? in
                guard let value = self.backends[state.id]?.appleBrightness() else { return nil }
                return (state.id, value)
            }
            DispatchQueue.main.async {
                guard generation == self.epoch else { return }
                self.appleReadPending = false
                for (id, value) in observed {
                    guard let index = self.displays.firstIndex(where: { $0.id == id }), self.pending[id]?[.brightness] == nil else { continue }
                    let delta = value - self.displays[index].brightness
                    guard abs(delta) > 0.005 else { continue }
                    self.displays[index].brightness = value
                    for (target, level) in MonitorRouting.relativeTargets(self.displays, source: id, delta: delta) {
                        self.set(.brightness, value: level, displayID: target, synchronize: false)
                    }
                }
            }
        }
    }
    private static func audioString(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value as String
    }
    private static func activeAudioUID() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return nil }
        return audioString(id, selector: kAudioDevicePropertyDeviceUID)
    }
    static func audioOutputs() -> [MonitorAudioOutput] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var output = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &output, 0, nil, &bytes) == noErr, bytes > 0,
                  let uid = audioString(id, selector: kAudioDevicePropertyDeviceUID), let name = audioString(id, selector: kAudioObjectPropertyName) else { return nil }
            return MonitorAudioOutput(id: uid, name: name)
        }
    }
}
