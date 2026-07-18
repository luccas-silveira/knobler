//
//  VolumeHUD.swift
//  Knobler
//
//  HUD de som e brilho: engole as teclas via CGEventTap (evento NX_SYSDEFINED,
//  type 14) e aplica volume via CoreAudio / brilho via DisplayServices — o OSD
//  nativo nunca aparece porque o sistema nunca vê a tecla. Mecânica do
//  boring.notch (MediaKeyInterceptor). Requer Acessibilidade.
//  Se o DisplayServices não resolver (framework privado), as teclas de brilho
//  passam direto pro sistema e só o HUD de som funciona.
//

import AppKit
import AudioToolbox
import CoreAudio

final class VolumeHUDController {
    var onHUD: ((NotchViewModel.HUDState) -> Void)?

    /// ⌥ direita (keycode 61) pressionada/solta — hold-to-talk do ditado.
    /// O evento sempre passa adiante: modificador sozinho não digita nada.
    var onRightOption: ((Bool) -> Void)?

    private static let systemDefinedEventType = CGEventType(rawValue: 14)!
    // keycodes NX: soundUp=0, soundDown=1, mute=7, brightnessUp=2, brightnessDown=3
    private static let volumeKeyCodes: Set<Int> = [0, 1, 7]
    private static let brightnessKeyCodes: Set<Int> = [2, 3]
    private static let step: Float32 = 1.0 / 16.0

    // DisplayServices (privado): resolvido em runtime pra falhar limpo
    private typealias BrightnessGet = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias BrightnessSet = @convention(c) (UInt32, Float) -> Int32
    private let brightnessGet: BrightnessGet?
    private let brightnessSet: BrightnessSet?

