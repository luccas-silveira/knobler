// Gate da etapa 17 do WhatsApp: codificação Opus e envelope Ogg em Swift puro.
//
//   - `OggOpus.crc32`: CRC do Ogg (polinômio 0x04C11DB7, início 0, sem
//     reflexão, sem xor final).
//   - `OggOpus.cabecalhoOpusHead` / `cabecalhoOpusTags`: bytes exatos do RFC 7845.
//   - `OggOpus.amostras48k(pacote:)`: duração pelo TOC (RFC 6716, 3.1).
//   - `OggOpus.paginas(...)`: relidas por um leitor de páginas escrito AQUI
//     (CRC próprio, laço, continuação, BOS/EOS, granule, numeração).
//   - `WACodificadorOpus().codificar(_:)`: 2 s de seno a 16 kHz mono viram
//     pacotes Opus de verdade; `OggOpus.arquivo(...)` dá um Ogg que a ponte
//     aceita (`OggS` + `OpusHead` de 1 canal, docs/whatsapp-ponte.md,
//     `POST /v1/enviar/voz`). Em macOS 26+ o arquivo abre no `AVAudioFile`.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/OggOpus.swift Knobler/WhatsApp/CodificadorOpus.swift \
//     tools/whatsappoggcheck.swift \
//     -o /tmp/whatsappoggcheck && /tmp/whatsappoggcheck

import AVFoundation
import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappoggcheck.swift:\(linha))")
        exit(1)
    }
}

private func hex(_ b: [UInt8]) -> String {
    b.map { String(format: "%02x", $0) }.joined(separator: " ")
}

// MARK: - CRC de referência, independente do de produção

private let tabelaCRC: [UInt32] = (0..<256).map { i -> UInt32 in
    var r = UInt32(i) << 24
    for _ in 0..<8 {
        r = (r & 0x8000_0000) != 0 ? (r << 1) ^ 0x04C1_1DB7 : (r << 1)
    }
    return r
}

private func crcReferencia(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0
    for b in bytes {
        crc = (crc << 8) ^ tabelaCRC[Int(((crc >> 24) ^ UInt32(b)) & 0xFF)]
    }
    return crc
}

// MARK: - leitor de páginas Ogg (RFC 3533)

private struct Pagina {
    var tipo: UInt8
    var granule: Int64
    var serial: UInt32
    var numero: UInt32
    var lacos: [UInt8]
    var carga: [UInt8]
    var crcConfere: Bool
    var bos: Bool { tipo & 0x02 != 0 }
    var eos: Bool { tipo & 0x04 != 0 }
    var continua: Bool { tipo & 0x01 != 0 }
}

private func le32(_ b: [UInt8], _ i: Int) -> UInt32 {
    UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
}

private func le64(_ b: [UInt8], _ i: Int) -> Int64 {
    var v: UInt64 = 0
    for k in 0..<8 { v |= UInt64(b[i + k]) << (8 * UInt64(k)) }
    return Int64(bitPattern: v)
}

/// Lê o fluxo inteiro; qualquer byte que não feche uma página reprova.
private func lerPaginas(_ b: [UInt8], _ contexto: String) -> [Pagina] {
    var paginas: [Pagina] = []
    var i = 0
    while i < b.count {
        exigir(b.count - i >= 27, "\(contexto): sobram \(b.count - i) bytes depois da página \(paginas.count), menos que um cabeçalho de página")
        exigir(Array(b[i..<i + 4]) == Array("OggS".utf8), "\(contexto): página \(paginas.count) não começa com OggS (bytes \(hex(Array(b[i..<min(i + 4, b.count)]))))")
        exigir(b[i + 4] == 0, "\(contexto): página \(paginas.count) com versão \(b[i + 4]), esperado 0")
        let nseg = Int(b[i + 26])
        exigir(b.count - i >= 27 + nseg, "\(contexto): tabela de laço da página \(paginas.count) passa do fim do arquivo")
        let lacos = Array(b[(i + 27)..<(i + 27 + nseg)])
        let tamanho = lacos.reduce(0) { $0 + Int($1) }
        let fim = i + 27 + nseg + tamanho
        exigir(fim <= b.count, "\(contexto): carga da página \(paginas.count) passa do fim do arquivo")
        var bruto = Array(b[i..<fim])
        let crcGravado = le32(bruto, 22)
        bruto[22] = 0; bruto[23] = 0; bruto[24] = 0; bruto[25] = 0
        paginas.append(Pagina(
            tipo: b[i + 5],
            granule: le64(b, i + 6),
            serial: le32(b, i + 14),
            numero: le32(b, i + 18),
            lacos: lacos,
            carga: Array(b[(i + 27 + nseg)..<fim]),
            crcConfere: crcReferencia(bruto) == crcGravado))
        i = fim
    }
    return paginas
}

