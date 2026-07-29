# Preview da conversão no shelf

Data: 2026-07-29

## Problema

O shelf converte imagem, PDF, Markdown e vídeo pelo menu de contexto, mas às
cegas. `Shelf.swift:147` chama `FileConverter.convert` direto e o arquivo nasce
gravado ao lado do original. Disso saem três incômodos, todos com a mesma raiz —
não existe estado intermediário entre "escolhi no menu" e "arquivo no disco":

1. **Não dá pra ver o que vai sair.** Nem tamanho, nem dimensões, nem a cara do
   resultado.
2. **Não dá pra escolher qualidade.** Os parâmetros são constantes no código:
   `0.9` de compressão no JPEG/HEIC (`ImageConverter.swift:57`), fator de
   rasterização fixo no PDF→PNG, preset do AVFoundation escolhido por
   disponibilidade e não por intenção.
3. **Suja o disco.** Conversão ruim deixa um arquivo pra apagar na mão.

## Desenho

Converter sempre para uma pasta temporária e só mover para o destino final
quando o usuário confirmar. O disco sujo some por construção, e o arquivo
temporário é o que o preview mostra.

### Opções de conversão

```swift
struct ConversionOptions {
    enum Quality { case alta, media, baixa }
    enum Scale { case full, half, quarter }
    var quality: Quality = .alta
    var scale: Scale = .full
}
```

Os quatro conversores recebem `options` e `to directory:`. Hoje cada um chama
`FileConverter.uniqueURL(for: url)`, que trava a saída na pasta do original — é
essa amarra que impede o arquivo provisório.

O mapeamento preset→parâmetro vive em cada conversor, porque só ele sabe o que a
escala significa no seu formato:

| Conversor | Qualidade | Escala |
|---|---|---|
| `ImageConverter` | `kCGImageDestinationLossyCompressionQuality` 0,9 / 0,7 / 0,5 | redimensiona o `CGImage` |
| `DocumentConverter` (PDF→PNG) | ignorada (PNG é lossless) | fator de rasterização 2x / 1x / 0,5x |
| `DocumentConverter` (Markdown→PDF) | ignorada | ignorada (PDF é vetorial) |
| `VideoConverter` | presets `HighestQuality` / `MediumQuality` / `LowQuality` | `AVMutableVideoComposition` |

`FileConverter.convert` repassa os dois parâmetros. Nenhuma decisão nova entra
nele: continua só roteando por tipo.

O card esconde a linha de escala quando ela não se aplica (Markdown→PDF) e a
linha de qualidade quando o destino é PNG.

### Escala em vídeo

`AVAssetExportSession` não aceita resolução arbitrária por preset. Os presets de
dimensão (`AVAssetExportPreset1280x720` e afins) amarram bitrate junto e
colidiriam com o eixo de qualidade, então a escala vira um
`AVMutableVideoComposition` com `renderSize` = `naturalSize × fator` e um
`CGAffineTransform(scaleX:y:)` na instrução da trilha de vídeo.

Duas consequências:

- **Escala < 100% desliga o passthrough.** O remux instantâneo de hoje só existe
  quando nada é reescrito. Com escala em 100% o comportamento atual fica intacto,
  passthrough incluso.
- **`renderSize` ímpar quebra o encoder H.264.** As dimensões são arredondadas
  pra par.

### Estado

`ShelfPreview`, um `ObservableObject` novo:

```swift
let source: URL              // original, continua no shelf
let target: ConversionTarget
var options: ConversionOptions
var output: URL?             // resultado atual, em /tmp
var outputBytes: Int64?
var outputPixelSize: CGSize? // nil em PDF multipágina e vídeo sem trilha
var extraPages: Int          // PDF→PNG: páginas além da primeira
var running: Bool
var progress: Double         // só vídeo
```

Vive no `ShelfStore` (`var preview: ShelfPreview?`), **um de cada vez** — abrir
um preview novo descarta o anterior.

Trocar preset dispara reconversão: cancela a corrente
(`AVAssetExportSession.cancelExport`, que só importa no vídeo), apaga o `output`
antigo e converte de novo pra um subdiretório próprio em
`FileManager.default.temporaryDirectory`.

**Salvar** move o arquivo pro diretório do original com o
`FileConverter.uniqueURL(for:)` que já existe e adiciona ao shelf — mesmo destino
de hoje, só que no fim do fluxo em vez de no começo. **Descartar** apaga o
diretório temporário.

Limpeza do temporário em três gatilhos: descarte, reconversão e
`applicationWillTerminate`. Um `kill -9` deixa lixo em `/tmp`, que o macOS limpa
sozinho — não há varredura na inicialização.

### Card

A seção Prateleira ganha um modo: com `shelf.preview != nil` ela mostra o preview
no lugar da grade de itens, e o `NotchViewModel` recebe
`focoPendente = .prateleira` mais `focusLocked` — o mesmo mecanismo que o clique
no card de mensagem já usa. A faixa de ícones e o swipe continuam funcionando; o
foco só não foge sozinho do preview enquanto ele está aberto.

Conteúdo, de cima pra baixo:

```
┌─ notch aberto ────────────────┐
│  ┌────────┐  foto.jpg         │
│  │ minia  │  2,4 MB → 810 KB  │
│  │ tura   │  1920×1080        │
│  └────────┘                   │
│  Qualidade  [Alta] Média Baixa│
│  Tamanho    [100%]  50%   25% │
│  [ Salvar ]      [ Descartar ]│
│  ● ● ◉ ● ●   (faixa)          │
└───────────────────────────────┘
```

Enquanto reconverte, os números esmaecem e Salvar desabilita; no vídeo a barra de
progresso ocupa a linha dos números. `extraPages > 0` acrescenta "+3 páginas" sob
a miniatura — o preview mostra a primeira, Salvar grava todas.

A miniatura vem de `NSImage(contentsOf:)` pra imagem e PDF, e de
`AVAssetImageGenerator` no primeiro segundo pro vídeo. Deliberadamente **não** usa
`QLThumbnailGenerator` nem `NSWorkspace.icon`: o `CLAUDE.md` registra que os dois
viram o ícone de "proibido" no `ImageRenderer` offscreen, e este card precisa
entrar no harness de snapshot.

## Verificação

- **`tools/conversionpreviewcheck.swift`** — gate novo, entra em
  `tools/check.sh`. Cobre a lógica pura: mapeamento preset→parâmetro por tipo,
  arredondamento par do `renderSize`, escala ignorada onde não se aplica, e o
  ciclo de vida do temporário (reconverter apaga o anterior, descartar apaga o
  diretório, salvar move e não deixa resto).
- **`tools/snapshot.sh`** — cenários `shelf-preview-imagem` e
  `shelf-preview-video`. O segundo tem barra de progresso e entra na lista dos
  não-determinísticos do `CLAUDE.md`. Os arquivos novos entram na lista manual do
  script.
- **Manual, no app rodando** — converter uma imagem de verdade, trocar os
  presets, conferir que o tamanho muda, salvar, e conferir que `/tmp` ficou
  limpo. Não dá pra automatizar aqui.

## Fora de escopo

- Conversão em lote (vários itens do shelf de uma vez).
- Escolher pasta de destino diferente da do original.
- Lembrar o último preset entre conversões.

Nenhum dos três aparece nos incômodos que motivaram a feature.
