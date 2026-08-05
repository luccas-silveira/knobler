# As 10 conversões restantes do marketplace

Converter em peça (plugin) as 10 features que ainda dizem "Em breve" na vitrine,
fechando a etapa do marketplace. O piloto (Pomodoro) já provou a máquina:
`Knobler/Plugin.swift` (ficha + registro + `PluginHost`), `tools/plugincheck.swift`
(12 casos), vitrine em `Knobler/PluginsSettingsPane.swift`.

Ordem: as com painel de Ajustes primeiro (ABRIR já resolvido), depois as sem painel.

## Global Constraints

Valem em TODAS as tarefas. Violar qualquer uma é defeito.

1. **`Knobler/Plugin.swift` importa só `Foundation`.** É o que deixa
   `tools/plugincheck.swift` compilar a máquina de peças sem arrastar AppKit/SwiftUI.
   Efeito que passa por AppKit, SwiftUI, `AppSettings`, view model ou som **não pode**
   morar lá: vira closure emprestada pelo `AppDelegate`, no precedente de
   `PomodoroEfeitos` (`Plugin.swift:41-52`) — a ficha guarda as DECISÕES (quem escuta o
   quê, os guards, as bordas), o `AppDelegate` diz só COMO cumprir cada efeito.
   Cada peça convertida ganha o próprio struct `XEfeitos` e um campo em `PluginDeps`.
2. **`PluginID` e o nome de seção NUNCA são renomeados.** Renomear id desinstala a peça
   na máquina de quem já usa. Por isso o card da peça `anotacao` se chama "Desenho".
3. **Desinstalar não apaga nada** — dado, preferência, Keychain, perfil no relay ficam.
   Sem diálogo de confirmação.
4. **A ordem salva das seções nunca é tocada** por instalar/desinstalar
   (`notchSectionOrder`, `notchSectionsFixadas`).
5. **Dependência entre peças degrada calada**: a opção some, sem aviso e sem oferta de
   instalar. A pergunta é `deps.instalado(_:)` / `PluginHost.shared.estaInstalado(_:)`,
   e `false` é caminho normal, não erro.
6. **`pronta: true` na ficha** é o que acende os botões do card. Toda tarefa que
   converte uma peça vira essa chave E atualiza a lista travada no `plugincheck`
   (`tools/plugincheck.swift:285`), senão o assert quebra de propósito.
7. **Gates**: `./tools/check.sh` verde e
   `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build`
   ok ao fim de cada tarefa. Check novo = entrada nova em `tools/check.sh`.
   Harness escrito como `main.swift` não aceita `-parse-as-library`.
8. **Nunca editar `Knobler.xcodeproj` à mão** — é artefato do XcodeGen (`project.yml`).
   Arquivo novo em `Knobler/` exige `xcodegen generate`.
9. Comentários e strings de UI em **pt-BR**. Simplificação deliberada com ceiling
   conhecido leva comentário `// ponytail:`.
10. **Escopo mínimo (ponytail)**: converter é mover o nascimento, dar o `parar()`,
    resolver o ABRIR e virar a chave. Não é refatorar a feature, não é renomear tipo,
    não é criar protocolo novo. Se a feature já tem `start()/stop()`, `parar()` chama o
    que já existe.
11. Cada tarefa acrescenta **um caso novo** ao `tools/plugincheck.swift` (no mínimo:
    a peça está `pronta`, e sem ela na lista de instalados o serviço não nasce) e uma
    linha no `## [Unreleased]` do `CHANGELOG.md`.
12. Commit por tarefa, mensagem em pt-BR no padrão do repo (`feat(plugins): ...`).

### O ABRIR das peças sem painel

Decisão desta etapa, válida das tarefas 7 a 10: **o `abrir` de peça sem painel mora na
view** (`PluginsSettingsPane.abrir(_:)`, hoje em `PluginsSettingsPane.swift:192`), como
um `switch peca.id` no ramo em que `peca.painel == nil`. Motivo: a ação passa por
AppKit/SwiftUI e a ficha é Foundation puro (constraint 1); pôr uma closure `abrir` na
ficha obrigaria a fiar o `AppDelegate` na vitrine por um botão só.

---

## Task 1 — Lembretes

**Alvo**: `ReminderScheduler` (`KnoblerApp.swift:85`), fiado em `KnoblerApp.swift:447-472`.

- Criar `LembretesEfeitos` em `Plugin.swift` com as closures que o `AppDelegate`
  empresta: os itens (`AppSettings.shared.reminders`), o que fazer quando dispara
  (card + som), e desligar o lembrete de uma vez só (`enabled = false`).
- Escrever `montarLembretes(_ deps:)` no estilo de `montarPomodoro`: cria o
  `ReminderScheduler`, liga os providers, registra o observer de
  `NSWorkspace.didWakeNotification` e chama `start()`.
  ⚠️ Se registrar o observer exigir AppKit, o registro fica no `AppDelegate` como mais
  um efeito e a ficha só decide QUE ele existe.