/// Remonta os pacotes pelo laço. Devolve os pacotes e, por página, quantos
/// pacotes TERMINARAM nela. Confere a flag de continuação em cada página.
private func remontar(_ paginas: [Pagina], _ contexto: String) -> (pacotes: [[UInt8]], terminados: [Int]) {
    var pacotes: [[UInt8]] = []
    var terminados: [Int] = []
    var atual: [UInt8] = []
    var aberto = false
    for (n, p) in paginas.enumerated() {
        exigir(p.continua == aberto, "\(contexto): página \(n) com flag de continuação \(p.continua), mas o pacote anterior \(aberto ? "ficou aberto" : "estava fechado")")
        var pos = 0
        var fechados = 0
        for laco in p.lacos {
            atual += p.carga[pos..<(pos + Int(laco))]
            pos += Int(laco)
            aberto = true
            if laco < 255 {
                pacotes.append(atual)
                atual = []
                aberto = false
                fechados += 1
            }
        }
        terminados.append(fechados)
    }
    exigir(!aberto, "\(contexto): o fluxo termina com um pacote aberto (laço de 255 sem fechamento)")
    return (pacotes, terminados)
}

// MARK: - casos

private func crc() {
    let v = OggOpus.crc32(Array("123456789".utf8))
    exigir(v == 0x89A1_897F, "crc32(\"123456789\") deu 0x\(String(v, radix: 16)), esperado 0x89a1897f (CRC do Ogg: 0x04C11DB7, início 0, sem reflexão, sem xor final)")
    exigir(OggOpus.crc32([]) == 0, "crc32([]) deu \(OggOpus.crc32([])), esperado 0")
    // bate com a referência em bytes quaisquer, não só no vetor do teste
    var gerador = SystemRandomNumberGenerator()
    for tamanho in [1, 27, 255, 1000] {
        let dados = (0..<tamanho).map { _ in UInt8.random(in: 0...255, using: &gerador) }
        let a = OggOpus.crc32(dados), r = crcReferencia(dados)
        exigir(a == r, "crc32 de \(tamanho) bytes aleatórios deu 0x\(String(a, radix: 16)), a referência dá 0x\(String(r, radix: 16))")
    }
}

private func opusHead() {
    let h = OggOpus.cabecalhoOpusHead(canais: 1, preSkip: 312, taxaOriginal: 16000)
    let esperado: [UInt8] = Array("OpusHead".utf8) + [
        1,              // versão
        1,              // canais
        0x38, 0x01,     // pre-skip 312 LE
        0x80, 0x3E, 0x00, 0x00, // 16000 LE
        0x00, 0x00,     // ganho
        0,              // família de mapeamento
    ]
    exigir(h.count == 19, "OpusHead com \(h.count) bytes, esperado 19")
    exigir(h == esperado, "OpusHead(1 canal, 312, 16000) deu [\(hex(h))], esperado [\(hex(esperado))]")
    // outro valor, pra não passar com bytes fixos
    let h2 = OggOpus.cabecalhoOpusHead(canais: 2, preSkip: 0x0A0B, taxaOriginal: 48000)
    exigir(h2.count == 19 && h2[9] == 2 && h2[10] == 0x0B && h2[11] == 0x0A
           && Array(h2[12..<16]) == [0x80, 0xBB, 0x00, 0x00],
           "OpusHead(2 canais, 0x0A0B, 48000) deu [\(hex(h2))]: canais, pre-skip ou taxa fora do lugar/endianness")
}