    init() {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY)
        brightnessGet = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
            .map { unsafeBitCast($0, to: BrightnessGet.self) }
        brightnessSet = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
            .map { unsafeBitCast($0, to: BrightnessSet.self) }
    }

    private var canControlBrightness: Bool {
        brightnessGet != nil && brightnessSet != nil
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    private var trustedAtCreation = false
    /// Ring de últimos eventos de tecla vistos (diagnóstico) — um slot único
    /// era sobrescrito por ruído de mouse antes de conseguirmos ler.
    private var keyLog: [String] = []
    private static let logTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.S"
        return f
    }()
    private func logKey(_ entry: String) {
        keyLog.append("\(Self.logTime.string(from: Date())) \(entry)")
        if keyLog.count > 12 { keyLog.removeFirst(keyLog.count - 12) }
    }
    private lazy var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private lazy var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    // A pílula aparece SÓ para mudanças iniciadas pelas nossas teclas.
    // Mudança externa (gesto no AirPods, slider da barra, outro app) já tem UI
    // do sistema — mostrar a nossa junto duplicava, e o card de dispositivo do
    // macOS não é interceptável (não é tecla).
    func start() {
        setupEventTap()
        // TCC pós-re-assinatura pode deixar o tap silenciosamente inerte, e a
        // permissão pode chegar DEPOIS do launch — health-check recria o tap
        // quando o estado de confiança muda (mitigação padrão pro problema)
        healthTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) {
            [weak self] _ in self?.checkTapHealth()
        }
        // diagnóstico: teclas de brilho de teclado externo podem chegar como
        // keyDown comum (F14/F15 etc.) em vez de NX systemDefined
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.logKey("kb=\(event.keyCode)")
        }
    }

    /// Estado do tap pro GET /status da API local (diagnóstico).
    var diagnostics: [String: Any] {
        [
            "axTrusted": AXIsProcessTrusted(),
            "tapExists": eventTap != nil,
            "tapEnabled": eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false,
            "brightnessAvailable": canControlBrightness,
            "keyLog": keyLog,
        ]
    }

    private func checkTapHealth() {
        let trusted = AXIsProcessTrusted()
        guard let eventTap else {
            if trusted { setupEventTap() }
            return
        }
        if trusted != trustedAtCreation {
            // identidade/permissão mudou desde a criação: tap pode estar inerte
            teardownTap()
            setupEventTap()
        } else if !CGEvent.tapIsEnabled(tap: eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func teardownTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
    }

    // MARK: - Event tap (teclas de volume)

    private func setupEventTap() {
        trustedAtCreation = AXIsProcessTrusted()
        let mask = CGEventMask(1 << Self.systemDefinedEventType.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, cgEvent, refcon in
                guard let refcon else { return Unmanaged.passRetained(cgEvent) }
                let controller = Unmanaged<VolumeHUDController>
                    .fromOpaque(refcon).takeUnretainedValue()
                return controller.handle(cgEvent)
            },
            userInfo: refcon
        )

        guard let eventTap else {
            NSLog("knobler: CGEventTap indisponível (Acessibilidade?) — HUD de som desligado")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handle(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if cgEvent.type == .tapDisabledByTimeout || cgEvent.type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passRetained(cgEvent)
        }
        if cgEvent.type == .flagsChanged {
            if cgEvent.getIntegerValueField(.keyboardEventKeycode) == 61 {
                // .maskAlternate é o estado agregado das duas ⌥: com a esquerda
                // segurada, soltar a direita ainda leria como press e prenderia
                // o ditado gravando. Lemos o bit device-específico da ⌥ direita
                // (NX_DEVICERALTKEYMASK = 0x40; a esquerda é 0x20).
                let pressed = cgEvent.flags.rawValue & 0x40 != 0
                DispatchQueue.main.async { [weak self] in
                    self?.onRightOption?(pressed)
                }
            }
            return Unmanaged.passRetained(cgEvent)
        }
        guard cgEvent.type != .null,
              let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined
        else {
            if cgEvent.type.rawValue == 14 { logKey("raw14-convfail") }
            return Unmanaged.passRetained(cgEvent)
        }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let stateByte = (data1 & 0xFF00) >> 8

        guard nsEvent.subtype.rawValue == 8 else {
            // subtipo 7 é botão de mouse — spam que afogaria o ring
            if nsEvent.subtype.rawValue != 7 {
                logKey("sd\(nsEvent.subtype.rawValue) data1=0x\(String(data1, radix: 16))")
            }
            return Unmanaged.passRetained(cgEvent)
        }
        if stateByte == 0xA { logKey("nx=\(keyCode)") }

        let isVolume = Self.volumeKeyCodes.contains(keyCode)
            && AppSettings.shared.volumeHUD
        let isBrightness = Self.brightnessKeyCodes.contains(keyCode)
            && canControlBrightness && AppSettings.shared.brightnessHUD
        guard isVolume || isBrightness else {
            return Unmanaged.passRetained(cgEvent)
        }

        // age no keyDown (0xA), mas engole keyUp também — o sistema nunca vê a tecla
        if stateByte == 0xA {
            let flags = nsEvent.modifierFlags
            let fine = flags.contains(.shift) && flags.contains(.option)
            let delta = Self.step / (fine ? 4 : 1)
            DispatchQueue.main.async { [weak self] in
                switch keyCode {
                case 0: self?.adjust(by: delta)
                case 1: self?.adjust(by: -delta)
                case 7: self?.toggleMute()
                case 2: self?.adjustBrightness(by: delta)
                case 3: self?.adjustBrightness(by: -delta)
                default: break
                }
            }
        }
        return nil
    }

    // MARK: - Brilho

    /// A tela principal pode ser um monitor externo sem DisplayServices —
    /// o brilho controlável é o da embutida.
    private static func builtinDisplay() -> CGDirectDisplayID {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) == 1 }
            ?? CGMainDisplayID()
    }

    private func adjustBrightness(by delta: Float) {
        guard let brightnessGet, let brightnessSet else { return }
        let display = Self.builtinDisplay()
        var current: Float = 0
        guard brightnessGet(display, &current) == 0 else { return }
        let target = max(0, min(1, current + delta))
        _ = brightnessSet(display, target)
        onHUD?(.init(kind: .brightness, level: target))
    }

    // MARK: - Ações

    // ponytail: publica o valor recém-escrito em vez de re-ler o HAL a cada tecla.
    //           se o write clampar/falhar o publicado pode divergir 1 passo (raro);
    //           upgrade: cache do device + listener de kAudioHardwarePropertyDefaultOutputDevice.
    private func adjust(by delta: Float32) {
        let device = Self.defaultOutputDevice()
        guard device != kAudioObjectUnknown, let current = readVolume(device) else {
            publishCurrentState()
            return
        }
        var muted = readMute(device) ?? false
        if muted, delta > 0 { writeMute(device, false); muted = false }
        let target = max(0, min(1, current + delta))
        writeVolume(device, target)
        if target == 0, !muted { writeMute(device, true); muted = true }
        onHUD?(.init(kind: .volume, level: muted ? 0 : target, muted: muted))
    }

    private func toggleMute() {
        let device = Self.defaultOutputDevice()
        guard device != kAudioObjectUnknown else { return }
        let muted = !(readMute(device) ?? false)
        writeMute(device, muted)
        let level = readVolume(device) ?? 0
        onHUD?(.init(kind: .volume, level: muted ? 0 : level, muted: muted))
    }

    /// Fallback: só quando a leitura inicial do volume falha em `adjust`.
    private func publishCurrentState() {
        let device = Self.defaultOutputDevice()
        guard device != kAudioObjectUnknown else { return }
        let muted = readMute(device) ?? false
        let level = readVolume(device) ?? 0
        onHUD?(.init(kind: .volume, level: muted ? 0 : level, muted: muted))
    }


    // MARK: - CoreAudio

    private static func defaultOutputDevice() -> AudioObjectID {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func readVolume(_ device: AudioObjectID) -> Float32? {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &value) == noErr
        else { return nil }
        return value
    }

    private func writeVolume(_ device: AudioObjectID, _ value: Float32) {
        var value = value
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, size, &value)
    }

    private func readMute(_ device: AudioObjectID) -> Bool? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &value) == noErr
        else { return nil }
        return value == 1
    }

    private func writeMute(_ device: AudioObjectID, _ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(device, &muteAddress, 0, nil, size, &value)
    }
}
