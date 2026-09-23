// Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others.
// Adaptação de Display, AppleDisplay, OtherDisplay e DisplayManager 4.4.0 para Knobler.
// Sem AppDelegate, menus ou OSD. A fila e o ciclo de vida pertencem a Monitores.
import AppKit
import IOKit

final class MonitorDisplay {
    let id: CGDirectDisplayID
    let apple: Bool
    private let intel: IntelDDC?
    private let arm: IOAVService?
    private var red = [CGGammaValue](repeating: 0, count: 256)
    private var green = [CGGammaValue](repeating: 0, count: 256)
    private var blue = [CGGammaValue](repeating: 0, count: 256)
    private var samples: UInt32 = 0
    private var gammaChanged = false
    private var shade: NSWindow?
    private var applied: [MonitorCommand: UInt16] = [:]
    var values: [MonitorCommand: Double] = [:]
    var hardwareBrightness = false
    var software = false

    init(id: UInt32, arm: IOAVService?) {
        self.id = id
        self.arm = arm
        var brightness: Float = -1
        apple = DisplayServicesGetBrightness(id, &brightness) == 0 && brightness >= 0
        intel = !apple && !Arm64DDC.isArm64 ? IntelDDC(for: id) : nil
        if apple { values[.brightness] = Double(brightness); hardwareBrightness = true }
        CGGetDisplayTransferByTable(id, 256, &red, &green, &blue, &samples)
    }