- `ReminderScheduler: PluginServico` com `parar()` que invalida o timer e **remove o
  observer do wake** — observer vazado é o bug que sobrevive à desinstalação.
- `AppDelegate`: `reminderScheduler` some como propriedade; os pontos que ainda o
  tocam (`snooze()` em `:156-162`, handler do botão do card em `:1019-1021`) passam a
  falar com `plugins.servico(.lembretes)` e viram no-op quando a peça não está viva.
- `pronta: true`, `plugincheck` (lista travada + caso novo), `CHANGELOG.md`.

## Task 2 — Descanso

**Alvo**: `DescansoController` (`KnoblerApp.swift:90`) + o `breakScheduler` que o
alimenta (`KnoblerApp.swift:476-485`).

- Mesmo desenho: `DescansoEfeitos`, `montarDescanso(_ deps:)` criando controller +
  scheduler e ligando os providers.
- `parar()`: encerra o overlay em curso se estiver ativo e para o scheduler.
- **Ponta da única dependência plugin→plugin**: `montarPomodoro` já pergunta
  `deps.instalado(.descanso)` antes de travar a tela na pausa (`Plugin.swift:401`). Com
  o Descanso vivo de verdade, o Pomodoro precisa **falar com o serviço** e não com uma
  propriedade do `AppDelegate` — o caminho é `plugins.servico(.descanso)` no efeito
  `pausaComecou`. O caminho "sem Descanso" continua provado só no harness.
- `applicationShouldTerminate` (`KnoblerApp.swift:1374-1375`) consulta
  `descanso.isActive` pra vetar o quit: com a peça desinstalada não há veto — é o
  comportamento certo, mas escreva isso como comentário no ponto.
- `pronta: true`, `plugincheck`, `CHANGELOG.md`.

## Task 3 — Mensagens LAN

**Alvo**: `LANMessaging` + `MessageStore` (`KnoblerApp.swift:64-65`), fiação em
`:359-390`, start condicionado em `:1073`, resposta em `:1043-1046`, `flush()`/`stop()`
no `applicationWillTerminate` (`:1387-1392`).

- `MensagensEfeitos` + `montarMensagens(_ deps:)`. O serviço vivo carrega o
  `LANMessaging` e o `MessageStore` juntos (uma peça, dois objetos) — um struct/classe
  pequena conformando `PluginServico` é mais curto que dois registros.
- `parar()`: `messageStore.flush()` + `lanMessaging.stop()` + soltar os cancellables.
- **As views recebem `.environmentObject(lanMessaging)` / `(messageStore)`**
  (`KnoblerApp.swift:1001-1002`, `:1415`). Com a peça desinstalada não há objeto para
  injetar. A seção `mensagens` e o painel já somem sozinhos (F3), então a saída mais
  curta é injetar instâncias vazias/ociosas quando a peça não está viva — **não** tornar
  o `environmentObject` opcional em todas as views. Escolha e justifique num
  `// ponytail:`.
- `pronta: true`, `plugincheck`, `CHANGELOG.md`.

## Task 4 — Notificações externas (webhooks)

**Alvo**: `WebhookClient` (`KnoblerApp.swift:63`), `onNotify` em `:397-399`,
liga/desliga por ajuste em `:563-567`, `shutdown()` em `:1387`.

- `WebhooksEfeitos` + `montarWebhooks(_ deps:)`. O ajuste
  `AppSettings.shared.webhookNotifications` continua mandando no `start()/stop()`
  **dentro** da peça viva — instalada e desligada por ajuste é estado normal.
- `parar()`: `shutdown()`.
- `SettingsView` recebe `webhookClient` por parâmetro de init (`KnoblerApp.swift:1413`).
  Com a peça desinstalada o painel `webhooks` nem aparece na barra lateral (F3), mas o
  init continua exigindo o objeto — resolva do jeito mais curto (parâmetro opcional ou
  cliente ocioso) e marque a escolha.
- `pronta: true`, `plugincheck`, `CHANGELOG.md`.

## Task 5 — Ditado

**Alvo**: `DictationController` (`KnoblerApp.swift:67`), fiação em `:221-245`,
diagnóstico no status da API em `:543`.

- `DitadoEfeitos` + `montarDitado(_ deps:)`.
- **Depende de recurso de outra superfície**: o tap da tecla direita chega pelo
  `volumeHUD.onRightOption` (`KnoblerApp.swift:233-235`), e o VolumeHUD é de fábrica —
  logo é dependência para baixo, não plugin→plugin. O encaminhamento vira efeito: o
  `AppDelegate` continua dono do `onRightOption` e repassa para
  `plugins.servico(.ditado)`, que é `nil` com a peça desinstalada.
- `parar()`: para o motor de reconhecimento e solta o encaminhamento.
- Esta é a primeira peça com **gancho global** — se o ditado não acordar ao instalar sem
  reiniciar, **não invente reinicialização de tap**: o remédio aceito no mapa é o aviso
  "reinicie o Knobler pra concluir", que `docs/plugins.md` já documenta. Registre o
  comportamento observado no relatório.
