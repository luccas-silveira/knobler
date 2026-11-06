import AVFoundation
import Combine
import Foundation
import os

// Tocador do áudio recebido no WhatsApp. Um áudio por vez no app inteiro:
// tocar outro para o anterior. O Ogg Opus da ponte abre direto no
// `AVAudioPlayer` desta máquina (A71); no 14.2 não é garantido, o que não
// importa para uso pessoal (spec, "Áudio").

private let log = Logger(subsystem: "com.zoi.knobler", category: "whatsapp")

@MainActor
protocol WATocador: AnyObject {
    var aoTerminar: (() -> Void)? { get set }
    var duracao: TimeInterval { get }
    var tempo: TimeInterval { get }
    func tocar() -> Bool
    func pausar()
}

@MainActor
final class WATocadorAVAudio: NSObject, WATocador, AVAudioPlayerDelegate {
    var aoTerminar: (() -> Void)?
    private let player: AVAudioPlayer

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
        player.prepareToPlay()
    }

    var duracao: TimeInterval { player.duration }
    var tempo: TimeInterval { player.currentTime }
    func tocar() -> Bool { player.play() }
    func pausar() { player.pause() }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        aoTerminar?()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        log.error("WhatsApp: áudio não decodificou — \(String(describing: error), privacy: .public)")
        aoTerminar?()
    }
}

@MainActor
final class WAPlayer: ObservableObject {
    static let shared = WAPlayer()

    /// Id da mensagem tocando agora; `nil` parado ou pausado.
    @Published private(set) var tocando: String?
    /// 0…1 do áudio atual (pausado mantém onde parou).
    @Published private(set) var progresso: Double = 0

    private let fabrica: @MainActor (URL) throws -> WATocador
    private var atual: (id: String, tocador: WATocador)?
    private var relogio: Task<Void, Never>?
    /// Sobe a cada áudio novo: o fim de um áudio trocado não mexe no atual.
    private var sessao: UInt64 = 0

    init(fabrica: @escaping @MainActor (URL) throws -> WATocador = { try WATocadorAVAudio(url: $0) }) {
        self.fabrica = fabrica
    }

    /// Toca `url` como a mensagem `id`. Mesmo `id` pausado retoma de onde parou.
    func tocar(url: URL, id: String) {
        if let a = atual, a.id == id {
            guard tocando != id else { return }
            if a.tocador.tocar() {
                tocando = id
                acompanhar()
            }
            return
        }
        encerrar()
        let t: WATocador
        do {
            t = try fabrica(url)
        } catch {
            log.error("WhatsApp: áudio não abriu — \(String(describing: error), privacy: .public)")
            return
        }
        sessao &+= 1
        let s = sessao
        t.aoTerminar = { [weak self] in Self.naMain { self?.terminou(sessao: s) } }
        atual = (id, t)
        guard t.tocar() else {
            log.error("WhatsApp: áudio não tocou")
            encerrar()
            return
        }
        tocando = id
        acompanhar()
    }

    func pausar() {
        relogio?.cancel()
        relogio = nil
        atual?.tocador.pausar()
        tocando = nil
    }

    private func terminou(sessao s: UInt64) {
        guard s == sessao else { return }
        relogio?.cancel()
        relogio = nil
        atual = nil
        tocando = nil
        progresso = 0
    }

    /// Para e solta o tocador atual, zerando o progresso.
    private func encerrar() {
        relogio?.cancel()
        relogio = nil
        if let a = atual {
            a.tocador.aoTerminar = nil
            a.tocador.pausar()
        }
        atual = nil
        tocando = nil
        progresso = 0
        sessao &+= 1
    }

    /// Lê o tempo do tocador 10 vezes por segundo enquanto toca.
    private func acompanhar() {
        relogio?.cancel()
        let s = sessao
        relogio = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, s == self.sessao, let t = self.atual?.tocador else { return }
                self.progresso = t.duracao > 0 ? min(max(t.tempo / t.duracao, 0), 1) : 0
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    /// O delegate do `AVAudioPlayer` chama na main; se vier de outra fila, salta.
    private nonisolated static func naMain(_ bloco: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(bloco)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(bloco) }
        }
    }
}
