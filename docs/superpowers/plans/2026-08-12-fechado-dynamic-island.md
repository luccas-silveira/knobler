# Notch fechado com música idêntico à Dynamic Island — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O estado fechado com música do notch — capa à esquerda, barras à direita — fica visualmente indistinguível da ilha compacta do iPhone.

**Architecture:** As medidas e curvas da Apple vivem num arquivo próprio sem SwiftUI (`Knobler/IlhaVisualizador.swift`), testado por um harness de função pura. A análise de áudio que já existe passa de cinco para seis bandas. A view do visualizador é reescrita: as barras deixam de ser pintadas e viram a máscara por onde a capa desfocada aparece, com uma mola reemitida a cada leitura do espectro. A regra "pausar esconde" é invertida, e a espiada no hover que existia por causa dela é removida.

**Tech Stack:** Swift 5, SwiftUI + AppKit, Accelerate (FFT já existente), macOS 14.2 como deployment target.

## Global Constraints

- Deployment target macOS 14.2. Nada de API mais nova sem `if #available`.
- Comentários e strings de UI em pt-BR.
- Nunca editar `Knobler.xcodeproj` à mão — é artefato de `xcodegen generate`.
- Arquivo `.swift` novo em `Knobler/` que a `NotchView` use tem que entrar à mão na lista de `tools/snapshot.sh`.
- Check novo exige entrada em `tools/check.sh`, senão a CI não o vê.
- `MARKETING_VERSION` e tags são escritas só por `tools/release.sh`. O plano escreve em `## [Unreleased]` do `CHANGELOG.md`.
- Números da Apple e números de calibração são coisas diferentes e ficam marcados como tal no código.
- Fonte de todos os valores: `docs/superpowers/research/2026-08-12-fechado-dynamic-island-research.md`.

---

### Task 1: Medidas e geometria da ilha

**Files:**
- Create: `Knobler/IlhaVisualizador.swift`
- Create: `tools/ilhacheck.swift`
- Modify: `tools/check.sh` (uma linha no bloco `== self-checks Swift ==`, junto de `colorpickercheck`)

**Interfaces:**
- Produces: `enum IlhaVisualizador` com `barras: Int`, `area: CGSize`, `capaLado/capaRaio: CGFloat`, `capaOpacidadePausada: CGFloat`, `capaDuracaoDim: TimeInterval`, `engordaNoPico: CGFloat`, `cinzaSemCapa: NSColor`, `duracaoSemCapa: TimeInterval`, `bordasDeBanda: [Int]`, e as funções `passo(_ largura: CGFloat) -> CGFloat`, `larguraDaBarra(_ largura: CGFloat) -> CGFloat`, `centro(_ indice: Int, largura: CGFloat) -> CGFloat`, `altura(amplitude: CGFloat, area: CGSize) -> CGFloat`, `largura(amplitude: CGFloat, area: CGSize) -> CGFloat`.

- [ ] **Step 1: Escrever o check que falha**

Cria `tools/ilhacheck.swift`:

```swift
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
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/IlhaVisualizador.swift tools/ilhacheck.swift -o /tmp/ilhacheck
```

Esperado: FALHA com "no such file or directory: 'Knobler/IlhaVisualizador.swift'".

- [ ] **Step 3: Escrever o arquivo de medidas**

Cria `Knobler/IlhaVisualizador.swift`:

```swift
//
//  IlhaVisualizador.swift
//  Knobler
//
//  Medidas e curvas do indicador de reprodução da Dynamic Island. Os valores
//  marcados "Apple" saem da decompilação de MediaControls.framework; os
//  marcados "calibração" não têm fonte e foram acertados por comparação
//  visual. Fonte de tudo:
//  docs/superpowers/research/2026-08-12-fechado-dynamic-island-research.md
//
//  Sem view nenhuma de propósito: `tools/ilhacheck.swift` compila só este
//  arquivo, e uma view aqui arrastaria a árvore inteira pra dentro do check.
//

import SwiftUI

enum IlhaVisualizador {

    // MARK: - Medidas do indicador (Apple)

    /// `+[MRUWaveformData amplitudeCount]` devolve 6.
    static let barras = 6
    /// Acessório trailing da ilha compacta.
    static let area = CGSize(width: 22, height: 22)
    /// Quanto a barra engorda no pico (`xScaleMultiplier`).
    static let engordaNoPico: CGFloat = 0.66

    /// `slot` do `layoutSubviews`: a fatia que cabe a cada barra.
    static func passo(_ largura: CGFloat) -> CGFloat {
        largura / CGFloat(barras)
    }

    /// Metade do passo — o vão entre barras é igual à largura da barra.
    static func larguraDaBarra(_ largura: CGFloat) -> CGFloat {
        passo(largura) / 2
    }

    /// Centro horizontal da barra `indice`. A view usa um HStack centralizado,
    /// que reproduz estes centros; a função existe para o check provar isso.
    static func centro(_ indice: Int, largura: CGFloat) -> CGFloat {
        larguraDaBarra(largura) + CGFloat(indice) * passo(largura)
    }

    /// O piso é a própria largura da barra: silêncio vira ponto redondo, nunca
    /// um traço fino e nunca o sumiço da barra. É o detalhe que separa a cópia
    /// boa da ruim.
    static func altura(amplitude: CGFloat, area: CGSize) -> CGFloat {
        max(limitada(amplitude) * area.height, larguraDaBarra(area.width))
    }

    static func largura(amplitude: CGFloat, area: CGSize) -> CGFloat {
        larguraDaBarra(area.width) + engordaNoPico * limitada(amplitude)
    }

    private static func limitada(_ amplitude: CGFloat) -> CGFloat {
        min(max(amplitude, 0), 1)
    }

    // MARK: - Capa (Apple)

    static let capaLado: CGFloat = 22
    static let capaRaio: CGFloat = 5.5
    /// Pausado, a capa escurece — `setDimsWhenPaused:`.
    static let capaOpacidadePausada: CGFloat = 0.5
    static let capaDuracaoDim: TimeInterval = 0.2
    /// Sem capa: cinza fixo do iPhone, com cross-fade de meio segundo.
    static let cinzaSemCapa = NSColor(white: 0.392156863, alpha: 1)
    static let duracaoSemCapa: TimeInterval = 0.5

    // MARK: - Bandas (calibração)

    /// Sete bordas em bins de FFT (~47Hz/bin a 48kHz) para seis bandas. A Apple
    /// usa seis bandas, mas as bordas dela não foram extraídas: estas são a
    /// mesma faixa de antes (47Hz–12kHz) redividida em progressão geométrica de
    /// razão ~2,5 no lugar de ~3.
    static let bordasDeBanda = [1, 3, 6, 16, 41, 102, 256]
}
```

