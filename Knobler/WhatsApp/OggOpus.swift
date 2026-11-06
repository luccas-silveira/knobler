import Foundation

// Envelope Ogg da nota de voz (RFC 3533 + RFC 7845). O macOS grava Opus mas não
// grava Ogg, por isso as páginas são montadas aqui. A ponte confere `OggS` e um
// `OpusHead` de 1 canal (docs/whatsapp-ponte.md, `POST /v1/enviar/voz`).

enum OggOpus {
    /// Tabela do CRC do Ogg: polinômio 0x04C11DB7, sem reflexão.
    private static let tabelaCRC: [UInt32] = (0..<256).map { i -> UInt32 in
        var r = UInt32(i) << 24
        for _ in 0..<8 {
            r = (r & 0x8000_0000) != 0 ? (r << 1) ^ 0x04C1_1DB7 : (r << 1)
        }
        return r
    }

    /// CRC do Ogg: valor inicial 0, sem reflexão, sem xor final.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0
        for b in bytes {
            crc = (crc << 8) ^ tabelaCRC[Int(((crc >> 24) ^ UInt32(b)) & 0xFF)]
        }
        return crc
    }

    /// Cabeçalho de identificação (RFC 7845, 5.1): 19 bytes, família 0.
    static func cabecalhoOpusHead(canais: UInt8, preSkip: UInt16, taxaOriginal: UInt32) -> [UInt8] {
        var h = Array("OpusHead".utf8)
        h.append(1)                      // versão
        h.append(canais)
        h += le(UInt64(preSkip), bytes: 2)
        h += le(UInt64(taxaOriginal), bytes: 4)
        h += [0, 0]                      // ganho de saída
        h.append(0)                      // família de mapeamento
        return h
    }

    /// Cabeçalho de comentários (RFC 7845, 5.2) só com o vendor, sem comentários.
    static func cabecalhoOpusTags(vendor: String) -> [UInt8] {
        let v = Array(vendor.utf8)
        return Array("OpusTags".utf8) + le(UInt64(v.count), bytes: 4) + v + le(0, bytes: 4)
    }

    /// Amostras a 48 kHz de um pacote, pelo byte TOC (RFC 6716, 3.1).
    static func amostras48k(pacote: [UInt8]) -> Int {
        guard let toc = pacote.first else { return 0 }
        let config = Int(toc >> 3)
        let quadro: Int
        switch config {
        case 0...11: quadro = [480, 960, 1920, 2880][config % 4]   // SILK 10/20/40/60 ms
        case 12...15: quadro = [480, 960][config % 2]              // híbrido 10/20 ms
        default: quadro = [120, 240, 480, 960][config % 4]         // CELT 2,5/5/10/20 ms
        }
        let quadros: Int
        switch toc & 0x03 {
        case 0: quadros = 1
        case 1, 2: quadros = 2
        default: quadros = pacote.count >= 2 ? Int(pacote[1] & 0x3F) : 0
        }
        return quadro * quadros
    }

    /// Fluxo Ogg completo: página do `OpusHead` (BOS), página do `OpusTags` e as
    /// páginas de áudio (no máximo 255 segmentos cada), a última com EOS e
    /// granule `preSkip + totalAmostras48k` (corte do fim).
    static func paginas(pacotes: [[UInt8]], preSkip: Int, totalAmostras48k: Int, serial: UInt32) -> [UInt8] {
        var saida: [UInt8] = []
        var numero: UInt32 = 0

        func emitir(_ tipo: UInt8, granule: Int64, lacos: [UInt8], carga: [UInt8]) {
            var p = Array("OggS".utf8)
            p.append(0)                                  // versão
            p.append(tipo)
            p += le(UInt64(bitPattern: granule), bytes: 8)
            p += le(UInt64(serial), bytes: 4)
            p += le(UInt64(numero), bytes: 4)
            let posCRC = p.count
            p += [0, 0, 0, 0]
            p.append(UInt8(lacos.count))
            p += lacos
            p += carga
            let crc = crc32(p)
            p.replaceSubrange(posCRC..<(posCRC + 4), with: le(UInt64(crc), bytes: 4))
            saida += p
            numero += 1
        }

        let head = cabecalhoOpusHead(canais: 1, preSkip: UInt16(clamping: preSkip), taxaOriginal: 16000)
        emitir(0x02, granule: 0, lacos: lacosDe(head.count), carga: head)
        let tags = cabecalhoOpusTags(vendor: "Knobler")
        emitir(0x00, granule: 0, lacos: lacosDe(tags.count), carga: tags)

        let granuleFinal = Int64(preSkip + totalAmostras48k)
        guard !pacotes.isEmpty else {
            emitir(0x04, granule: granuleFinal, lacos: [], carga: [])
            return saida
        }

        // Segmentos de todos os pacotes em ordem; cada um sabe se fecha pacote.
        var lacos: [UInt8] = []
        var carga: [UInt8] = []
        var continua = false        // a página atual começa no meio de um pacote
        var aberto = false          // o último segmento não fechou o pacote
        var fechouAlgum = false
        var amostras = 0
        var granule = Int64(-1)

        for (k, pacote) in pacotes.enumerated() {
            amostras += amostras48k(pacote: pacote)
            var pos = 0
            for laco in lacosDe(pacote.count) {
                if lacos.count == 255 {
                    emitir(continua ? 0x01 : 0x00, granule: fechouAlgum ? granule : -1, lacos: lacos, carga: carga)
                    lacos = []; carga = []
                    continua = aberto
                    fechouAlgum = false
                }
                lacos.append(laco)
                carga += pacote[pos..<(pos + Int(laco))]
                pos += Int(laco)
                aberto = laco == 255
                if !aberto {
                    fechouAlgum = true
                    granule = k == pacotes.count - 1 ? granuleFinal : Int64(preSkip + amostras)
                }
            }
        }
        emitir((continua ? 0x01 : 0x00) | 0x04, granule: granuleFinal, lacos: lacos, carga: carga)
        return saida
    }

    /// Arquivo `.ogg` pronto para a ponte, com serial sorteado.
    static func arquivo(pacotes: [[UInt8]], preSkip: Int, totalAmostras48k: Int) -> Data {
        Data(paginas(pacotes: pacotes, preSkip: preSkip, totalAmostras48k: totalAmostras48k,
                     serial: UInt32.random(in: 0...UInt32.max)))
    }

    /// Tabela de laço de um pacote: 255 até o resto; múltiplo de 255 ganha um 0.
    private static func lacosDe(_ tamanho: Int) -> [UInt8] {
        [UInt8](repeating: 255, count: tamanho / 255) + [UInt8(tamanho % 255)]
    }

    private static func le(_ valor: UInt64, bytes: Int) -> [UInt8] {
        (0..<bytes).map { UInt8(truncatingIfNeeded: valor >> (8 * UInt64($0))) }
    }
}
