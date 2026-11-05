import Foundation

/// Conta quantas gravações do próprio Knobler estão com o microfone aberto
/// (ditado e gravação de áudio no notch, que reusam o `MicRecorder`).
///
/// O silêncio por microfone usa isto pra não confundir o nosso uso com uma
/// chamada: enquanto `ativo`, não silencia; depois, conta o limiar a partir de
/// `terminouEm`. Lock porque o gravador pode ser parado fora da main.
final class UsoProprioDoMicrofone {
    static let shared = UsoProprioDoMicrofone()

    private let lock = NSLock()
    private var abertos = 0
    private var fim: Date?

    func comecou() {
        lock.lock()
        abertos += 1
        lock.unlock()
    }

    /// `terminou()` sem `comecou()` correspondente é ignorado: o contador não
    /// fica negativo.
    func terminou(agora: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        guard abertos > 0 else { return }
        abertos -= 1
        if abertos == 0 { fim = agora }
    }

    var ativo: Bool {
        lock.lock()
        defer { lock.unlock() }
        return abertos > 0
    }

    /// Fim do último uso próprio; `nil` = nunca usou nesta execução.
    var terminouEm: Date? {
        lock.lock()
        defer { lock.unlock() }
        return fim
    }
}