private func opusTags() {
    let t = OggOpus.cabecalhoOpusTags(vendor: "Knobler")
    let esperado: [UInt8] = Array("OpusTags".utf8) + [7, 0, 0, 0] + Array("Knobler".utf8) + [0, 0, 0, 0]
    exigir(t == esperado, "OpusTags(vendor: \"Knobler\") deu [\(hex(t))], esperado [\(hex(esperado))]")
    let t2 = OggOpus.cabecalhoOpusTags(vendor: "ação")   // 6 bytes em UTF-8
    exigir(t2.count == 8 + 4 + 6 + 4 && Array(t2[8..<12]) == [6, 0, 0, 0],
           "OpusTags(vendor: \"ação\") deu [\(hex(t2))]: o tamanho do vendor é em bytes UTF-8, LE32")
}

private func amostras() {
    func toc(_ config: UInt8, _ codigo: UInt8) -> UInt8 { config << 3 | codigo }
    let casos: [(String, [UInt8], Int)] = [
        ("config 1 (SILK 20 ms) código 0", [toc(1, 0)] + [UInt8](repeating: 0xAA, count: 20), 960),
        ("config 0 (SILK 10 ms) código 1", [toc(0, 1)] + [UInt8](repeating: 0xAA, count: 20), 960),
        ("config 16 (CELT 2,5 ms) código 0", [toc(16, 0)] + [UInt8](repeating: 0xAA, count: 8), 120),
        ("config 1 (20 ms) código 3 com 3 quadros", [toc(1, 3), 0x03] + [UInt8](repeating: 0xAA, count: 30), 2880),
        ("config 3 (SILK 60 ms) código 0", [toc(3, 0)] + [UInt8](repeating: 0xAA, count: 20), 2880),
        ("config 19 (CELT 20 ms) código 2", [toc(19, 2), 5] + [UInt8](repeating: 0xAA, count: 12), 1920),
        ("config 12 (híbrido 10 ms) código 0", [toc(12, 0)] + [UInt8](repeating: 0xAA, count: 10), 480),
        ("pacote vazio", [], 0),
    ]
    for (nome, pacote, esperado) in casos {
        let n = OggOpus.amostras48k(pacote: pacote)
        exigir(n == esperado, "amostras48k, \(nome): deu \(n), esperado \(esperado)")
    }
}

/// Pacote sintético de `tamanho` bytes com TOC de 20 ms (960 amostras a 48 kHz).
private func pacoteSintetico(_ tamanho: Int, semente: UInt8) -> [UInt8] {
    [0x08] + (1..<tamanho).map { UInt8(truncatingIfNeeded: $0 &* 7) &+ semente }
}

