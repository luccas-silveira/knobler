import AppKit

// Dublês de serviço: eventos sintéticos nunca chegam a uma escrita física.
enum MonitorCommand { case brightness, volume, mute }
final class Monitores {
    static let shared = Monitores()
    var running = true
    var accepted = false
    var commands: [MonitorCommand] = []
    func handleKey(_ command: MonitorCommand, increase: Bool, fine: Bool) -> Bool {
        commands.append(command)
        return running && accepted
    }
}
final class AppSettings {
    static let shared = AppSettings()
    var volumeHUD = false
    var brightnessHUD = true
}
enum NotchViewModel {
    struct HUDState {
        enum Kind { case brightness, volume }
        var kind: Kind = .volume
        var level: Float
        var muted = false
    }
}

@main enum VolumeHUDCheck {
    static func main() {
        let controller = VolumeHUDController()
        func event(_ code: Int, down: Bool) -> CGEvent {
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8,
                               data1: (code << 16) | ((down ? 0xA : 0xB) << 8), data2: -1)!.cgEvent!
        }
        func passes(_ code: Int, down: Bool) -> Bool {
            guard let returned = controller.handle(event(code, down: down)) else { return false }
            _ = returned.takeRetainedValue()
            return true
        }
        // Tela excluída, ocupada ou sem backend: não acionar o fallback da tela interna.
        assert(passes(2, down: true))
        assert(passes(2, down: false))
        assert(passes(3, down: true))
        assert(passes(3, down: false))
        Monitores.shared.accepted = true
        assert(!passes(2, down: true))
        assert(!passes(2, down: false))
        // Desativar entre pressionar e soltar não vaza o keyUp que já foi consumido.
        assert(!passes(3, down: true))
        Monitores.shared.running = false
        assert(!passes(3, down: false))
        // O comportamento anterior de brilho volta; keyUp não executa escrita.
        assert(!passes(2, down: false))
        AppSettings.shared.brightnessHUD = false
        assert(passes(2, down: true))
        assert(passes(2, down: false))
        // Áudio sem associação mantém a rota normal (HUD desativado neste check).
        Monitores.shared.running = true
        Monitores.shared.accepted = false
        assert(passes(0, down: true))
        assert(passes(0, down: false))
        print("volumehudcheck: ok")
    }
}