- [ ] **Step 4: Rodar o check e ver passar**

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/IlhaVisualizador.swift tools/ilhacheck.swift -o /tmp/ilhacheck && /tmp/ilhacheck
```

Esperado: `✅ ilhacheck ok`.

- [ ] **Step 5: Registrar o check**

Em `tools/check.sh`, logo abaixo da linha `swift_check colorpickercheck …`:

```bash
swift_check ilhacheck         Knobler/IlhaVisualizador.swift tools/ilhacheck.swift
```

- [ ] **Step 6: Rodar a bateria inteira**

```bash
./tools/check.sh
```

Esperado: todos `ok`, incluindo `ilhacheck`.

- [ ] **Step 7: Commit**

```bash
git add Knobler/IlhaVisualizador.swift tools/ilhacheck.swift tools/check.sh
git commit -m "feat(notch): medidas do visualizador da Dynamic Island"
```

---

### Task 2: A animação de reserva da Apple

**Files:**
- Modify: `Knobler/IlhaVisualizador.swift`
- Modify: `tools/ilhacheck.swift`

**Interfaces:**
- Consumes: `IlhaVisualizador.barras` da Task 1.
- Produces: `IlhaVisualizador.cicloDaReserva: TimeInterval`, `sequenciasDaReserva: [[CGFloat]]`, `ordemDaReserva: [(sequencia: Int, defasagem: Double)]`, `reserva(em tempo: TimeInterval) -> [CGFloat]`, `amostra(_ sequencia: [CGFloat], fase: Double) -> CGFloat`.

Contexto: a tabela sai de `BouncyBars.caar`, o asset que a Apple toca quando não pode analisar o áudio. São cinco sequências de doze quadros-chave, ciclo de 2,66 s, interpolação cúbica, e o último valor de cada sequência repete o primeiro para o laço fechar sem emenda.

- [ ] **Step 1: Escrever o check que falha**

Acrescenta em `tools/ilhacheck.swift`, dentro de `main()`, antes do `print`:

```swift
        testReserva()