private func paginasBasicas() {
    let pacotes = [10, 255, 300, 600].enumerated().map { pacoteSintetico($0.element, semente: UInt8($0.offset)) }
    let preSkip = 312
    let total = 4 * 960 - 100              // corte do fim: a última página não é a soma
    let serial: UInt32 = 0xC0FF_EE01
    let b = OggOpus.paginas(pacotes: pacotes, preSkip: preSkip, totalAmostras48k: total, serial: serial)
    let ctx = "paginas(10, 255, 300, 600 bytes)"
    let ps = lerPaginas(b, ctx)
    exigir(ps.count >= 3, "\(ctx): \(ps.count) páginas, esperado ao menos 3 (OpusHead, OpusTags, áudio)")

    for (n, p) in ps.enumerated() {
        exigir(p.crcConfere, "\(ctx): CRC da página \(n) não confere")
        exigir(p.numero == UInt32(n), "\(ctx): página \(n) numerada \(p.numero), esperado \(n)")
        exigir(p.serial == serial, "\(ctx): página \(n) com serial 0x\(String(p.serial, radix: 16)), esperado 0x\(String(serial, radix: 16))")
        exigir(p.bos == (n == 0), "\(ctx): flag BOS na página \(n) é \(p.bos), esperado só na primeira")
        exigir(p.eos == (n == ps.count - 1), "\(ctx): flag EOS na página \(n) é \(p.eos), esperado só na última")
    }

    let (remontados, terminados) = remontar(ps, ctx)

    // página 0: só o OpusHead
    exigir(ps[0].lacos == [19] && terminados[0] == 1,
           "\(ctx): a primeira página tem laço \(ps[0].lacos), esperado só o OpusHead ([19])")
    exigir(ps[0].granule == 0, "\(ctx): granule da página do OpusHead é \(ps[0].granule), esperado 0")
    let head = ps[0].carga
    exigir(Array(head.prefix(8)) == Array("OpusHead".utf8), "\(ctx): primeira página não traz OpusHead: [\(hex(Array(head.prefix(8))))]")
    exigir(head.count == 19 && head[8] == 1 && head[9] == 1,
           "\(ctx): OpusHead da primeira página [\(hex(head))] não é versão 1 com 1 canal")
    exigir(Int(head[10]) | Int(head[11]) << 8 == preSkip,
           "\(ctx): OpusHead com pre-skip \(Int(head[10]) | Int(head[11]) << 8), esperado \(preSkip)")

    // página 1: só o OpusTags
    exigir(!ps[1].continua && terminados[1] == 1 && ps[1].lacos.last.map { $0 < 255 } == true,
           "\(ctx): a segunda página deveria trazer só o OpusTags (laço \(ps[1].lacos))")
    exigir(Array(ps[1].carga.prefix(8)) == Array("OpusTags".utf8), "\(ctx): segunda página não começa com OpusTags")
    exigir(ps[1].granule == 0, "\(ctx): granule da página do OpusTags é \(ps[1].granule), esperado 0")

    // áudio: começa na página 2, pacotes iguais aos de entrada
    exigir(ps[2...].allSatisfy { !$0.carga.starts(with: Array("Opus".utf8)) || $0.continua },
           "\(ctx): cabeçalho Opus repetido em página de áudio")
    exigir(remontados.count == 2 + pacotes.count,
           "\(ctx): \(remontados.count) pacotes remontados pelo laço, esperado \(2 + pacotes.count) (2 cabeçalhos + 4 de áudio)")
    for (k, p) in pacotes.enumerated() where 2 + k < remontados.count {
        let r = remontados[2 + k]
        exigir(r == p, "\(ctx): pacote de áudio \(k) remontado com \(r.count) bytes, entrou com \(p.count) (ou conteúdo diferente)")
    }
    // laço: 10 | 255 0 | 255 45 | 255 255 90
    let lacosAudio = ps[2...].flatMap { $0.lacos }
    exigir(lacosAudio == [10, 255, 0, 255, 45, 255, 255, 90],
           "\(ctx): laço das páginas de áudio \(lacosAudio), esperado [10, 255, 0, 255, 45, 255, 255, 90] (o pacote de 255 bytes ganha 255, 0)")

    let ultima = ps[ps.count - 1]
    exigir(ultima.granule == Int64(preSkip + total),
           "\(ctx): granule da última página \(ultima.granule), esperado preSkip + totalAmostras48k = \(preSkip + total)")
}

