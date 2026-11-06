import AVFoundation

// Codifica a gravação da nota de voz em Opus com o encoder nativo do macOS.
// A entrada é a do gravador do ditado: Float32 mono 16 kHz
// (`MicRecorder`, Knobler/Dictation.swift). O envelope Ogg fica com `OggOpus`.

enum WAErroCodificador: Error {
    case formato
    case conversor
    case conversao(String)
}

final class WACodificadorOpus {
    private let taxa: Double

    init(taxa: Double = 16000) {
        self.taxa = taxa
    }

    /// Pacotes Opus crus e o pre-skip em amostras de 48 kHz para o `OpusHead`.
    func codificar(_ amostras: [Float]) throws -> (pacotes: [[UInt8]], preSkip48k: Int) {
        guard let entrada = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: taxa,
                                          channels: 1, interleaved: false),
              let saida = AVAudioFormat(settings: [AVFormatIDKey: kAudioFormatOpus,
                                                   AVSampleRateKey: taxa,
                                                   AVNumberOfChannelsKey: 1])
        else { throw WAErroCodificador.formato }
        guard let conversor = AVAudioConverter(from: entrada, to: saida) else {
            throw WAErroCodificador.conversor
        }

        guard let pcm = AVAudioPCMBuffer(pcmFormat: entrada,
                                         frameCapacity: AVAudioFrameCount(max(amostras.count, 1)))
        else { throw WAErroCodificador.formato }
        pcm.frameLength = AVAudioFrameCount(amostras.count)
        if let canal = pcm.floatChannelData?[0] {
            amostras.withUnsafeBufferPointer { origem in
                if let base = origem.baseAddress { canal.update(from: base, count: origem.count) }
            }
        }

        let tamanhoMaximo = conversor.maximumOutputPacketSize > 0 ? conversor.maximumOutputPacketSize : 1500
        let capacidade: AVAudioPacketCount = 64
        var entregue = false
        var pacotes: [[UInt8]] = []

        while true {
            let buffer = AVAudioCompressedBuffer(format: saida, packetCapacity: capacidade,
                                                 maximumPacketSize: tamanhoMaximo)
            var erro: NSError?
            let status = conversor.convert(to: buffer, error: &erro) { _, estado in
                if entregue {
                    estado.pointee = .endOfStream
                    return nil
                }
                entregue = true
                estado.pointee = .haveData
                return pcm
            }
            if status == .error {
                throw WAErroCodificador.conversao(erro?.localizedDescription ?? "erro desconhecido")
            }
            if let descricoes = buffer.packetDescriptions {
                let base = buffer.data.assumingMemoryBound(to: UInt8.self)
                for i in 0..<Int(buffer.packetCount) {
                    let d = descricoes[i]
                    guard d.mDataByteSize > 0 else { continue }
                    pacotes.append(Array(UnsafeBufferPointer(start: base + Int(d.mStartOffset),
                                                             count: Int(d.mDataByteSize))))
                }
            }
            if status == .endOfStream || (status == .inputRanDry && buffer.packetCount == 0) { break }
        }

        let lider = Int(conversor.primeInfo.leadingFrames)
        // ponytail: pre-skip do encoder da Apple não documentado; 312 é o do libopus
        let preSkip = lider > 0 ? lider * 3 : 312
        return (pacotes, preSkip)
    }
}