    var hasDDC: Bool { arm != nil || intel != nil }
    private func code(_ command: MonitorCommand) -> UInt8 {
        switch command {
        case .brightness: return Command.brightness.rawValue
        case .contrast: return Command.contrast.rawValue
        case .volume: return Command.audioSpeakerVolume.rawValue
        case .mute: return Command.audioMuteScreenBlank.rawValue
        }
    }
    func read(_ command: MonitorCommand, preferences p: MonitorPreferences) -> (UInt16, UInt16)? {
        guard let codes = p.calibration(command).codes(default: code(command)), let code = codes.first else { return nil }
        if Arm64DDC.isArm64 {
            return Arm64DDC.read(service: arm, command: code, readSleepTime: UInt32(p.delayMilliseconds * 1000), numOfRetryAttemps: UInt8(p.attempts))
        }
        return intel?.read(command: code, tries: UInt(p.attempts), minReplyDelay: UInt64(p.delayMilliseconds * 1_000_000))
    }
    func readInitial(preferences p: MonitorPreferences, valid: () -> Bool = { true }) -> (values: [MonitorCommand: Double], maxima: [MonitorCommand: Double]) {
        var maxima: [MonitorCommand: Double] = [:]
        if hasDDC && p.mode != .software {
            for command in [MonitorCommand.brightness, .contrast, .volume, .mute] {
                guard valid() else { break }
                if command == .mute && !p.enableMute { continue }
                if let (raw, maximum) = read(command, preferences: p), maximum > 0 || (command == .mute && (raw == 1 || raw == 2)) {
                    var calibration = p.calibration(command)
                    if calibration.maximum == 100 { calibration.maximum = Double(maximum) }
                    values[command] = command == .mute ? (raw == 1 ? 1 : 0) : calibration.decode(raw)
                    maxima[command] = Double(maximum)
                    if command == .brightness { hardwareBrightness = true }
                }
            }
        }
        // A escala combinada do MonitorControl reserva a metade inferior para software.
        if hardwareBrightness && !apple && p.mode == .automatic, let value = values[.brightness] {
            values[.brightness] = p.brightnessSwitchingPoint + value * (1 - p.brightnessSwitchingPoint)
        }
        if p.mode == .software || !hardwareBrightness { values[.brightness] = 1; software = p.mode != .hardware }
        return (values, maxima)
    }
    func appleBrightness() -> Double? {
        guard apple else { return nil }
        var value: Float = 0
        return DisplayServicesGetBrightness(id, &value) == 0 ? Double(value) : nil
    }
    private func write(_ command: MonitorCommand, raw: UInt16, preferences p: MonitorPreferences, valid: () -> Bool) -> Bool {
        guard valid(), let codes = p.calibration(command).codes(default: code(command)) else { return false }
        if applied[command] == raw { return true }
        applied[command] = nil // Falha parcial também invalida o valor confirmado anterior.
        for code in codes {
            var success = false
            for _ in 0..<p.attempts {
                guard valid() else { return false }
                if Arm64DDC.isArm64 {
                    success = Arm64DDC.write(service: arm, command: code, value: raw, writeSleepTime: UInt32(p.delayMilliseconds * 1000), numOfRetryAttemps: 0)
                } else {
                    success = intel?.write(command: code, value: raw, errorRecoveryWaitTime: 2000, writeSleepTime: UInt32(p.delayMilliseconds * 1000)) ?? false
                }
                if success { break }
            }
            guard success else { return false }
        }
        // Só uma escrita confirmada pode suprimir uma repetição do mesmo valor.
        applied[command] = raw
        return true
    }
    // Passos de Display.setSmoothBrightness do upstream; canceláveis entre cada escrita.
    func setSmooth(_ command: MonitorCommand, value: Double, preferences p: MonitorPreferences, valid: () -> Bool) -> Bool {
        guard command == .brightness else { return set(command, value: value, preferences: p, valid: valid) }
        var current = values[.brightness] ?? value
        while abs(current - value) >= 0.01 {
            guard valid() else { return false }
            let delta = value - current
            current += (delta > 0 ? 1 : -1) * max(abs(delta) / 6, 0.01)
            guard set(command, value: current, preferences: p, valid: valid) else { return false }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return set(command, value: value, preferences: p, valid: valid)
    }
    func set(_ command: MonitorCommand, value: Double, preferences p: MonitorPreferences, valid: () -> Bool) -> Bool {
        guard value.isFinite, p.valid, valid() else { return false }
        let value = min(1, max(0, value))
        if command != .brightness {
            guard hasDDC, p.mode != .software else { return false }
            let raw = command == .mute ? UInt16(value > 0 ? 1 : 2) : p.calibration(command).encode(value, volume: command == .volume)
            guard write(command, raw: raw, preferences: p, valid: valid) else { return false }
            values[command] = value
            return true
        }
        if p.mode == .software || !hardwareBrightness {
            guard p.mode != .hardware, setSoftware(value, preferences: p, valid: valid) else { return false }
            software = true
        } else if apple {
            guard valid(), DisplayServicesSetBrightness(id, Float(value)) == 0 else { return false }
            guard setSoftware(1, preferences: p, valid: valid) else { return false }
            software = false
        } else {
            let hardware = p.mode == .automatic ? max(0, (value - p.brightnessSwitchingPoint) / (1 - p.brightnessSwitchingPoint)) : value
            let dimming = p.mode == .automatic ? min(1, value / p.brightnessSwitchingPoint) : 1
            guard write(.brightness, raw: p.brightnessCalibration.encode(hardware), preferences: p, valid: valid),
                  setSoftware(dimming, preferences: p, valid: valid) else { return false }
            software = dimming < 1
        }
        values[command] = value
        return true
    }
    private func setSoftware(_ value: Double, preferences p: MonitorPreferences, valid: () -> Bool) -> Bool {
        guard valid() else { return false }
        let floor = p.allowZeroBrightness ? 0.0 : 0.15
        let transformed = Float(value * (1 - floor) + floor)
        if p.softwareMethod == .overlay {
            if gammaChanged && !restoreGamma() { return false }
            var success = false
            DispatchQueue.main.sync {
                guard valid() else { return }
                if value == 1 { self.shade?.orderOut(nil); success = true; return }
                guard CGDisplayMirrorsDisplay(self.id) == 0,
                      let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == self.id }) else { return }
                if self.shade == nil {
                    let shade = NSWindow(contentRect: screen.frame, styleMask: [], backing: .buffered, defer: false)
                    shade.isReleasedWhenClosed = false
                    shade.backgroundColor = .black
                    shade.ignoresMouseEvents = true
                    shade.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
                    shade.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle]
                    self.shade = shade
                }
                self.shade?.setFrame(screen.frame, display: true)
                self.shade?.alphaValue = CGFloat(1 - transformed)
                self.shade?.orderFrontRegardless()
                success = true
            }
            return success
        }
        DispatchQueue.main.sync { self.shade?.orderOut(nil) }
        if value == 1 && !gammaChanged { return true }
        guard samples > 0 else { return false }
        let result = CGSetDisplayTransferByTable(id, samples, red.map { $0 * transformed }, green.map { $0 * transformed }, blue.map { $0 * transformed })
        if result == .success { gammaChanged = value < 1 }
        return result == .success
    }
    private func restoreGamma() -> Bool {
        guard gammaChanged, samples > 0 else { return true }
        if CGDisplayIsOnline(id) == 0 { gammaChanged = false; return true }
        guard CGSetDisplayTransferByTable(id, samples, red, green, blue) == .success else { return false }
        gammaChanged = false
        return true
    }
    func restoreSoftware() -> Bool {
        var restored = false
        for _ in 0..<3 {
            if restoreGamma() { restored = true; break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        DispatchQueue.main.sync { self.shade?.close(); self.shade = nil }
        return restored
    }
}
