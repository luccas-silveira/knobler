# Arrastar imagem do shelf como anexo (v0.11) — Design

Data: 2026-07-17 · Status: aprovado em conversa (após pesquisa no código do Chromium)

## Problema

Arrastar uma imagem do shelf pro terminal do Claude Code (Electron) cola o
**caminho** do arquivo como texto, em vez de anexar a imagem. O preview nativo
de screenshot do macOS anexa a imagem — queremos o mesmo do shelf.

## Causa-raiz (confirmada no código-fonte do Chromium)

O leitor de drag do Chromium no macOS é **síncrono** e popula
`dataTransfer.files` de dois jeitos, nesta lógica:

- `HasFile()` → true se o pasteboard tem `public.file-url`; aí o alvo recebe um
  `File` **com path** (e o terminal, por decisão do JS dele, insere o path como
  texto). É o que o `.onDrag { NSItemProvider(contentsOf:) }` do SwiftUI produz.
- Senão, `GetFileContents()` lê `dataForType:` de qualquer UTI que conforme a
  `public.image` → `File` **sem path**, montado dos bytes crus. É por aqui que o
  preview nativo anexa a imagem: ele põe os **bytes** no pasteboard, sem file-url.

O Chromium **não resolve file promises** (`NSFilePromiseProvider`) nem chama a
API assíncrona do `NSItemProvider` (`registerDataRepresentation`) — por isso as
tentativas com promise/data-rep entregaram "nada". Só vale **bytes crus
síncronos** via `NSPasteboardItem.setData`.

## Decisão

| Decisão | Escolha | Porquê |
|---|---|---|
| Mecanismo | Fonte de drag **AppKit** (`NSViewRepresentable` sobre a miniatura) | `.onDrag` do SwiftUI só expõe file-url; file promise não funciona no Chromium |
| Payload (imagem) | `NSPasteboardItem.setData(bytes, forType: public.png/…)` **sem** file-url | Único formato que o Chromium lê síncrono e anexa (igual ao preview nativo) |
| Payload (não-imagem) | file-url via `setString(url.absoluteString, .fileURL)` | Preserva o arrastar-arquivo original pra PDFs/zip/etc. |
| Trade-off aceito | Imagem sem file-url pode não salvar direto no Finder | Usuário priorizou anexar no terminal/apps; validamos os dois no teste |
| Ativação | `acceptsFirstMouse == true` | A janela do notch é `nonactivatingPanel`; o drag tem que iniciar sem ativar |

## Componente

- **`ImageDragSource.swift`** (novo) — `NSViewRepresentable` `ImageDragSource(url:)`
  hospedando `DragSourceView: NSView, NSDraggingSource`:
  - `acceptsFirstMouse` → true; `mouseDown` capturado (não repassa) pra habilitar
    o `mouseDragged`.
  - `mouseDragged` inicia `beginDraggingSession`: se o arquivo conforma a
    `public.image`, escreve os bytes tipados no `NSPasteboardItem` (sem file-url);
    senão, escreve o file-url. Drag image = miniatura da imagem (ou ícone do Finder).
  - `draggingSession(_:sourceOperationMaskFor:)` → `.copy`.
- **`Shelf.swift`** — no `shelfItem`, tirar o `.onDrag` do VStack e sobrepor
  `ImageDragSource(url:)` na miniatura de 30×30 (o X de remover fica fora, no
  canto, segue clicável).

## Bordas

- Arquivo apagado depois de entrar no shelf: `Data(contentsOf:)` falha → não
  inicia drag (item some no próximo launch, como já é).
- Não-imagem no shelf: cai no ramo file-url (comportamento antigo intacto).
- O overlay de drag cobre só 30×30 da miniatura — hover/peek do card seguem no
  nível do notch, sem conflito esperado (validar).

## Validação

- Build Release verde.
- E2E real: arrastar screenshot do shelf pro **terminal do Claude Code** →
  anexa a imagem (não o caminho); pro campo de imagem de um app/navegador →
  anexa; pro **Finder** → conferir se salva o arquivo (trade-off conhecido);
  arrastar um não-imagem (se houver) → continua indo como arquivo; o X de
  remover continua clicável.
