import AppKit

// Transportes indisponíveis neste executável: o serviço real usa apenas a escrita injetada.
enum Arm64DDC {
    static let isArm64 = false
    static func getServiceMatches(displayIDs: [UInt32]) -> [(displayID: UInt32, service: Int)] { [] }
}
final class MonitorDisplay {
    let apple = false, hardwareBrightness = false, software = false
    init(id: UInt32, arm: Int?) { assertionFailure("Self-check não deve acessar telas") }
    func restoreSoftware() -> Bool { true }
    func appleBrightness() -> Double? { nil }
    func readInitial(preferences: MonitorPreferences, valid: () -> Bool) -> (values: [MonitorCommand: Double], maxima: [MonitorCommand: Double]) { ([:], [:]) }
    func setSmooth(_ command: MonitorCommand, value: Double, preferences: MonitorPreferences, valid: () -> Bool) -> Bool { false }
}
enum KeyboardShortcuts {
    struct Name { init(_ value: String) {} }
    static func enable(_ name: Name) {}
    static func onKeyDown(for name: Name, action: @escaping () -> Void) {}
    static var removidosTodos = 0, removidosPorNome = 0
    static func removeAllHandlers() { removidosTodos += 1 }
    static func removeHandlers(for name: Name) { removidosPorNome += 1 }
}

@main struct MonitorServiceChecks {
    static func wait(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        assert(condition(), "A fila não concluiu no prazo")
    }
    static func main() {
        var one = MonitorState(id: 1, persistentID: "test-one", name: "Um", brightness: 0.3)
        var two = MonitorState(id: 2, persistentID: "test-two", name: "Dois", brightness: 0.6)
        one.preferences.synchronize = true
        two.preferences.synchronize = true
        let lock = NSLock()
        var writes: [(UInt32, Double)] = []
        var succeeds = false
        var restores = false
        let service = Monitores(testDisplays: [one, two], restore: {
            lock.lock(); defer { lock.unlock() }; return restores
        }) { id, command, value, valid in
            assert(command == .brightness && valid())
            lock.lock(); defer { lock.unlock() }
            writes.append((id, value))
            return succeeds
        }
        func count() -> Int { lock.lock(); defer { lock.unlock() }; return writes.count }
        service.set(.brightness, value: 0.4, displayID: 1)
        service.set(.brightness, value: 0.5, displayID: 1)
        wait { service.displays.allSatisfy { $0.error != nil } }
        assert(count() == 2, "Agrupa cada monitor, sem realimentar a origem")
        assert(abs(service.displays[1].brightness - 0.8) < 0.00001)
        lock.lock(); succeeds = true; lock.unlock()
        service.retry(displayID: 1)
        service.retry(displayID: 2)
        wait { service.displays.allSatisfy { $0.error == nil } }
        assert(count() == 4, "A mesma escrita deve ser repetida após falha")
        lock.lock()
        assert(writes[0].0 == 1 && writes[2].0 == 1 && writes[0].1 == writes[2].1)
        assert(writes[1].0 == 2 && writes[3].0 == 2 && writes[1].1 == writes[3].1)
        lock.unlock()
        // Parar os Monitores não pode derrubar atalho de outra peça (⌃⇧T do Texto da tela).
        service.stop()
        assert(KeyboardShortcuts.removidosTodos == 0, "stop() apagou os atalhos de todo mundo")
        assert(KeyboardShortcuts.removidosPorNome == Monitores.shortcutNames.count)
        service.set(.brightness, value: 0.9, displayID: 1)
        var stopped: Bool?
        service.stop { stopped = $0 }
        wait { stopped != nil }
        assert(stopped == false && service.restorationError != nil)
        assert(count() == 4 && service.displays.isEmpty, "Desativar invalida escritas pendentes")
        lock.lock(); restores = true; lock.unlock()
        stopped = nil
        service.stop { stopped = $0 }
        wait { stopped != nil }
        assert(stopped == true && service.restorationError == nil, "Pode repetir restauração após parar")
        var started = false
        var cancelled = false
        let inFlight = Monitores(testDisplays: [one]) { _, _, _, valid in
            lock.lock(); started = true; lock.unlock()
            let deadline = Date().addingTimeInterval(2)
            while valid(), Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
            lock.lock(); cancelled = !valid(); lock.unlock()
            return false
        }
        inFlight.set(.brightness, value: 0.8, displayID: 1)
        wait { lock.lock(); defer { lock.unlock() }; return started }
        stopped = nil
        inFlight.stop { stopped = $0 }
        wait { stopped != nil }
        lock.lock(); assert(cancelled); lock.unlock()
        assert(stopped == true, "Escrita em curso deve observar cancelamento antes de concluir a parada")
        // O reprobe de desconexão e a suspensão usam os mesmos caminhos de produção.
        for suspend in [false, true] {
            var lifecycleWrites = 0
            let lifecycle = Monitores(testDisplays: [one], screens: { [] }) { _, _, _, _ in
                lock.lock(); lifecycleWrites += 1; lock.unlock()
                return true
            }
            lifecycle.set(.brightness, value: 0.9, displayID: 1)
            if suspend { lifecycle.suspend() } else { lifecycle.refresh() }
            // Tenta inserir novo trabalho após dormir; suspend deve recusar também este.
            if suspend { lifecycle.set(.brightness, value: 0.4, displayID: 1) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            lock.lock(); assert(lifecycleWrites == 0); lock.unlock()
            if !suspend { assert(lifecycle.displays.isEmpty) }
            lifecycle.stop()
        }
        print("Monitores serviço: agrupamento, repetição, sincronização e restauração OK")
    }
}
