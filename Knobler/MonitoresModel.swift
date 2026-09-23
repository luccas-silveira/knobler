// Conversões adaptadas de MonitorControl 4.4.0 (OtherDisplay.swift); licença em Vendor/MonitorControl.
import Foundation

enum MonitorCommand: String, Codable, CaseIterable { case brightness, contrast, volume, mute }
enum MonitorControlMode: String, Codable, CaseIterable { case automatic, hardware, software }
enum MonitorSoftwareMethod: String, Codable, CaseIterable { case gamma, overlay }

struct MonitorCalibration: Codable, Equatable {
    var minimum: Double = 0
    var maximum: Double = 100
    var curve: Int = 5
    var inverted = false
    var remap = ""
    var exponent: Double { [1: 0.6, 2: 0.7, 3: 0.8, 4: 0.9, 6: 1.3, 7: 1.5, 8: 1.7, 9: 1.88][curve] ?? 1 }
    var valid: Bool { minimum.isFinite && maximum.isFinite && minimum >= 0 && maximum <= 65535 && minimum < maximum }
    func encode(_ value: Double, volume: Bool = false) -> UInt16 {
        guard valid, value.isFinite else { return 0 }
        let unit = min(1, max(0, inverted ? 1 - value : value))
        let raw = UInt16(min(maximum, max(minimum, (maximum - minimum) * pow(unit, exponent) + minimum)))
        return volume && value > 0 ? max(1, raw) : raw
    }
    func decode(_ value: UInt16) -> Double {
        guard valid else { return 0 }
        let unit = pow((min(max(Double(value), minimum), maximum) - minimum) / (maximum - minimum), 1 / exponent)
        return inverted ? 1 - unit : unit
    }
    func codes(default code: UInt8) -> [UInt8]? {
        guard !remap.trimmingCharacters(in: .whitespaces).isEmpty else { return [code] }
        let parts = remap.split(separator: ",", omittingEmptySubsequences: false)
        let codes = parts.compactMap { UInt8($0.trimmingCharacters(in: .whitespaces), radix: 16) }.filter { $0 != 0 }
        return codes.count == parts.count ? codes : nil
    }
}

struct MonitorPreferences: Codable, Equatable {
    var name = ""
    var keyboardEnabled = true
    var audioDeviceUID = ""
    var mode = MonitorControlMode.automatic
    var softwareMethod = MonitorSoftwareMethod.gamma
    var synchronize = false
    var showHUD = true
    var restoreLastValues = false
    var allowZeroBrightness = false
    var enableMute = true
    var brightnessSwitchingPoint = 0.5
    var brightnessCalibration = MonitorCalibration()
    var contrastCalibration = MonitorCalibration()
    var volumeCalibration = MonitorCalibration()
    var attempts = 3
    var delayMilliseconds = 50
    func calibration(_ command: MonitorCommand) -> MonitorCalibration {
        switch command {
        case .brightness: return brightnessCalibration
        case .contrast: return contrastCalibration
        case .volume: return volumeCalibration
        case .mute: return MonitorCalibration()
        }
    }
    var valid: Bool {
        brightnessSwitchingPoint.isFinite && (0.0625...0.9375).contains(brightnessSwitchingPoint) &&
        (1...20).contains(attempts) && (1...1000).contains(delayMilliseconds) &&
        [brightnessCalibration, contrastCalibration, volumeCalibration].allSatisfy { $0.valid && $0.codes(default: 0x10) != nil }
    }
}

struct MonitorState: Identifiable, Equatable {
    var id: UInt32
    var persistentID: String
    var name: String
    var brightness: Double = 1
    var contrast: Double?
    var volume: Double?
    var muted = false
    var muteSupported = false
    var software = false
    var error: String?
    var preferences = MonitorPreferences()
    var hardwareBrightness = false
    var busy = false
}

struct MonitorAudioOutput: Identifiable { var id: String; var name: String }

// A geração cancela trabalhos ainda não iniciados; a revisão agrupa eventos do mesmo controle.
final class MonitorWorkGate {
    private let lock = NSLock()
    private var generation = 0
    private var revisions: [String: Int] = [:]
    func invalidate() { lock.lock(); defer { lock.unlock() }; generation += 1; revisions.removeAll() }
    func ticket(_ key: String) -> (Int, Int) {
        lock.lock(); defer { lock.unlock() }
        revisions[key, default: 0] += 1
        return (generation, revisions[key]!)
    }
    func accepts(_ ticket: (Int, Int), key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == ticket.0 && revisions[key] == ticket.1
    }
}

enum MonitorRouting {
    static func audioTarget(_ displays: [MonitorState], uid: String?) -> UInt32? {
        guard let uid, !uid.isEmpty else { return nil }
        let matches = displays.filter { $0.preferences.keyboardEnabled && $0.volume != nil && $0.preferences.audioDeviceUID == uid }
        return matches.count == 1 ? matches[0].id : nil
    }
    static func relativeTargets(_ displays: [MonitorState], source: UInt32, delta: Double) -> [(UInt32, Double)] {
        guard displays.contains(where: { $0.id == source && $0.preferences.synchronize }) else { return [] }
        return displays.filter { $0.id != source && $0.preferences.synchronize }.map { ($0.id, min(1, max(0, $0.brightness + delta))) }
    }
}

// Resposta VCP: valida o pacote antes de anunciar capacidades ou valores físicos.
enum MonitorDDCReply {
    static func decode(_ bytes: [UInt8], command: UInt8) -> (current: UInt16, maximum: UInt16)? {
        guard bytes.count == 11, bytes[2] == 2, bytes[3] == 0, bytes[4] == command,
              bytes.dropLast().reduce(UInt8(0x50), ^) == bytes[10] else { return nil }
        return ((UInt16(bytes[8]) << 8) | UInt16(bytes[9]), (UInt16(bytes[6]) << 8) | UInt16(bytes[7]))
    }
}
