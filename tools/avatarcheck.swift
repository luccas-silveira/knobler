// Gate do cache de avatar remoto (Knobler/RemoteAvatarLoader.swift).
//
// O cache guarda a miniatura, não a imagem decodificada inteira: uma foto de
// 4000×3000 virava 48 MB presos no NSCache. Trava o tamanho da miniatura, a
// orientação, a recusa de bytes que não são imagem e o teto do cache.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/RemoteAvatarLoader.swift tools/avatarcheck.swift \
//     -o /tmp/avatarcheck && /tmp/avatarcheck

import AppKit
import ImageIO
import UniformTypeIdentifiers

private func exigir(_ cond: Bool, _ msg: String) {
    if !cond {
        print("FALHOU: \(msg)")
        exit(1)
    }
}

/// Imagem sólida codificada no formato pedido, com orientação EXIF opcional.
private func imagem(largura: Int, altura: Int, tipo: UTType, orientacao: Int? = nil) -> Data {
    let ctx = CGContext(data: nil, width: largura, height: altura, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: largura, height: altura))
    let dados = NSMutableData()
    let destino = CGImageDestinationCreateWithData(dados, tipo.identifier as CFString, 1, nil)!
    var props: [CFString: Any] = [:]
    if let orientacao { props[kCGImagePropertyOrientation] = orientacao }
    CGImageDestinationAddImage(destino, ctx.makeImage()!, props as CFDictionary)
    CGImageDestinationFinalize(destino)
    return dados as Data
}

@main
enum Gate {
    static func main() {
        // Foto grande: sai no teto, proporção mantida.
        let grande = RemoteAvatarLoader.miniatura(de: imagem(largura: 4000, altura: 3000, tipo: .jpeg))
        exigir(grande != nil, "JPEG válido não decodificou")
        exigir(max(grande!.width, grande!.height) == RemoteAvatarLoader.ladoMaximo,
               "miniatura fora do teto: \(grande!.width)×\(grande!.height)")
        exigir(grande!.width == 128 && grande!.height == 96, "proporção perdida: \(grande!.width)×\(grande!.height)")

        // Pequena: não amplia.
        let pequena = RemoteAvatarLoader.miniatura(de: imagem(largura: 40, altura: 40, tipo: .png))
        exigir(pequena?.width == 40 && pequena?.height == 40, "imagem pequena mudou de tamanho")

        // EXIF girado 90° (orientação 6): a miniatura já sai em pé.
        let girada = RemoteAvatarLoader.miniatura(
            de: imagem(largura: 400, altura: 200, tipo: .jpeg, orientacao: 6))
        exigir(girada?.width == 64 && girada?.height == 128,
               "orientação EXIF ignorada: \(girada?.width ?? 0)×\(girada?.height ?? 0)")

        // Bytes que não são imagem: nil, sem crash.
        exigir(RemoteAvatarLoader.miniatura(de: Data("<html>oi</html>".utf8)) == nil,
               "HTML virou imagem")
        exigir(RemoteAvatarLoader.miniatura(de: Data()) == nil, "vazio virou imagem")

        // O cache tem teto e cada entrada é pequena: o pior caso cabe em poucos MB.
        let pior = RemoteAvatarLoader.limiteDoCache * RemoteAvatarLoader.ladoMaximo
            * RemoteAvatarLoader.ladoMaximo * 4
        exigir(RemoteAvatarLoader.limiteDoCache > 0 && pior <= 8 * 1024 * 1024,
               "cache cheio passa de 8 MB: \(pior) bytes")

        // O cache de verdade: o teto está ligado no NSCache, e o que vai pra ele
        // (o mesmo caminho do download) é a miniatura, não a foto cheia.
        exigir(RemoteAvatarLoader.limiteEfetivoDoCache == RemoteAvatarLoader.limiteDoCache,
               "o NSCache está sem o teto: countLimit \(RemoteAvatarLoader.limiteEfetivoDoCache)")
        let guardada = RemoteAvatarLoader.imagemDoCache(de: imagem(largura: 4000, altura: 3000, tipo: .jpeg))
        // o CGImage por trás (a rep do NSImage reporta pixels na escala da tela)
        let cg = guardada?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        exigir(cg != nil && max(cg!.width, cg!.height) <= RemoteAvatarLoader.ladoMaximo,
               "o cache guarda a imagem cheia: \(cg?.width ?? 0)×\(cg?.height ?? 0)")
        exigir(RemoteAvatarLoader.imagemDoCache(de: Data("<html>oi</html>".utf8)) == nil, "HTML foi pro cache")

        print("avatarcheck: ok")
    }
}