```

E o método, depois de `testBandas()`:

```swift
    /// A tabela vem de `BouncyBars.caar`. O que o check protege: o laço tem que
    /// fechar (senão a animação dá um pulo a cada 2,66 s), os valores têm que
    /// caber em 0…1, e as seis barras não podem estar todas em fase (senão o
    /// desenho vira um bloco subindo e descendo junto).
    static func testReserva() {
        assert(IlhaVisualizador.cicloDaReserva == 2.66, "ciclo de 2,66 s")
        assert(IlhaVisualizador.sequenciasDaReserva.count == 5, "cinco sequências")
        for (indice, sequencia) in IlhaVisualizador.sequenciasDaReserva.enumerated() {
            assert(sequencia.count == 12, "doze quadros na sequência \(indice)")
            assert(sequencia.first == sequencia.last,
                   "laço sem emenda na sequência \(indice)")
            assert(sequencia.allSatisfy { $0 >= 0 && $0 <= 1 },
                   "sequência \(indice) em 0…1")
        }

        assert(IlhaVisualizador.ordemDaReserva.count == IlhaVisualizador.barras,
               "uma entrada de ordem por barra")

        // continuidade no ponto de emenda: um passo antes do fim e um depois do
        // começo têm que estar perto, senão o olho vê o corte
        let fim = IlhaVisualizador.reserva(em: IlhaVisualizador.cicloDaReserva - 0.01)
        let comeco = IlhaVisualizador.reserva(em: 0.01)
        for barra in 0..<IlhaVisualizador.barras {
            assert(abs(fim[barra] - comeco[barra]) < 0.15,
                   "emenda suave na barra \(barra)")
        }

        // as barras não sobem todas juntas
        let instante = IlhaVisualizador.reserva(em: 1.0)
        assert(Set(instante.map { Int($0 * 100) }).count > 3,
               "as barras não estão em fase")

        // amostrar na fase 0 devolve o primeiro quadro-chave
        assert(abs(IlhaVisualizador.amostra(IlhaVisualizador.sequenciasDaReserva[0],
                                            fase: 0) - 0.49) < 0.0001,
               "fase 0 é o primeiro quadro")
    }
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/IlhaVisualizador.swift tools/ilhacheck.swift -o /tmp/ilhacheck
```

Esperado: FALHA com "type 'IlhaVisualizador' has no member 'cicloDaReserva'".

- [ ] **Step 3: Escrever a tabela e a amostragem**

Acrescenta ao fim de `Knobler/IlhaVisualizador.swift`, antes da última chave:

```swift
    // MARK: - Animação de reserva (Apple, com uma escolha nossa)

    /// Ciclo do `BouncyBars.caar`: doze quadros-chave uniformes, ~0,2418 s cada.
    static let cicloDaReserva: TimeInterval = 2.66

    /// As cinco sequências do asset, em fração da altura. O último valor repete
    /// o primeiro: é o que fecha o laço sem emenda.
    static let sequenciasDaReserva: [[CGFloat]] = [
        [0.490, 0.510, 0.429, 0.789, 0.655, 0.310,
         0.473, 0.510, 0.532, 0.688, 0.709, 0.490],
        [0.770, 0.480, 0.770, 0.552, 0.451, 0.461,
         0.881, 0.700, 0.907, 0.534, 0.519, 0.770],
        [0.600, 0.680, 0.580, 0.829, 0.680, 0.790,
         0.614, 0.880, 0.571, 0.829, 0.620, 0.600],
        [0.330, 0.589, 0.680, 0.469, 0.937, 0.599,
         0.717, 0.520, 0.688, 0.440, 0.730, 0.330],
        [0.400, 0.240, 0.489, 0.570, 0.421, 0.339,
         0.250, 0.720, 0.290, 0.588, 0.501, 0.400],
    ]

    /// Que sequência toca em cada barra. A tabela da Apple tem cinco e o
    /// indicador tem seis barras: a sexta repete a terceira defasada em meio
    /// ciclo. Escolha nossa, sem fonte.
    static let ordemDaReserva: [(sequencia: Int, defasagem: Double)] = [
        (0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (2, 0.5),
    ]

    /// Amplitudes das seis barras no instante dado.
    static func reserva(em tempo: TimeInterval) -> [CGFloat] {
        ordemDaReserva.map { item in
            var fase = (tempo / cicloDaReserva + item.defasagem)
                .truncatingRemainder(dividingBy: 1)
            if fase < 0 { fase += 1 }
            return amostra(sequenciasDaReserva[item.sequencia], fase: fase)
        }
    }

    /// Catmull-Rom fechado nos quadros-chave — a Apple interpola em cúbica, e
    /// linear deixaria uma quina visível a cada 0,24 s. Pode passar de 0…1 no
    /// exagero da curva; quem limita é `altura(amplitude:area:)`.
    static func amostra(_ sequencia: [CGFloat], fase: Double) -> CGFloat {
        let intervalos = sequencia.count - 1        // 11: o último repete o primeiro
        let posicao = fase * Double(intervalos)
        let quadro = Int(posicao) % intervalos
        let t = CGFloat(posicao - posicao.rounded(.down))
        func ponto(_ indice: Int) -> CGFloat {
            sequencia[((indice % intervalos) + intervalos) % intervalos]
        }
        let p0 = ponto(quadro - 1), p1 = ponto(quadro)
        let p2 = ponto(quadro + 1), p3 = ponto(quadro + 2)
        return 0.5 * (2 * p1
            + (-p0 + p2) * t
            + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
            + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
    }
```

- [ ] **Step 4: Rodar o check e ver passar**

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/IlhaVisualizador.swift tools/ilhacheck.swift -o /tmp/ilhacheck && /tmp/ilhacheck
```

Esperado: `✅ ilhacheck ok`.

- [ ] **Step 5: Commit**

```bash
git add Knobler/IlhaVisualizador.swift tools/ilhacheck.swift
git commit -m "feat(notch): curva de reserva do visualizador extraída da Apple"
```

---

### Task 3: Análise de áudio em seis bandas

**Files:**
- Modify: `Knobler/AudioLevelTap.swift:37-43`, `:131-132`, `:205-230`

**Interfaces:**
- Consumes: `IlhaVisualizador.bordasDeBanda` e `IlhaVisualizador.barras` da Task 1.
- Produces: `SystemAudioLevels.bands` com seis valores em vez de cinco. Assinatura pública inalterada.

- [ ] **Step 1: Trocar as constantes de banda**

Em `Knobler/AudioLevelTap.swift`, substituir o bloco de estado (hoje em `:37-43`):

```swift
    // suavização + auto-gain POR BANDA (graves têm sempre mais energia; sem
    // normalização individual as barras dos agudos ficam permanentemente baixas)
    private var smoothed = [Float](repeating: 0, count: 5)
    private var runningMax = [Float](repeating: -6, count: 5)
    private var lastPublish = Date.distantPast

    // bordas das bandas em bins de FFT (~47Hz/bin a 48kHz):
    // 47–140, 140–420, 420–1.2k, 1.2k–4k, 4k–12k Hz
    private static let bandEdges = [1, 3, 9, 26, 85, 256]
```

por:

```swift
    // suavização + auto-gain POR BANDA (graves têm sempre mais energia; sem
    // normalização individual as barras dos agudos ficam permanentemente baixas)
    private var smoothed = [Float](repeating: 0, count: IlhaVisualizador.barras)
    private var runningMax = [Float](
        repeating: -6, count: IlhaVisualizador.barras)
    private var lastPublish = Date.distantPast

    /// Seis bandas, como a Dynamic Island. As bordas moram no
    /// `IlhaVisualizador` junto do resto das medidas.
    private static let bandEdges = IlhaVisualizador.bordasDeBanda
    private static let bandCount = IlhaVisualizador.barras
```

- [ ] **Step 2: Trocar os laços de cinco por `bandCount`**

Em `stop()` (hoje `:131-132`), substituir:

```swift
            self?.smoothed = [0, 0, 0, 0, 0]
            self?.runningMax = [Float](repeating: -6, count: 5)
```

por:

```swift
            self?.smoothed = [Float](repeating: 0, count: Self.bandCount)
            self?.runningMax = [Float](repeating: -6, count: Self.bandCount)
```

Em `analyze()`, substituir as três ocorrências de `5` (a criação de `levels` e os dois `for band in 0..<5`):

```swift
        var levels = [Float](repeating: 0, count: Self.bandCount)
        for band in 0..<Self.bandCount {
```

e

```swift
        for band in 0..<Self.bandCount {
```

Também atualizar o comentário do cabeçalho do arquivo (`:6-7`), que diz "5 bandas de frequência normalizadas em 0…1", para "6 bandas".

- [ ] **Step 3: Confirmar que não sobrou nenhum cinco literal**

```bash
grep -n "count: 5\|0\.\.<5\|5 bandas" Knobler/AudioLevelTap.swift
```

Esperado: nenhuma linha.

- [ ] **Step 4: Compilar o app**

```bash
xcodegen generate
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Esperado: `BUILD SUCCEEDED`. Nesta altura a view ainda desenha cinco barras a partir de um vetor de seis — o excedente é ignorado, e a Task 4 conserta.

- [ ] **Step 5: Commit**

```bash
git add Knobler/AudioLevelTap.swift
git commit -m "feat(notch): análise de áudio em seis bandas"
```

---

### Task 4: O visualizador reescrito

**Files:**
- Modify: `Knobler/NotchView.swift:1682-1750` (o `AudioBarsView` inteiro), `:797-803` (o wrapper `audioBars`), `:785-788` (o frame na asa)
- Modify: `Knobler/MediaController.swift:30-35` e `:121` (luminância da capa)
- Modify: `tools/snapshot.sh:28` (acrescentar o arquivo novo à lista)

**Interfaces:**
- Consumes: tudo do `IlhaVisualizador` das Tasks 1 e 2; `SystemAudioLevels.bands` com seis valores da Task 3.
- Produces: `AudioBarsView(playing: Bool, levels: SystemAudioLevels, capa: NSImage?, luminancia: Double?)` — a propriedade `tint: Color` deixa de existir; `MediaController.artworkLuminancia: Double?`.

- [ ] **Step 1: Publicar a luminância da capa**

Em `Knobler/MediaController.swift`, trocar o bloco de `:30-35`:

```swift
    @Published private(set) var artwork: NSImage? {
        didSet { artworkTint = artwork.flatMap(Self.vibrantTint) }
    }
    /// Cor vibrante dominante da capa — tinge o visualizador como no iPhone.
    @Published private(set) var artworkTint: Color?
```

por:

```swift
    @Published private(set) var artwork: NSImage? {
        didSet {
            artworkTint = artwork.flatMap(Self.vibrantTint)
            artworkLuminancia = artwork.flatMap(Self.luminanciaMedia)
        }
    }
    /// Cor vibrante dominante da capa. O visualizador não usa mais (virou
    /// recorte sobre a própria capa); quem usa é o card aberto.
    @Published private(set) var artworkTint: Color?
    /// Luminância média da capa em 0…1. O visualizador corrige capa escura ou
    /// clara demais a partir dela, como o iPhone.
    @Published private(set) var artworkLuminancia: Double?
```

E acrescentar, logo antes de `private static func vibrantTint`:

```swift
    /// Luminância média (Rec. 709) numa amostra de 16x16 — barata e suficiente
    /// pra decidir se as barras precisam clarear ou escurecer.
    private static func luminanciaMedia(_ image: NSImage) -> Double? {
        let side = 16
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var soma = 0.0
        var contados = 0
        for y in 0..<side {
            for x in 0..<side {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else { continue }
                soma += 0.2126 * Double(color.redComponent)
                    + 0.7152 * Double(color.greenComponent)
                    + 0.0722 * Double(color.blueComponent)
                contados += 1
            }
        }
        return contados > 0 ? soma / Double(contados) : nil
    }
```

- [ ] **Step 2: Acrescentar os parâmetros visuais de calibração**

Em `Knobler/IlhaVisualizador.swift`, antes da seção de reserva:

```swift
    // MARK: - Pintura das barras (calibração)

    /// A capa entra desfocada e mais saturada atrás das barras — no iPhone as
    /// barras são recorte, não tinta. Os três valores abaixo não têm fonte: os
    /// da Apple ficaram em dados que a decompilação não expôs.
    static let desfoqueDaCapa: CGFloat = 3
    static let saturacaoDaCapa: Double = 1.6
    /// Abaixo disto a capa é escura demais e as barras somem no preto do notch;
    /// acima, clara demais e o desenho perde contorno.
    static let luminanciaMinima = 0.35
    static let luminanciaMaxima = 0.85

    /// Quanto clarear e quanto escurecer, dado o brilho médio da capa. Mesma
    /// forma do `-updateArtworkFilters` da Apple: a distância até o limiar vira
    /// a opacidade da camada de correção.
    static func correcaoDeLuminancia(_ luminancia: Double) -> (clarear: Double, escurecer: Double) {
        (clarear: max(0, luminanciaMinima - luminancia),
         escurecer: max(0, luminancia - luminanciaMaxima))
    }

    /// Uma mola por leitura do espectro, todas as barras juntas — é o que a
    /// Apple faz, e a irregularidade vem do som, não da animação. Números sem
    /// fonte.
    static let mola = Animation.spring(response: 0.30, dampingFraction: 0.62)
```

O arquivo já importa `SwiftUI` desde a Task 1, que é de onde vem o tipo `Animation`. Rodar `xcrun swiftc -parse-as-library -swift-version 5 Knobler/IlhaVisualizador.swift tools/ilhacheck.swift -o /tmp/ilhacheck && /tmp/ilhacheck` de novo aqui: o check tem que continuar passando com as constantes novas.

- [ ] **Step 3: Reescrever o visualizador**

Em `Knobler/NotchView.swift`, substituir o bloco inteiro de `// MARK: - Visualizador de áudio` até o fim de `struct AudioBarsView` (hoje `:1682-1750`) por:

```swift
// MARK: - Visualizador de áudio

/// Indicador de reprodução igual ao da Dynamic Island: seis barras que são o
/// RECORTE por onde a capa desfocada aparece — no iPhone elas não são pintadas
/// com uma cor da capa, e é isso que dá matiz diferente entre vizinhas.
/// Alimentado pelas bandas do áudio real; sem tap disponível, toca a animação
/// de reserva que a Apple usa no app Música. Medidas em `IlhaVisualizador`.
struct AudioBarsView: View {
    var playing: Bool
    @ObservedObject var levels: SystemAudioLevels
    var capa: NSImage?
    var luminancia: Double?

    private var bands: [Float]? { levels.bands }
    private static let area = IlhaVisualizador.area
    private static let paradas = [CGFloat](
        repeating: 0, count: IlhaVisualizador.barras)

    var body: some View {
        pintura
            .frame(width: Self.area.width, height: Self.area.height)
    }

    @ViewBuilder private var pintura: some View {
        if !playing {
            // pausado: seis pontinhos parados, como a ilha sem análise
            capaTratada.mask(barras(Self.paradas))
        } else if let bands {
            capaTratada.mask(barras(bands.map { CGFloat($0) }))
                .animation(IlhaVisualizador.mola, value: bands)
        } else {
            // 30fps bastam pra reserva — 60 dobra o custo sem ganho visível
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { contexto in
                capaTratada.mask(barras(IlhaVisualizador.reserva(
                    em: contexto.date.timeIntervalSinceReferenceDate)))
            }
        }
    }

    private var capaTratada: some View {
        ZStack {
            if let capa {
                Image(nsImage: capa)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: IlhaVisualizador.desfoqueDaCapa)
                    .saturation(IlhaVisualizador.saturacaoDaCapa)
                correcao
            } else {
                Color(nsColor: IlhaVisualizador.cinzaSemCapa)
            }
        }
        .frame(width: Self.area.width, height: Self.area.height)
        .clipped()
        .animation(.easeInOut(duration: IlhaVisualizador.duracaoSemCapa),
                   value: capa == nil)
    }

    /// Capa escura demais some no preto do notch; clara demais perde contorno.
    /// ponytail: a Apple ainda soma saturação junto do clareamento — teto
    /// conhecido, capa quase preta fica cinza em vez de colorida. Duas camadas
    /// resolvem o caso que importa.
    @ViewBuilder private var correcao: some View {
        let ajuste = IlhaVisualizador.correcaoDeLuminancia(luminancia ?? 0.5)
        if ajuste.clarear > 0 { Color.white.opacity(ajuste.clarear) }
        if ajuste.escurecer > 0 { Color.black.opacity(ajuste.escurecer) }
    }

    /// HStack centralizado com vão igual à largura da barra reproduz os centros
    /// do `layoutSubviews` da Apple — o `ilhacheck` prova a equivalência.
    private func barras(_ amplitudes: [CGFloat]) -> some View {
        HStack(spacing: IlhaVisualizador.larguraDaBarra(Self.area.width)) {
            ForEach(0..<IlhaVisualizador.barras, id: \.self) { indice in
                let amplitude = indice < amplitudes.count ? amplitudes[indice] : 0
                Capsule(style: .continuous)
                    .frame(
                        width: IlhaVisualizador.largura(
                            amplitude: amplitude, area: Self.area),
                        height: IlhaVisualizador.altura(
                            amplitude: amplitude, area: Self.area))
            }
        }
        .frame(width: Self.area.width, height: Self.area.height)
    }
}
```

- [ ] **Step 4: Atualizar o wrapper e o frame na asa**

Em `Knobler/NotchView.swift`, trocar `audioBars` (hoje `:797-803`):

```swift
    private var audioBars: some View {
        AudioBarsView(
            playing: media.state?.isPlaying == true,
            levels: levels,
            capa: media.artwork,
            luminancia: media.artworkLuminancia
        )
    }
```

E na asa direita (hoje `:785-788`), trocar o frame fixo pela medida da ilha:

```swift
                } else if wingsVisible {
                    audioBars
                        .frame(width: IlhaVisualizador.area.width,
                               height: IlhaVisualizador.area.height)
                }
```

- [ ] **Step 5: Acrescentar o arquivo novo ao harness de snapshot**

Em `tools/snapshot.sh`, na lista de fontes, ao lado de `Knobler/AudioLevelTap.swift \`:

```bash
  Knobler/IlhaVisualizador.swift \
```

- [ ] **Step 6: Compilar e renderizar**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
./tools/snapshot.sh
```

Esperado: `BUILD SUCCEEDED` e os 55 PNGs regenerados sem erro.

- [ ] **Step 7: Conferir o desenho**

Ler `Snapshots/closed-music.png` e `Snapshots/closed-music-external.png`. O que tem que estar lá: seis barras finas com vão igual à espessura, pontas em cápsula, coloridas com matizes diferentes entre si (vindo da capa, não de uma cor só), nenhuma barra colada na vizinha, nenhuma estourando a altura do notch.

- [ ] **Step 8: Commit**

```bash
git add Knobler/NotchView.swift Knobler/MediaController.swift \
  Knobler/IlhaVisualizador.swift tools/snapshot.sh
git commit -m "feat(notch): barras viram recorte sobre a capa, com as medidas da ilha"
```

---

### Task 5: Pausado visível, sem espiada

**Files:**
- Modify: `Knobler/NotchView.swift:154-157` (`wingsVisible`), `:84` (`opening`), `:805-818` (`miniArtwork`)
- Modify: `Knobler/NotchViewModel.swift:52-54`, `:368-370`, `:387-400`, `:402-410`
- Modify: `Knobler/KnoblerApp.swift:366-373`, `:1193-1194`
- Modify: `tools/main.swift:167-177` (cenários)

**Interfaces:**
- Consumes: `IlhaVisualizador.capaLado/capaRaio/capaOpacidadePausada/capaDuracaoDim` da Task 1.
- Produces: `NotchViewModel` sem `peeking`, sem `musicPaused` e sem `scheduleExpandAfterPeek()`.

- [ ] **Step 1: Inverter a regra de visibilidade**

Em `Knobler/NotchView.swift`, trocar `:154-157`:

```swift
    /// Pausado, a música se esconde; hover espia (peeking) antes do card completo.
    private var wingsVisible: Bool {
        hasMusic && (media.state?.isPlaying == true || vm.peeking)
    }
```

por:

```swift
    /// Com música na sessão, capa e barras ficam — tocando ou pausada, como na
    /// ilha do iPhone. Pausada, as barras caem pros pontinhos e a capa escurece.
    private var wingsVisible: Bool { hasMusic }
```

E em `:84`, trocar `let opening = mode != .closed || vm.peeking` por:

```swift
        let opening = mode != .closed
```

- [ ] **Step 2: Capa nas medidas da ilha, com o escurecimento ao pausar**

Trocar `miniArtwork` (hoje `:805-818`) por:

```swift
    private var miniArtwork: some View {
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.15))
            }
        }
        .frame(width: IlhaVisualizador.capaLado, height: IlhaVisualizador.capaLado)
        .clipShape(RoundedRectangle(cornerRadius: IlhaVisualizador.capaRaio,
                                    style: .continuous))
        // pausado a capa escurece, como no iPhone
        .opacity(media.state?.isPlaying == true
                 ? 1 : IlhaVisualizador.capaOpacidadePausada)
        .animation(.easeInOut(duration: IlhaVisualizador.capaDuracaoDim),
                   value: media.state?.isPlaying)
    }
```

- [ ] **Step 3: Remover a espiada do view model**

Em `Knobler/NotchViewModel.swift`:

Apagar as três linhas de `:52-54`:

```swift
    /// Música pausada some do notch; hover "espia" (peeking) antes de expandir.
    @Published var musicPaused = false
    @Published var peeking = false
```

Em `fecharPorHoverOut()`, trocar `:368-370`:

```swift
        if expanded || peeking { lastCollapseAt = Date() }
        expanded = false
        peeking = false
```

por:

```swift
        if expanded { lastCollapseAt = Date() }
        expanded = false
```

Em `setHover(_:)`, trocar o bloco de `:387-397` por:

```swift
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hovering else { return }
            self.expanded = true
        }
```

Apagar `scheduleExpandAfterPeek()` inteiro (`:402-410`) e a constante `peekDwell` que só ele usa.

- [ ] **Step 4: Remover o publisher que alimentava a regra**

Em `Knobler/KnoblerApp.swift`, apagar o bloco `pausedCancellable` (hoje `:366-373`, incluindo o comentário `// pausado, a música se esconde do notch (peek no hover)` e a declaração da propriedade `pausedCancellable`), e a atribuição em `:1193-1194`.

- [ ] **Step 5: Confirmar que não sobrou referência**

```bash
grep -rn "peeking\|musicPaused\|peekDwell\|scheduleExpandAfterPeek\|pausedCancellable" \
  Knobler tools --include="*.swift"
```

Esperado: nenhuma linha. Se aparecer alguma em `tools/main.swift`, é o Step 6.

- [ ] **Step 6: Substituir os dois cenários da regra antiga por um**

Em `tools/main.swift`, trocar os cenários de `:167-177`:

```swift
    // pausado: escondida (deve parecer ilha vazia, não miniatura)
    Scenario(name: "closed-paused-hidden", realNotch: false) { vm, media, _ in
        media.injectPreview(state: fakeState(playing: false), artwork: fakeArtwork())
        vm.musicPaused = true
    },
    // pausado + hover: espiada (asinhas com pontinhos)
    Scenario(name: "closed-paused-peek", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(playing: false), artwork: fakeArtwork())
        vm.musicPaused = true
        vm.peeking = true
    },
```

por:

```swift
    // pausado: capa escurecida e as barras nos pontinhos, como a ilha do iPhone
    Scenario(name: "closed-paused", realNotch: true) { _, media, _ in
        media.injectPreview(state: fakeState(playing: false), artwork: fakeArtwork())
    },
```

E apagar os PNGs órfãos:

```bash
rm -f Snapshots/closed-paused-hidden.png Snapshots/closed-paused-peek.png
```

- [ ] **Step 7: Compilar, rodar os checks e renderizar**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
./tools/check.sh
./tools/snapshot.sh
```

Esperado: `BUILD SUCCEEDED`, todos os checks `ok`, e `Snapshots/closed-paused.png` gerado.

- [ ] **Step 8: Conferir o pausado**

Ler `Snapshots/closed-paused.png`. O que tem que estar lá: a capa visível e mais apagada que no `closed-music.png`, e seis pontos redondos alinhados no lugar das barras — não traços, não barras de meia altura, não área vazia.

- [ ] **Step 9: Commit**

```bash
git add Knobler/NotchView.swift Knobler/NotchViewModel.swift \
  Knobler/KnoblerApp.swift tools/main.swift
git commit -m "feat(notch): música pausada continua no notch, sem espiada no hover"
```

---

### Task 6: Calibração no app real

**Files:**
- Modify: `Knobler/IlhaVisualizador.swift` (só os valores marcados "calibração")

Esta é a tarefa que a spec avisou que existiria: os números sem fonte só se acertam olhando. Nada de código novo — só ajuste de constante e comparação.

- [ ] **Step 1: Subir a build assinada**

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build 2>&1 | tail -3
pkill -x Knobler; open build/Debug/Knobler.app 2>/dev/null || \
  echo "abrir manualmente o Knobler.app recém-compilado"
```

- [ ] **Step 2: Tocar música e confirmar que a análise está de pé**

```bash
curl -s http://127.0.0.1:4477/status | jq '.visualizerTapped'
```

Esperado: o bundle ID do player (ex.: `"com.spotify.client"`), não `"none"`. Se vier `"none"`: a permissão de gravação de áudio do sistema não foi concedida ou o ajuste "visualizador ao vivo" está desligado — nesse estado o que se vê é a curva de reserva, não a análise.

- [ ] **Step 3: Comparar com o iPhone e ajustar**

Com música tocando nos dois, olhar lado a lado e ajustar em `Knobler/IlhaVisualizador.swift` apenas estes valores, um de cada vez:

| Sintoma | Constante |
|---|---|
| Barras parecem tremer / movimento nervoso demais | `mola` — subir `response` |
| Barras parecem moles, atrasadas em relação à batida | `mola` — descer `response` |
| Barras oscilam depois de parar | `mola` — subir `dampingFraction` |
| Cor lavada, sem relação com a capa | `saturacaoDaCapa` para cima |
| Dá pra reconhecer o desenho da capa dentro das barras | `desfoqueDaCapa` para cima |
| Barras somem em capa escura | `luminanciaMinima` para cima |
| Alturas todas coladas no topo ou todas no chão | `bordasDeBanda` — redistribuir |

- [ ] **Step 4: Registrar o que mudou**

Cada valor alterado ganha o número novo e o comentário continua dizendo "calibração". Se algum valor sair muito do inicial, acrescentar meia linha dizendo o que se via antes.

- [ ] **Step 5: Rodar os checks e o snapshot**

```bash
./tools/check.sh && ./tools/snapshot.sh
```

- [ ] **Step 6: Commit**

```bash
git add Knobler/IlhaVisualizador.swift
git commit -m "fix(notch): calibra o visualizador contra a ilha do iPhone"
```

---

### Task 7: Documentação e novidade

**Files:**
- Modify: `docs/now-playing.md:14-21`, `:39-41`
- Modify: `README.md:222-224` (o consumo declarado)
- Modify: `CHANGELOG.md` (bloco `## [Unreleased]`)
- Create: `Knobler/Novidades/0.27.0.html`
- Modify: `Knobler/NovidadesCatalogo.swift:20`

- [ ] **Step 1: Atualizar a página de agora tocando**

Em `docs/now-playing.md`, substituir o parágrafo de `:13-21` por:

```markdown
Mostra o que está tocando no Spotify ou Apple Music — capa do álbum e um
visualizador de áudio animado no notch fechado; passar o mouse expande com
controles de play/pause, próxima/anterior, barra de progresso e shuffle. O
visualizador é o da Dynamic Island, nas mesmas medidas: seis barras que não são
pintadas, e sim o recorte por onde a capa desfocada aparece — por isso cada uma
tem um tom diferente da vizinha. Elas dançam com o áudio real do player, lido
por um tap via CoreAudio (FFT em 6 bandas) no processo dele. Sem áudio real
disponível (ou sem a permissão concedida), toca a animação de reserva que a
Apple usa no app Música. Música pausada continua no notch: a capa escurece e as
barras descansam em pontinhos redondos.
```

E em `:39-41`, trocar a última frase da permissão:

```markdown
- **Gravação de Áudio do Sistema** — *"Knobler lê o áudio do player para
  animar o visualizador no notch, como no iPhone."* Sem ela, o visualizador
  toca a animação de reserva da Apple em vez de seguir o áudio.
```

- [ ] **Step 2: Corrigir o consumo no README**

`README.md:222-224` diz "~11% de um core com música tocando (visualizador a 20Hz)". Medir de novo com o Activity Monitor, com música tocando e o card fechado, e escrever o número medido. Se não der pra medir na hora, trocar a frase por uma sem número em vez de deixar um número errado.

- [ ] **Step 3: Escrever a entrada do CHANGELOG**

Em `## [Unreleased]`, na seção `### Adicionado` (ou `### Alterado`, conforme o arquivo já usar):

```markdown
- Visualizador de música redesenhado nas medidas da Dynamic Island: seis barras
  finas que revelam a capa em vez de serem tingidas por ela, com o piso em
  pontinho e a análise do áudio em seis bandas.
- Música pausada continua visível no notch, com a capa escurecida — o hover
  passa a abrir o card direto, sem a etapa de espiada.
```

- [ ] **Step 4: Capturar a imagem da novidade**

Com música tocando e o notch fechado, capturar o notch da tela real (o harness de snapshot não serve aqui: é o app rodando que interessa) e salvar como `Knobler/Novidades/midia/visualizador-ilha.png`.

```bash
screencapture -R 500,0,400,60 -o Knobler/Novidades/midia/visualizador-ilha.png
sips -Z 800 Knobler/Novidades/midia/visualizador-ilha.png
```

Ajustar o `-R` para a posição do notch na tela em uso. Conferir o PNG antes de seguir: se sair a barra de menus em vez do notch com capa e barras, refazer.

- [ ] **Step 5: Escrever a página da novidade**

Cria `Knobler/Novidades/0.27.0.html` no molde de `0.26.0.html`:

```html
<section class="novidade">
  <h3>O visualizador agora é o do iPhone</h3>
  <p>As barrinhas que dançam ao lado da capa não eram as da Dynamic Island:
     eram mais grossas, mais altas e pintadas de uma cor só, tirada da capa.</p>
  <p>Agora são seis barras finas, com o mesmo vão e a mesma espessura do
     iPhone, e elas não são pintadas — a capa aparece por dentro delas,
     desfocada. Por isso cada barra tem um tom um pouco diferente da vizinha.
     No silêncio, viram pontinhos redondos em vez de sumir.</p>
  <figure>
    <img src="midia/visualizador-ilha.png" alt="Notch fechado com a capa do álbum à esquerda e seis barras finas coloridas à direita">
    <figcaption>Seis barras, vão igual à espessura, cor vinda da própria capa.</figcaption>
  </figure>
  <p>Música pausada também mudou: em vez de sumir do notch, ela fica — a capa
     escurece e as barras descansam nos pontinhos, como no iPhone. Como não há
     mais nada escondido pra revelar, passar o mouse abre o card direto.</p>
</section>
```

- [ ] **Step 6: Acrescentar a versão ao catálogo**

Em `Knobler/NovidadesCatalogo.swift:20`:

```swift
    static let versoes: [String] = ["0.25.0", "0.26.0", "0.27.0"]
```

- [ ] **Step 7: Rodar a bateria**

```bash
./tools/check.sh
```

Esperado: todos `ok`. O gate de novidades falha se a mídia referenciada no HTML não existir — se falhar aí, é o Step 4 que não saiu.

- [ ] **Step 8: Commit**

```bash
git add docs/now-playing.md README.md CHANGELOG.md \
  Knobler/Novidades/0.27.0.html Knobler/Novidades/midia/visualizador-ilha.png \
  Knobler/NovidadesCatalogo.swift
git commit -m "docs: visualizador nas medidas da ilha e pausado visível"
```

---

## Fechamento

Depois da Task 7, a entrega é `./tools/release.sh minor` — mas só depois de o usuário ver o notch com música tocando e aprovar. A validação de "idêntico" é dele, não de um check.
