# Capturas de tela direto no shelf (v0.10) — Design

Data: 2026-07-17 · Status: aprovado em conversa

## Objetivo

Toda captura de tela do macOS (⌘⇧3/⌘⇧4/⌘⇧5) entra automaticamente na
prateleira do notch, pronta pra arrastar pra qualquer app. O notch dá um
peek de 1,5s confirmando a chegada.

## Decisões (com o porquê)

| Decisão | Escolha | Porquê |
|---|---|---|
| Detecção | **NSMetadataQuery** com `kMDItemIsScreenCapture == 1` | Mecanismo oficial do Spotlight (CleanShot/Dropbox usam); pega captura em QUALQUER pasta configurada, sem polling e sem re-observar quando `com.apple.screencapture location` muda |
| Arquivo | **Só referenciar** — captura fica onde o macOS salvou | Zero risco/surpresa; remover do shelf não apaga o arquivo (comportamento atual do shelf) |
| Feedback | **Peek de 1,5s** — card expande mostrando a prateleira e fecha | Confirmação visual sem interação; capturas em sequência renovam o timer |
| Notch ocupado | Pergunta/ditado ativo → adiciona SEM peek | Card de pergunta tem prioridade; peek não pode roubar a cena |
| Escopo de mídia | Só imagens (`public.image` no filtro) | Gravações de tela (.mov) também têm o atributo e não cabem na prateleira |
| Ajustes | Toggle "Capturas de tela vão pro shelf", default ligado | Padrão de todos os módulos do app |

## Componentes

- **`ScreenshotWatcher.swift`** (novo, ~60 linhas) — `NSMetadataQuery` vivo
  (escopo home), predicado `kMDItemIsScreenCapture == 1`, escuta
  `NSMetadataQueryDidFinishGathering`/`DidUpdate`. Ignora resultados do
  gathering inicial (capturas antigas); só itens NOVOS pós-start entram.
  Callback `onScreenshot: ((URL) -> Void)?` na main queue. `start()`/`stop()`
  reagem ao toggle dos Ajustes.
- **`AppSettings`** — `screenshotsToShelf: Bool` (default true) + toggle na
  Section do shelf/Notch nos Ajustes.
- **`KnoblerApp`** (fiação) — `watcher.onScreenshot` → `shelf.add(url)` +
  peek: se nenhum vm tem `ask`/`dictation` ativo, `setExpandedDirect(true)`
  em todos os monitores e fechar após 1,5s (work item cancelável; nova
  captura renova; mouse em cima segura — `setHover` já cuida do resto).

## Bordas e erros

- Arquivo `.` temporário do screencapture: o Spotlight só indexa o definitivo;
  filtrar path que começa com `.` por segurança.
- Duplicata: `ShelfStore.add` já deduplica por URL; capacidade 8 já derruba
  os mais antigos.
- Captura deletada depois: init do ShelfStore já filtra inexistentes ao
  restaurar; ícone quebrado em runtime é aceitável (item sai no próximo launch).
- Sem permissão nova: NSMetadataQuery não pede TCC; app não é sandboxed.

## Fora do escopo (v1)

Mover/renomear arquivos, pasta própria, preview da imagem no shelf (ícone do
Finder já mostra thumbnail), gravações de tela, ações rápidas (copiar/anotar).

## Validação

- Build Release verde.
- E2E real: ⌘⇧4 → peek de 1,5s com a captura na prateleira → arrastar do
  shelf pro Finder/app; captura durante pergunta ativa → entra sem peek;
  toggle OFF → captura não entra; duas capturas seguidas → timer renova.
