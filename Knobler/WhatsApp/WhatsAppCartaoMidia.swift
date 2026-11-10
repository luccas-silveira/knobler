import CoreGraphics
import Foundation

/// Regras do quadro de mídia do card de chegada do WhatsApp (mockup
/// docs/vesta/mockups/2026-11-10-whatsapp-cartao-nitido): a altura segue a
/// proporção da imagem, só foto baixa o arquivo inteiro, vídeo ganha a
/// duração em m:ss e só `.aguardando` merece outra tentativa.
enum WACartaoMidia {
    /// Altura do quadro para a imagem caber inteira na largura do card, entre
    /// `NotchMetrics.whatsappCartaoQuadroMinimo` e `…Maximo`. Proporção ou
    /// largura inválida (zero, negativa, NaN, infinita) cai no mínimo.
    static func altura(larguraDisponivel: CGFloat, proporcao: CGFloat) -> CGFloat {
        let minimo = NotchMetrics.whatsappCartaoQuadroMinimo
        let maximo = NotchMetrics.whatsappCartaoQuadroMaximo
        guard larguraDisponivel.isFinite, larguraDisponivel > 0,
              proporcao.isFinite, proporcao > 0 else { return minimo }
        return min(max(larguraDisponivel / proporcao, minimo), maximo)
    }

    /// Só foto baixa o arquivo inteiro no card; vídeo fica na miniatura.
    static func baixaArquivo(tipo: WATipoMensagem) -> Bool {
        tipo == .imagem
    }

    /// Etiqueta do vídeo em m:ss ("0:42", "12:00"); sem duração, sem etiqueta.
    static func duracao(segundos: Int?) -> String? {
        guard let s = segundos, s > 0 else { return nil }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// `.aguardando` é a recuperação em curso: vale pedir de novo. O resto ou
    /// já chegou ou não vai chegar, e o card fica na miniatura.
    static func tentarDeNovo(_ r: WAResultadoMidia) -> Bool {
        r == .aguardando
    }
}
