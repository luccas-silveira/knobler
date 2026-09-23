//
//  AirDropProgresso.swift
//  Knobler
//
//  Progresso de recebimento: o sistema publica um `NSProgress` por arquivo que
//  chega em ~/Downloads (é o mesmo que o Finder desenha no ícone). Confirmado
//  ao vivo em 2026-09-23: kind `NSProgressFileOperationKindReceiving`, ~6
//  atualizações por segundo. Envio não publica nada — ver AirDropEnvio.
//

import Foundation

final class AirDropProgresso {
    var onFracao: ((URL, Double) -> Void)?
    var onFim: ((URL) -> Void)?

    private var assinatura: Any?
    private var observacoes: [URL: NSKeyValueObservation] = [:]

    func iniciar() {
        guard assinatura == nil else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        assinatura = Progress.addSubscriber(forFileURL: downloads) { [weak self] progresso in
            // só recebimento: download do Safari/Chrome também publica aqui
            guard let self,
                  progresso.userInfo[.fileOperationKindKey] as? Progress.FileOperationKind == .receiving,
                  let url = progresso.userInfo[.fileURLKey] as? URL
            else { return nil }
            self.observacoes[url] = progresso.observe(\.fractionCompleted, options: [.initial]) { p, _ in
                let f = p.fractionCompleted
                DispatchQueue.main.async { self.onFracao?(url, f) }
            }
            return { [weak self] in
                DispatchQueue.main.async {
                    self?.observacoes[url] = nil
                    self?.onFim?(url)
                }
            }
        }
    }

    func parar() {
        if let assinatura { Progress.removeSubscriber(assinatura) }
        assinatura = nil
        observacoes = [:]
    }
}
