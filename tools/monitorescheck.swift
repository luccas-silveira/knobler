import Foundation

@main struct MonitorChecks {
    static func main() {
        var calibration = MonitorCalibration()
        for curve in 1...9 {
            calibration.curve = curve
            for step in 0...100 {
                let value = Double(step) / 100
                let raw = calibration.encode(value)
                assert(raw <= 100)
                assert(abs(calibration.decode(raw) - value) < 0.15)
            }
        }
        calibration = MonitorCalibration(minimum: 10, maximum: 90, curve: 5, inverted: true)
        assert(calibration.encode(0) == 90 && calibration.encode(1) == 10)
        assert(calibration.decode(50) == 0.5)
        calibration.remap = "10, 6B"
        assert(calibration.codes(default: 0x10) == [0x10, 0x6B])
        calibration.remap = "10,zz"
        assert(calibration.codes(default: 0x10) == nil)
        calibration.minimum = .nan
        assert(!calibration.valid && calibration.encode(0.5) == 0)
        var reply: [UInt8] = [0x6E, 0x88, 2, 0, 0x10, 0, 1, 255, 1, 12, 0]
        reply[10] = reply.dropLast().reduce(UInt8(0x50), ^)
        let decoded = MonitorDDCReply.decode(reply, command: 0x10)!
        assert(decoded.current == 268 && decoded.maximum == 511)
        assert(MonitorDDCReply.decode(reply, command: 0x12) == nil)
        reply[10] ^= 1
        assert(MonitorDDCReply.decode(reply, command: 0x10) == nil)
        assert(MonitorDDCReply.decode([], command: 0x10) == nil)
        let gate = MonitorWorkGate()
        let old = gate.ticket("brightness")
        let latest = gate.ticket("brightness")
        assert(!gate.accepts(old, key: "brightness") && gate.accepts(latest, key: "brightness"))
        gate.invalidate() // desconexão, suspensão e desativação descartam inclusive o último trabalho
        assert(!gate.accepts(latest, key: "brightness"))
        var one = MonitorState(id: 1, persistentID: "one", name: "Um", brightness: 0.3, volume: 0.5)
        var two = MonitorState(id: 2, persistentID: "two", name: "Dois", brightness: 0.7, volume: 0.2)
        one.preferences.audioDeviceUID = "speakers"
        assert(MonitorRouting.audioTarget([one, two], uid: "speakers") == 1)
        two.preferences.audioDeviceUID = "speakers"
        assert(MonitorRouting.audioTarget([one, two], uid: "speakers") == nil)
        assert(MonitorRouting.audioTarget([one, two], uid: nil) == nil)
        assert(MonitorRouting.relativeTargets([one, two], source: 1, delta: 0.1).isEmpty)
        one.preferences.synchronize = true; two.preferences.synchronize = true
        let targets = MonitorRouting.relativeTargets([one, two], source: 1, delta: 0.1)
        assert(targets.count == 1 && targets[0].0 == 2 && abs(targets[0].1 - 0.8) < 0.0001)
        assert(MonitorRouting.relativeTargets([one, two], source: 1, delta: 1)[0].1 == 1)
        var remapped = MonitorPreferences()
        remapped.volumeCalibration.remap = "62,63"
        assert(remapped.calibration(.mute).codes(default: 0x8D) == [0x8D])
        let data = try! JSONEncoder().encode(one.preferences)
        assert(try! JSONDecoder().decode(MonitorPreferences.self, from: data) == one.preferences)
        print("Monitores: calibração, roteamento, sincronização relativa e invalidação OK")
    }
}
