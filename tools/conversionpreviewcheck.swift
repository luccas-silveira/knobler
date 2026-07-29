//
//  conversionpreviewcheck.swift
//  Gate do preview de conversão do shelf.
//
//  Cobre o que quebra calado: o mapeamento dos presets, o arredondamento par que
//  o encoder H.264 exige, e o ciclo de vida da pasta temporária (reconverter
//  apaga o anterior, descartar apaga tudo, salvar move e não deixa resto).
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/FileConverter.swift Knobler/ImageConverter.swift \
//    Knobler/DocumentConverter.swift Knobler/VideoConverter.swift \
//    Knobler/ShelfPreview.swift tools/conversionpreviewcheck.swift \
//    -o /tmp/conversionpreviewcheck && /tmp/conversionpreviewcheck
//

import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

private var falhas = 0

private func check(_ condicao: Bool, _ descricao: String) {
    if condicao {
        print("  ok   \(descricao)")
    } else {
        print("  FALHOU \(descricao)")
        falhas += 1
    }
}

/// Espera a condição girando o runloop — a conversão responde na main queue, e
/// bloquear com semáforo daria deadlock.
private func esperar(_ segundos: TimeInterval = 10, ate condicao: () -> Bool) -> Bool {
    let limite = Date().addingTimeInterval(segundos)
    while !condicao(), Date() < limite {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return condicao()
}

/// PNG sólido de `size`, escrito em disco — fixture que não depende de arquivo
/// do repo.
private func escreverPNG(_ size: CGSize, em url: URL) -> Bool {
    guard let ctx = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return false }
    ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
    ctx.fill(CGRect(origin: .zero, size: size))
    guard let image = ctx.makeImage() else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

@main
enum ConversionPreviewCheck {
    @MainActor
    static func main() {
        print("== presets ==")
        presets()
        print("== eixos por destino ==")
        eixos()
        print("== destino do arquivo ==")
        destino()
        print("== ciclo de vida do temporário ==")
        cicloDeVida()

        if falhas > 0 {
            print("❌ \(falhas) falha(s)")
            exit(1)
        }
        print("✅ conversionpreviewcheck ok")
    }

    // MARK: - Presets

    static func presets() {
        check(ConversionOptions.Quality.alta.lossyCompression == 0.9,
              "qualidade alta = 0,9 de compressão")
        check(ConversionOptions.Quality.baixa.lossyCompression
                < ConversionOptions.Quality.media.lossyCompression,
              "baixa comprime mais que média")
        check(ConversionOptions.Scale.full.factor == 1
                && ConversionOptions.Scale.half.factor == 0.5
                && ConversionOptions.Scale.quarter.factor == 0.25,
              "fatores de escala 1 / 0,5 / 0,25")
        check(ConversionOptions.padrao == ConversionOptions(quality: .alta, scale: .full),
              "padrão = alta em 100% (é o que preserva o passthrough do vídeo)")

        // a base de rasterização do PDF vezes o fator dá os 2x / 1x / 0,5x
        let base = DocumentConverter.baseRasterScale
        check(base * ConversionOptions.Scale.full.factor == 2
                && base * ConversionOptions.Scale.half.factor == 1
                && base * ConversionOptions.Scale.quarter.factor == 0.5,
              "PDF→PNG rasteriza em 2x / 1x / 0,5x")

        // medido: Medium impõe teto de resolução próprio e um 1080x1920 pedido em
        // 50% saía 320x568. Só o HighestQuality respeita o renderSize.
        check(VideoConverter.qualityPreset == AVAssetExportPresetHighestQuality,
              "vídeo exporta só no preset que respeita o renderSize")

        // dimensão ímpar quebra o encoder H.264 — e zero não existe
        check(ConversionOptions.evenSize(CGSize(width: 1921, height: 1081))
                == CGSize(width: 1922, height: 1082),
              "renderSize ímpar arredonda pra par")
        check(ConversionOptions.evenSize(CGSize(width: 1920, height: 1080))
                == CGSize(width: 1920, height: 1080),
              "renderSize já par não muda")
        check(ConversionOptions.evenSize(CGSize(width: 1, height: 0))
                == CGSize(width: 2, height: 2),
              "dimensão degenerada vira 2, não 0")
    }

    // MARK: - Eixos por destino

    static func eixos() {
        check(!ConversionTarget.image(.png).usaQualidade,
              "PNG não oferece qualidade (é lossless)")
        check(ConversionTarget.image(.jpeg).usaQualidade,
              "JPEG oferece qualidade")
        check(ConversionTarget.image(.png).usaEscala, "PNG oferece tamanho")
        check(!ConversionTarget.pdf.usaQualidade && !ConversionTarget.pdf.usaEscala,
              "PDF não oferece nenhum dos dois")
        check(!ConversionTarget.pngPages.usaQualidade && ConversionTarget.pngPages.usaEscala,
              "PDF→PNG oferece só tamanho")
        check(!ConversionTarget.video(.mpeg4Movie).usaQualidade
                && ConversionTarget.video(.mpeg4Movie).usaEscala,
              "vídeo oferece só tamanho (bitrate não é parâmetro do export)")
    }

    // MARK: - Destino

    static func destino() {
        let base = URL(fileURLWithPath: "/tmp/pasta/foto.jpg")
        let mesma = FileConverter.uniqueURL(for: base, ext: "png", in: nil)
        check(mesma.path == "/tmp/pasta/foto.png",
              "sem diretório: nasce ao lado do original")
        let outra = FileConverter.uniqueURL(
            for: base, ext: "png", in: URL(fileURLWithPath: "/tmp/trabalho"))
        check(outra.path == "/tmp/trabalho/foto.png",
              "com diretório: nasce lá, mantendo o nome")
    }

    // MARK: - Ciclo de vida

    @MainActor
    static func cicloDeVida() {
        let raiz = FileManager.default.temporaryDirectory
            .appendingPathComponent("conversionpreviewcheck-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: raiz) }

        let origem = raiz.appendingPathComponent("foto.png")
        guard escreverPNG(CGSize(width: 400, height: 200), em: origem) else {
            check(false, "fixture PNG escrita")
            return
        }

        let preview = ShelfPreview(source: origem, target: .image(.jpeg))
        guard esperar(ate: { !preview.running }) else {
            check(false, "primeira conversão terminou")
            return
        }
        guard let primeiro = preview.output else {
            check(false, "primeira conversão produziu arquivo")
            return
        }
        check(!primeiro.path.hasPrefix(raiz.path),
              "resultado NÃO nasce ao lado do original (fica no temporário)")
        check(FileManager.default.fileExists(atPath: primeiro.path),
              "resultado existe no temporário")
        check(preview.outputPixelSize == CGSize(width: 400, height: 200),
              "100% preserva a dimensão do original")
        let bytesAlta = preview.outputBytes ?? 0
        check(bytesAlta > 0, "tamanho do resultado é medido")

        // reconverter: o anterior tem que sumir, e o novo ser menor
        preview.options.scale = .half
        guard esperar(ate: { !preview.running && preview.output != nil }) else {
            check(false, "reconversão terminou")
            return
        }
        // não dá pra checar o caminho antigo: apagado o primeiro, o `uniqueURL`
        // devolve o MESMO nome pro segundo. O que importa é não acumular.
        let sobrando = (try? FileManager.default.contentsOfDirectory(
            at: primeiro.deletingLastPathComponent(),
            includingPropertiesForKeys: nil)) ?? []
        check(sobrando.count == 1,
              "reconverter apaga o anterior (1 arquivo no temporário, não 2)")
        check(preview.outputPixelSize == CGSize(width: 200, height: 100),
              "50% corta a dimensão pela metade")
        check((preview.outputBytes ?? .max) < bytesAlta,
              "50% pesa menos que 100%")

        // salvar: move pro lado do original e limpa o temporário
        let temporario = preview.output!
        let salvos = preview.salvar()
        check(salvos.count == 1, "salvar devolve o arquivo movido")
        check(salvos.first?.deletingLastPathComponent().path == raiz.path,
              "salvar grava na pasta do original")
        check(FileManager.default.fileExists(atPath: salvos.first?.path ?? ""),
              "arquivo salvo existe")
        check(!FileManager.default.fileExists(atPath: temporario.path),
              "salvar não deixa resto no temporário")
        check(FileManager.default.fileExists(atPath: origem.path),
              "o original continua no lugar")

        // descartar: some tudo, e o original segue intacto
        let outro = ShelfPreview(source: origem, target: .image(.jpeg))
        guard esperar(ate: { !outro.running && outro.output != nil }) else {
            check(false, "conversão do descarte terminou")
            return
        }
        let descartado = outro.output!
        outro.descartar()
        check(!FileManager.default.fileExists(atPath: descartado.path),
              "descartar apaga o resultado")
        check(FileManager.default.fileExists(atPath: origem.path),
              "descartar não encosta no original")
    }
}