- `pronta: true`, `plugincheck`, `CHANGELOG.md`.

## Task 6 — Desenho (`PluginID.anotacao`)

**Alvo**: `AnnotationController.shared` (`AnnotationController.swift:114`), guardado em
`KnoblerApp.swift:91`, `start()` em `:201`, diagnóstico em `:522`.

- Primeira peça `.shared`: o singleton **continua singleton** (views o consomem direto).
  Converter aqui é `montarAnotacao` chamando `AnnotationController.shared.start()` e
  devolvendo um `PluginServico` que, no `parar()`, desliga o controller (encerra os
  overlays por tela e solta o que `refreshScreens()` mantém).
- Não transforme o singleton em instância — é refatoração fora do escopo (constraint 10).
- `pronta: true`, `plugincheck`, `CHANGELOG.md`.

## Task 7 — Espelho (sem painel, com rota de API)

**Alvo**: `MirrorController.shared` (`Mirror.swift:13`); abertura automática por
calendário (`KnoblerApp.swift:487-502`), rota `POST /mirror` (`:505-518`), botão do card
(`NotchView.swift:1135-1148`, `:1215`).

- `montarEspelho` devolve um `PluginServico` cujo `parar()` solta a câmera
  (`release()`) e desfaz a abertura automática.
- O `guard PluginHost.shared.estaInstalado(.espelho)` do `POST /mirror` já existe
  (`NotchAPIServer.swift`) — **confirme** que agora ele tem caminho real e não regrida.
- A abertura automática por calendário (`mirrorBeforeMeetings`) precisa do mesmo guard.
- **ABRIR**: primeira peça sem painel. Implementar o `switch` decidido acima em
  `PluginsSettingsPane.abrir(_:)` — Espelho acende a câmera no notch da tela principal
  (mesma chamada de `MirrorController.activate(on:expand:)` usada pela rota).
- `pronta: true`, `plugincheck`, `CHANGELOG.md`.

## Task 8 — Nota rápida (sem painel)

**Alvo**: `QuickNote.shared` (`QuickNote.swift:17`); item de menu da barra
(`KnoblerApp.swift:1227-1230`) chamando `toggleQuickNote()` (`:1264-1292`); `active =
false` no `applicationWillTerminate` (`:1381`); consumida por `NotchView.swift:19` e
`NotchViewModel.swift:266,299,367`.

- `montarNotaRapida` devolve serviço cujo `parar()` é `QuickNote.shared.active = false`.
- **Com a peça desinstalada, o item de menu da barra some** (é a superfície dela fora do
  card) e `toggleQuickNote()` vira no-op.
- **ABRIR**: chama o mesmo `toggleQuickNote()` — extraia o mínimo para que a vitrine
  possa acioná-lo sem duplicar a lógica de "tela sob o mouse".
- `pronta: true`, `plugincheck`, `CHANGELOG.md`.

## Task 9 — Preview de Link (sem painel, sem serviço)

**Alvo**: `LinkPreview.shared` (`LinkPreview.swift:18`), aberto direto de
`Shelf.swift:155,231` (`abrir(url, on:)`); `KnoblerApp.swift:890` decide scroll.

- A feature é praticamente sem estado: `nascer` devolve um serviço mínimo só para a peça
  existir viva; o valor real da conversão está no **guard nos pontos de uso** —
  `Shelf.swift` só oferece o botão/ação de preview com
  `PluginHost.shared.estaInstalado(.previewLink)` (regra 5: a opção some, calada).
- `parar()`: fecha o preview aberto, se houver.
- **ABRIR**: sem URL não há o que espiar. Escolha o comportamento honesto mais curto —
  abrir a seção `link` do card ou levar à prateleira — e registre a escolha. Não invente
  tela nova.
- `pronta: true`, `plugincheck`, `CHANGELOG.md`.

## Task 10 — Conversão de arquivo (sem painel, sem seção)

**Alvo**: `FileConverter` (utilitário estático), chamado de `Shelf.swift:237`,
`ShelfDrop.swift:72`, `ShelfPreview.swift:68,104`. **Zero toques em `KnoblerApp.swift`**.

- Não há serviço para nascer: `nascer` devolve um serviço mínimo, e a conversão é
  gateada nos pontos de uso — os alvos de conversão só aparecem na prateleira com
  `PluginHost.shared.estaInstalado(.conversao)`. Isto é exatamente o que o ticket 002
  previu ("botões da prateleira somem quando Preview ou Conversão saem").
- `parar()`: nada a parar — escreva o porquê num comentário em vez de inventar estado.
- **ABRIR**: sem arquivo não há o que converter — mesma decisão da tarefa 9.
- `pronta: true`, `plugincheck` (agora com as 11 peças na lista travada), `CHANGELOG.md`.

## Fechamento (fora das tarefas, feito pelo controlador)

Depois da revisão final: `docs/plugins.md` e `docs/architecture.md` deixam de falar em
"Em breve", e a etapa fecha com `./tools/release.sh minor`.