private func muitosSegmentos() {
    let pacotes = (0..<300).map { pacoteSintetico(10, semente: UInt8(truncatingIfNeeded: $0)) }
    let preSkip = 312
    let total = 300 * 960 - 500
    let b = OggOpus.paginas(pacotes: pacotes, preSkip: preSkip, totalAmostras48k: total, serial: 7)
    let ctx = "paginas(300 pacotes de 10 bytes)"
    let ps = lerPaginas(b, ctx)
    for (n, p) in ps.enumerated() {
        exigir(p.crcConfere, "\(ctx): CRC da página \(n) não confere")
        exigir(p.numero == UInt32(n), "\(ctx): página \(n) numerada \(p.numero), esperado \(n)")
    }
    let (remontados, terminados) = remontar(ps, ctx)
    exigir(remontados.count == 302 && Array(remontados[2...]) == pacotes,
           "\(ctx): pacotes remontados (\(remontados.count)) não batem com os 300 de entrada + 2 cabeçalhos")
    let audio = Array(ps.indices.dropFirst(2))
    exigir(audio.count >= 2, "\(ctx): \(audio.count) página(s) de áudio, esperado mais de uma (255 segmentos por página)")
    exigir(ps.last?.eos == true, "\(ctx): a última página não tem a flag EOS")
    exigir(ps.last?.granule == Int64(preSkip + total),
           "\(ctx): granule da última página \(ps.last?.granule ?? -1), esperado \(preSkip + total)")

    var anterior: Int64 = 0
    var feitos = 0
    for n in audio {
        let g = ps[n].granule
        exigir(g > anterior, "\(ctx): granule da página \(n) (\(g)) não cresce em relação à anterior (\(anterior))")
        anterior = g
        feitos += terminados[n]
        if n != ps.count - 1 {
            exigir(g == Int64(preSkip + feitos * 960),
                   "\(ctx): granule da página \(n) é \(g), esperado preSkip + amostras até o último pacote dela = \(preSkip + feitos * 960)")
        }
    }
}

private func codificacaoReal() {
    let taxa = 16000.0
    let seno: [Float] = (0..<32000).map { Float(0.5 * sin(2 * Double.pi * 440 * Double($0) / taxa)) }
    let r: (pacotes: [[UInt8]], preSkip48k: Int)
    do {
        r = try WACodificadorOpus().codificar(seno)
    } catch {
        exigir(false, "WACodificadorOpus().codificar(2 s de seno) lançou \(error)")
        return
    }
    exigir(!r.pacotes.isEmpty, "codificar(2 s de seno) não devolveu pacote nenhum")
    exigir(r.pacotes.allSatisfy { !$0.isEmpty }, "codificar devolveu pacote vazio")
    exigir(r.preSkip48k > 0, "codificar devolveu preSkip48k \(r.preSkip48k), esperado maior que 0")
    let soma = r.pacotes.reduce(0) { $0 + OggOpus.amostras48k(pacote: $1) }
    exigir(soma >= 96_000, "os pacotes de 2 s somam \(soma) amostras a 48 kHz, esperado pelo menos 96000")

    let dados = OggOpus.arquivo(pacotes: r.pacotes, preSkip: r.preSkip48k, totalAmostras48k: 96_000)
    let b = [UInt8](dados)
    exigir(b.starts(with: Array("OggS".utf8)), "OggOpus.arquivo não começa com OggS: [\(hex(Array(b.prefix(4))))]")
    let ctx = "arquivo(codificação real)"
    let ps = lerPaginas(b, ctx)
    for (n, p) in ps.enumerated() {
        exigir(p.crcConfere, "\(ctx): CRC da página \(n) não confere")
    }
    let head = ps.first?.carga ?? []
    exigir(head.count == 19 && Array(head.prefix(8)) == Array("OpusHead".utf8) && head[9] == 1,
           "\(ctx): primeira página não é um OpusHead de 1 canal: [\(hex(head))] — a ponte responderia 400 audio_invalido")
    let (remontados, _) = remontar(ps, ctx)
    exigir(Array(remontados.dropFirst(2)) == r.pacotes, "\(ctx): os pacotes do Ogg não são os do codificador")

    guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
        print("    (AVAudioFile pulado: Ogg Opus só abre direto em macOS 26+)")
        return
    }
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("whatsappoggcheck-\(getpid()).ogg")
    defer { try? FileManager.default.removeItem(at: url) }
    do {
        try dados.write(to: url)
        let f = try AVAudioFile(forReading: url)
        let duracao = Double(f.length) / f.processingFormat.sampleRate
        exigir(duracao >= 1.9 && duracao <= 2.1, "AVAudioFile leu \(duracao) s, esperado entre 1,9 e 2,1 s")
    } catch {
        exigir(false, "AVAudioFile não abriu o Ogg gerado: \(error)")
    }
}

@main
enum Gate {
    static func main() {
        crc()
        opusHead()
        opusTags()
        amostras()
        paginasBasicas()
        muitosSegmentos()
        codificacaoReal()
        print("ok: whatsappoggcheck")
    }
}
