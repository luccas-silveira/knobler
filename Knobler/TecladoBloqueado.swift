// Bloqueio de teclado pra limpeza: engole todo evento de teclado enquanto ativo.
// Estado só em memória — crash ou saída do app libera o teclado.
import AppKit
import Carbon
import CoreGraphics

final class TecladoBloqueado: ObservableObject {
    static let shared = TecladoBloqueado()

    enum Recusa { case semAcessibilidade, entradaSegura }

    @Published private(set) var ativo = false
    private var tap: CFMachPort?
    private var fonte: CFRunLoopSource?

    private static let systemDefined = CGEventType(rawValue: 14)!

    static func deveEngolir(_ tipo: CGEventType) -> Bool {
        tipo == .keyDown || tipo == .keyUp || tipo == .flagsChanged || tipo == systemDefined
    }

    /// Devolve o motivo quando não liga.
    @discardableResult
    func ligar() -> Recusa? {
        if ativo { return nil }
        // Com campo de senha focado o macOS entrega as teclas por fora do tap.
        if IsSecureEventInputEnabled() { return .entradaSegura }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, Self.systemDefined]
            .reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, tipo, evento, refcon in
                guard let refcon else { return Unmanaged.passRetained(evento) }
                let eu = Unmanaged<TecladoBloqueado>.fromOpaque(refcon).takeUnretainedValue()
                if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
                    if let tap = eu.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passRetained(evento)
                }
                return TecladoBloqueado.deveEngolir(tipo) ? nil : Unmanaged.passRetained(evento)
            },
            userInfo: refcon)
        else { return .semAcessibilidade }
        let fonte = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), fonte, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.fonte = fonte
        ativo = true
        return nil
    }

    func desligar() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let fonte { CFRunLoopRemoveSource(CFRunLoopGetMain(), fonte, .commonModes) }
        tap = nil
        fonte = nil
        ativo = false
    }

    /// Só pro harness de snapshot: liga o estado sem criar tap.
    func _simularAtivo(_ v: Bool) { ativo = v }
}
