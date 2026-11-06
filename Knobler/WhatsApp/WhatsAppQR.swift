import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

// QR do pareamento. A ponte manda só o texto cru do `QRChannelItem.Code`
// (`qr` do Pareamento); quem desenha o código é o Knobler
// (docs/whatsapp-ponte.md:419-422).

enum WAQR {
    private static let contexto = CIContext(options: [.useSoftwareRenderer: true])

    /// Imagem `lado × lado` só com preto e branco opacos: módulos em escala
    /// inteira, sem suavização, e a sobra centrada como margem branca.
    /// Texto vazio (ou lado menor que o código) devolve `nil`.
    static func imagem(_ texto: String, lado: Int) -> CGImage? {
        guard !texto.isEmpty, lado > 0 else { return nil }
        let filtro = CIFilter.qrCodeGenerator()
        filtro.message = Data(texto.utf8)
        filtro.correctionLevel = "M"
        guard let codigo = filtro.outputImage,
              let base = contexto.createCGImage(codigo, from: codigo.extent) else { return nil }

        // o gerador já inclui a zona quieta de 1 módulo de cada lado
        let modulos = base.width
        let escala = lado / modulos
        guard escala >= 1 else { return nil }
        let desenho = modulos * escala
        let origem = (lado - desenho) / 2

        let cinza = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: lado, height: lado, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cinza,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: lado, height: lado))
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(base, in: CGRect(x: origem, y: origem, width: desenho, height: desenho))
        return ctx.makeImage()
    }
}
