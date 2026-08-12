//
//  tools/ilhacheck.swift — self-check das medidas do visualizador da ilha.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/IlhaVisualizador.swift tools/ilhacheck.swift -o /tmp/ilhacheck \
//    && /tmp/ilhacheck
//

import AppKit

@main
struct IlhaCheck {
    static func main() {
        testGeometria()
        testAlturas()
        testBandas()
        print("✅ ilhacheck ok")
    }

    static let area = IlhaVisualizador.area

    /// Os números vêm de `-[MRUWaveformView layoutSubviews]`: passo = largura/6,
    /// barra = passo/2 (o vão é igual à largura da barra), centro da barra i =
    /// barra + i*passo.
    static func testGeometria() {
        assert(IlhaVisualizador.barras == 6, "seis barras, como a Dynamic Island")
        assert(area == CGSize(width: 22, height: 22), "acessório de 22x22 pt")

        let passo = IlhaVisualizador.passo(area.width)
        let barra = IlhaVisualizador.larguraDaBarra(area.width)
        assert(abs(passo - 22.0 / 6) < 0.0001, "passo = largura/6")
        assert(abs(barra - passo / 2) < 0.0001, "o vão é igual à largura da barra")

        assert(abs(IlhaVisualizador.centro(0, largura: area.width) - barra) < 0.0001,
               "a primeira barra é centrada a uma largura da borda")
        let ultimo = IlhaVisualizador.centro(5, largura: area.width)
        // simetria: a margem que sobra à direita é a mesma da esquerda
        assert(abs((area.width - ultimo) - barra) < 0.0001, "desenho simétrico")

        // é isto que autoriza a view a usar um HStack centralizado com
        // spacing == largura da barra em vez de posicionar barra por barra
        let larguraDoConjunto = CGFloat(IlhaVisualizador.barras) * barra
            + CGFloat(IlhaVisualizador.barras - 1) * barra
        assert(abs((area.width - larguraDoConjunto) / 2 - barra / 2) < 0.0001,
               "HStack centralizado reproduz os centros da Apple")
    }

    /// `height = max(min(amplitude,1) * altura, largura_da_barra)` e
    /// `width = largura_base + 0.66 * amplitude`.
    static func testAlturas() {
        let barra = IlhaVisualizador.larguraDaBarra(area.width)

        // piso: amplitude zero vira um ponto redondo, nunca some
        assert(IlhaVisualizador.altura(amplitude: 0, area: area) == barra,
               "silêncio vira ponto de diâmetro igual à largura da barra")
        assert(IlhaVisualizador.altura(amplitude: 1, area: area) == area.height,
               "amplitude cheia ocupa a área inteira")
        // amplitude fora da faixa não estoura a moldura nem inverte a barra
        assert(IlhaVisualizador.altura(amplitude: 3, area: area) == area.height,
               "amplitude acima de 1 é limitada")
        assert(IlhaVisualizador.altura(amplitude: -1, area: area) == barra,
               "amplitude negativa cai no piso")

        assert(IlhaVisualizador.largura(amplitude: 0, area: area) == barra,
               "sem sinal, a barra tem a largura base")
        assert(abs(IlhaVisualizador.largura(amplitude: 1, area: area)
                   - (barra + 0.66)) < 0.0001, "no pico a barra engorda 0,66 pt")
    }

    /// Seis bandas pedem sete bordas. A faixa coberta (bins 1…256 a ~47Hz/bin)
    /// é a mesma de antes: mudou só a divisão.
    static func testBandas() {
        let bordas = IlhaVisualizador.bordasDeBanda
        assert(bordas.count == IlhaVisualizador.barras + 1,
               "uma borda a mais que o número de barras")
        assert(bordas.first == 1 && bordas.last == 256, "mesma faixa de antes")
        assert(zip(bordas, bordas.dropFirst()).allSatisfy { $0 < $1 },
               "bordas estritamente crescentes")
    }
}
