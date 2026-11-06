import AVFoundation

// A fonte de verdade da nota de voz: o gravador do ditado (`MicRecorder`,
// Knobler/Dictation.swift), que já grava pelo mic embutido com fone Bluetooth,
// aguenta troca de dispositivo e a `NSException` do `installTap`, e marca o
// uso próprio do microfone (gravar não silencia os cards). Só o app compila
// este arquivo: o Dictation.swift importa FluidAudio.

final class MicrofoneDoDitado: WAFonteDeMicrofone {
    private var gravador: MicRecorder?

    /// Sem decisão do usuário ainda, pede o acesso e não grava (como o ditado):
    /// a próxima tentativa, já concedida, começa.
    func comecar(nivel: @escaping (Float) -> Void) throws {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            throw NSError(domain: "MicrofoneDoDitado", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "acesso ao microfone pedido"])
        }
        let g = MicRecorder()
        g.onLevel = nivel
        try g.start()
        gravador = g
    }

    func parar() -> [Float] {
        defer { gravador = nil }
        return gravador?.stop() ?? []
    }
}
