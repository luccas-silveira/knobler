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
    }

    // MARK: - Event tap (teclas de volume)

    private func setupEventTap() {
        let mask = CGEventMask(1 << Self.systemDefinedEventType.rawValue)
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
        guard cgEvent.type != .null,
              let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8
        else { return Unmanaged.passRetained(cgEvent) }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let stateByte = (data1 & 0xFF00) >> 8

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

    private func adjustBrightness(by delta: Float) {
        guard let brightnessGet, let brightnessSet else { return }
        let display = CGMainDisplayID()
        var current: Float = 0
        guard brightnessGet(display, &current) == 0 else { return }
        let target = max(0, min(1, current + delta))
        _ = brightnessSet(display, target)
        onHUD?(.init(kind: .brightness, level: target))
    }

    // MARK: - Ações

    private func adjust(by delta: Float32) {
        let device = Self.defaultOutputDevice()
        guard device != kAudioObjectUnknown, let current = readVolume(device) else {
            publishCurrentState()
            return
        }
        if readMute(device) == true, delta > 0 {
            writeMute(device, false)
        }
        let target = max(0, min(1, current + delta))
        writeVolume(device, target)
        if target == 0 { writeMute(device, true) }
        publishCurrentState()
    }

    private func toggleMute() {
        let device = Self.defaultOutputDevice()
        guard device != kAudioObjectUnknown else { return }
        writeMute(device, !(readMute(device) ?? false))
        publishCurrentState()
    }

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
