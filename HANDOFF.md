# 🏁 SESSÃO 2026-07-19/20 — Feature: AirPods no notch — v0.17

Feature nova, **implementada + revisada + mergeada em `master`**; build Release **instalado em `/Applications` e rodando estável**. **E2E final (card na conexão) NÃO confirmado pelo usuário** — falta permitir Bluetooth + conectar os AirPods. Push pro origin pendente.

## O que foi feito

- **AirPods no notch**: conectou AirPods → card transitório (~4s) com nome + bateria **L / R / estojo**; enquanto conectado, bateria no **hover** (faixinha junto da música, card dedicado quando não há música). Aviso de bateria baixa (≤10%) e toggle opt-out "AirPods no notch".
  - `Knobler/AirPodsBattery.swift` (novo): modelo puro + parser do JSON do `system_profiler SPBluetoothDataType -json` (chaves `device_batteryLevelLeft/Right/Case`, filtro `device_minorType == "Headphones"`), self-check `@main`/`-parse-as-library`.
  - `Knobler/BluetoothMonitor.swift` (novo): conexão via `IOBluetooth` **event-driven** (zero polling parado); bateria via `system_profiler` off-main + poll 60s **só enquanto conectado**; callbacks `onAnnounce`/`onUpdate`/`onDisconnect`; hysteresis de bateria baixa (10/20).
  - `NotchViewModel`: `airpods`/`airpodsCard` + `Mode.airpods` (prioridade após hud, antes de música) + `showAirPodsCard` (espelha `showHUD`).
  - `NotchView`: card de conexão + `airpodsRow(compact:)` (faixa com música / card sem) + supressão do placeholder; `currentSize` acomoda a altura.
  - `AppSettings` (toggle) + `KnoblerApp` (fiação, start/stop no sink de settings) + `tools/main.swift`/`snapshot.sh` (5 cenários).
  - `project.yml`: **`NSBluetoothAlwaysUsageDescription`** (fix do crash TCC — ver abaixo).

## Como foi feito (processo)

- brainstorm → spec (`docs/superpowers/specs/2026-07-19-airpods-notch-design.md`) → **pesquisa na máquina real** (system_profiler entrega L/R/estojo em ~0.19s; `ioreg` **não** tem as chaves aqui; API do IOBluetooth verificada por `swiftc -typecheck`) → plano (`docs/superpowers/plans/2026-07-19-airpods-notch.md`, 5 tasks).
- **Execução subagent-driven** (implementer + review por-task, tudo opus): gates self-check/typecheck/xcodebuild/snapshots. **Review final da branch** pegou 1 Important — falha transitória do `system_profiler` (nil no poll) caía no branch de disconnect e **matava o único timer**, some pra sempre → corrigido (nil só desconecta com `announce=true`) + re-revisado. Merge fast-forward em `master`. Ledger em `.superpowers/sdd/progress.md`.

## Bugs achados no E2E (debugging sistemático)

1. **App velho rodando**: `/Applications/Knobler.app` era de 18/jul (sem a feature) → **"nada apareceu no knob"**. Instalei o build **Release** novo por cima (backup do velho em `/tmp`).
2. **Crash de TCC no launch**: tocar no `IOBluetooth` sem `NSBluetoothAlwaysUsageDescription` **aborta o app** (SIGABRT via TCC, `Knobler-2026-07-20-090656.ips`) no macOS atual — não é prompt, é crash fatal. Corrigido em `project.yml` (commit `49086bb`). App agora sobe estável e pede permissão de Bluetooth normalmente.

## Validação

- Self-checks verdes (parser, incl. bordas: componente ausente/JSON lixo/sem AirPods), `swiftc -typecheck` do monitor, `snapshot.sh` (5 PNGs `airpods-*` lidos/validados), `xcodebuild` Debug **e Release** → BUILD SUCCEEDED.
- App Release rodando estável em `/Applications` (PID vivo, API `127.0.0.1:4477` respondendo, sem novo crash pós-fix).
- **PENDENTE — E2E do usuário**: permitir Bluetooth (Ajustes → Privacidade → Bluetooth) + conectar AirPods → confirmar o card. Não confirmado nesta sessão.

## Pendências e followups

- **E2E final não confirmado** (card na conexão) — depende de permissão de Bluetooth + conexão dos AirPods.
- **Push pendente**: `master` está à frente de `origin/master` (esta feature + pendências anteriores).
- **Design (de propósito)**: card só pipoca em conexão **nova**; AirPods já conectados no launch → sem card (bateria só no hover). Evita incomodar todo login.
- Minors não-bloqueantes (ver ledger `.superpowers/sdd/progress.md`): connect-já-baixo mostra 1 card só; `disconnectNotes` bounded no fix; teardown depende da notificação IOBluetooth (cobertura de notas completa via start + bluetoothConnected).
- `graphify-out/` não regenerado — rodar `/graphify` se quiser o grafo fresco.

---

# 🏁 SESSÃO 2026-07-19 (madrugada) — Feature: Descanso (bloqueio forçado de tela) — v0.16

Feature nova, **validada em tela ("funcionou") e commitada+pushada em `master`**. Build de debug instalado em `/Applications/Knobler.app`.

## O que foi feito

- **Descanso**: bloqueio de tela agendado que **força uma pausa** — overlay escuro (~90%, tela fantasma
  atrás) cobrindo TODAS as telas + contador regressivo MM:SS + rótulo, em **modo quiosque nativo**, com
  **escape de emergência** (segurar Esc 5s, dica fixa no rodapé). Dois gatilhos: lista própria + pausas do Pomodoro.
  - `Knobler/Descanso.swift` (novo): `struct ScreenBreak` (Codable, reusa `Schedule` dos Lembretes +
    `durationMinutes`), conforma `protocol Scheduled`, self-check (`#if DESCANSO_SELFCHECK`, compila junto de `Reminders.swift`).
  - `Knobler/DescansoView.swift` (novo): `BreakOverlayView` (contador **sleep-proof**, ancorado em endDate,
    SwiftUI puro, snapshot-able) + aba "Descanso" (lista + formulário de **8 modos**: os 7 dos Lembretes +
    "Daqui a X" relativo, + Stepper de duração 1–120min).
  - `Knobler/DescansoController.swift` (novo): janela de shield por tela (`CGShieldingWindowLevel`, subclasse
    `ShieldWindow` que vira key p/ capturar Esc), quiosque (`presentationOptions` validado), Esc-hold 5s, fade 0.4s.
  - `Reminders.swift`: `ReminderScheduler` → **`ScheduleEngine<Item: Scheduled>`** genérico (+ `protocol Scheduled`,
    `typealias`) — reusa o tick "nunca atrasado"/dedup pros dois. `remindersProvider`→`itemsProvider`.
  - `Pomodoro.swift`: `onPhaseBegin` (trava a tela nas pausas quando o toggle está on).
  - `AppSettings`: `@Published screenBreaks` (JSON) + `pomodoroLockScreen`; 3ª aba "Descanso" + toggle "Travar a tela nas pausas".
  - `KnoblerApp`: fiação (breakScheduler + descanso, wake ticka os dois, oneShot self-disable) +
    **`applicationShouldTerminate → .terminateCancel`** durante o lock (Cmd+Q NÃO é coberto pelo quiosque).
  - `tools/snapshot.sh` + `tools/main.swift`: render do overlay (`descanso.png` / `descanso-hold.png`).

## Como foi feito (processo)

- grill-me (8 decisões) → `SPEC-descanso.md` → **pesquisa (Swift real + web/campo)** que corrigiu 3 premissas:
  **teto honesto** (Cmd+Q e Spotlight TAMBÉM escapam, não só Activity Monitor); **Cmd+Q** precisa de
  `applicationShouldTerminate` (flags não pegam); `.canJoinAllSpaces`/`.fullScreenAuxiliary` **não empilham**
  por cima (é o nível). Conjunto de quiosque validado (Kiosk Mode TN + precedente SplashBuddy). Lock "de verdade"
  (`AEAssessmentSession`) é gated por entitlement aprovado pela Apple → fora de escopo.
- Plano em `docs/superpowers/plans/2026-07-18-descanso.md` (8 tasks em ordem de dependência) → execução inline,
  build/self-check a cada fase.

## Validação

- 3 self-checks verdes: `reminders self-check ok` (refactor genérico não quebrou a lógica), `descanso self-check ok`
  (modelo + Codable + engine tickando ScreenBreak), `pomodoro self-check ok`.
- `xcodebuild ... build` → **BUILD SUCCEEDED**; `snapshot.sh` regenera os PNGs (overlay validado visualmente, lido).
- **E2E do usuário: "funcionou"** — lock engatou, cobriu tela/menu bar, Esc-5s abortou. Build fresco em `/Applications`.

## Pendências e followups (não-bloqueantes)

- **Teto honesto**: Spotlight (⌘Espaço) e Monitor de Atividade **escapam** do lock — é empurrão com atrito, não
  segurança. Lock forte só via `AEAssessmentSession` (entitlement Apple; fora de alcance).
- **"Daqui a X" salvo vira oneShot absoluto** ao reabrir pra editar (relativo é açúcar de UI, sem case no `Schedule`).
- **Um lock por vez**: gatilho que chega com lock ativo é ignorado (sem empilhar).
- **Monitor conectado DURANTE o lock** não é coberto (janelas montadas no `begin`).
- **Esc via keyUp**: se o keyUp não chegar (janela não-key, raro), o hold poderia "grudar" — mitigado por ser
  key window; sem teste de estresse.
- **App troca pra `.regular` + activate no lock** (aparece no Dock/rouba foco por um instante) — preço do quiosque nativo.
- `graphify-out/` não regenerado (3 arquivos novos + refactor = material — rodar `/graphify` se quiser o grafo fresco).
- SPEC "Cortado da v1": master-toggle, API HTTP (`POST /break`), `SchedulePickerView` compartilhado (regra de três).

---

# 🏁 SESSÃO 2026-07-18 (noite) — Feature: Lembretes programados (notificações personalizadas + recorrentes)

Feature nova, **mergeada em `master` (push feito) e validada em tela ("funciona")**.

## O que foi feito

- **Lembretes programados**: notificações personalizadas agendadas pelo usuário que disparam
  **no notch** (não banner nativo). Agendador próprio no molde do `Pomodoro`, só-Foundation.
  - `Knobler/Reminders.swift` (novo): `enum Schedule` (`oneShot`/`calendar([DateComponents])`/`interval`),
    `struct Reminder` (Codable), `ReminderClock` (matemática pura do próximo disparo + rótulos humanos),
    `ReminderScheduler` (engine tick de relógio de parede, "nunca atrasado"), self-check assert-based
    (`#if REMINDERS_SELFCHECK`, compila com **`-parse-as-library`**).
  - `Knobler/RemindersView.swift` (novo): aba "Lembretes" nos Ajustes — lista (toggle/editar/apagar/empty)
    + formulário de **7 modos** (uma vez, diária, semanal por dias, mensal, anual, n-ésimo dia, intervalo),
    Picker de som com preview, URL opcional.
  - `AppSettings`: `@Published var reminders: [Reminder]` (JSON em UserDefaults) + `SettingsView` virou `TabView` (Geral | Lembretes).
  - `NotchNotification.openURL` + `openSourceApp` abre no clique; fiação do `ReminderScheduler` no AppDelegate
    (onFire → enqueue no notch + `NSSound` + desliga oneShot; wake observer em **`NSWorkspace.shared.notificationCenter`**).
  - `tools/snapshot.sh`: adicionados `Reminders.swift` e `RemindersView.swift` à lista (o harness compila `AppSettings.swift`).

## Como foi feito (processo)

- grill-me (9 decisões) → `SPEC-reminders.md` → **pesquisa com Swift real** (pegou 3 armadilhas antes do código:
  `.strict` obrigatório vs `.nextTime` que corrompe o "dia 31"; `weekdayOrdinal:-1` NÃO casa em `Calendar.nextDate`
  → helper próprio; wake postado no `notificationCenter` do NSWorkspace, não no default).
- Plano em `docs/superpowers/plans/2026-07-18-lembretes-programados.md` (7 tasks) → execução **subagent-driven**
  (implementer + reviewer opus por task). Todas Spec ✅, 0 Critical/Important.
- Review final (opus) pegou 1 Important que o build mascarava: `snapshot.sh` quebrado (faltavam os arquivos novos) → corrigido.

## Validação

- Self-check `reminders self-check ok` (7 modos + engine nunca-atrasado, relógio falso).
- `xcodebuild ... build` → **BUILD SUCCEEDED** (app integrado); `snapshot.sh` regenera os 36 PNGs.
- **E2E do usuário: "funciona"** — só apareceu após instalar o build fresco em `/Applications` (o app rodava a versão velha de 12:26; gotcha recorrente).

## Pendências e followups (não-bloqueantes)

- **Intervalo re-ancora a CADA launch do app** (não persiste âncora) — "a cada 4h" num Mac que relança o Knobler
  com frequência pode nunca disparar. Âncora persistida resolveria. (footgun spec-by-design)
- **Editar um "uma vez" já disparado** fica com `enabled=false` — usuário precisa religar no toggle.
- **oneShot com data no passado** nunca dispara e fica ligado (sem aviso no form).
- **`ReminderClock.calendar = .current`** cacheado no 1º acesso — mudança de fuso mid-run só reflete no relaunch.
- Cobertura do self-check: faltam asserts isolando re-ancoragem de intervalo e o path de edit/hashValue-recompute.
- `graphify-out/` não regenerado (feature nova é mudança material — rodar `/graphify` se quiser o grafo fresco).

---

# 🏁 SESSÃO 2026-07-18 — Bugfix: HUD volume/brilho (fim do brilho-fantasma + fluidez) + thumbnails reais no shelf

Sessão de **correção de bugs menores**, sem bump de versão.

## O que foi feito

- **Brilho "fantasma" morto** (`VolumeHUD.swift`): removido o `Timer` de 0,5s
  (`pollBrightness()`) que disparava a pílula pra **qualquer** mudança de brilho > 0,4% —
  incluindo brilho automático (sensor) e True Tone. Agora o brilho segue o mesmo caminho do
  volume: pílula só pelas teclas interceptadas (keycodes NX 2/3 → `adjustBrightness`).
  Removidos junto: campos `brightnessPollTimer`/`lastBrightness` e a linha morta associada.
  Decisão do usuário: abrir mão da pílula no slider da Central de Controle em troca de zero
  fantasma.
- **Fluidez do HUD** (`VolumeHUD.swift` + `NotchView.swift`): (a) enxugadas as chamadas
  síncronas ao CoreAudio por tecla — `adjust`/`toggleMute` publicam o valor recém-escrito em
  vez de re-ler o HAL via `publishCurrentState()` (cortou ~metade das chamadas HAL/evento em
  key-repeat, `defaultOutputDevice()` uma vez só por toque); (b) spring da barra do HUD
  `0.25/0.9` → `0.18/0.95` pra deslizar contínuo em vez de pular entre passos.
- **Thumbnails reais no shelf** (`ShelfThumbnailDragView.swift`): antes toda miniatura era
  `NSWorkspace.shared.icon(forFile:)` = ícone genérico do tipo. Agora usa
  **`QLThumbnailGenerator`** (QuickLookThumbnailing) pra prévia real do conteúdo (imagem/PDF/
  vídeo), com o ícone genérico só como placeholder enquanto gera / se não houver preview.
  Callback guarda contra reciclagem da view (`self.url == url`). `Shelf.swift` intocado; o
  drag continua igual.

## Validação

- **Build Debug + Release SUCCEEDED.** `xcodegen` não rodado (nenhum arquivo add/removido).
- **HUD:** usuário confirmou "funcionou". `/status` da API local: `axTrusted`/`tapEnabled`/
  `tapExists` = true (tap vivo → teclas de brilho embutidas são interceptadas),
  `brightnessAvailable` = true; dict `diagnostics` intacto após remover o poll.
- **Shelf:** `QLThumbnailGenerator` validado headless nesta máquina (thumbnail 24.5×30pt de um
  screenshot real). Usuário confirmou ("Muito bom").
- **Snapshots NÃO regenerados**: sem mudança de layout estático (HUD só muda timing de
  animação; a thumbnail do shelf é conteúdo de runtime, não aparece no harness).

## Pendências e followups

- Se em algum **teclado externo** as teclas de brilho não mostrarem a pílula (o built-in está
  confirmado ativo via tap), reavaliar um poll *gated* só pra teclas não interceptáveis — sem
  reintroduzir o fantasma.
- Afinar `dampingFraction` da barra se ainda parecer com pulo em uso real (ceiling anotado no
  comentário ponytail do `VolumeHUD`: upgrade = cache do device + listener de default output).

---

# 🏁 SESSÃO 2026-07-18 — Ferramental de agente: MCP de build/docs + supply-chain

Sessão de **infra do agente** (não bump de versão, nada de código Swift). A partir
de uma pesquisa (deep-research, 101 agentes), montamos os 3 anéis de feedback que
deixam o Claude Code escrever Swift com mais confiabilidade.

## O que foi feito

- **`.mcp.json`** (escopo de projeto, versionado):
  - **XcodeBuildMCP** `@2.6.2` (`npx`) — build/test com erro de compilador em JSON
    estruturado; habilita o loop escrever→compilar→ler erro→corrigir. **Pinado**, não
    `@latest`, após review de segurança flagar supply-chain (MCP roda com privilégios
    locais; `@latest` auto-executaria releases futuras não revisadas).
  - **xcode** = `xcrun mcpbridge` (MCP oficial da Apple, Xcode 26.6) — `DocumentationSearch`
    (docs Apple + WWDC) + `ExecuteSnippet` (REPL Swift) pra verificar símbolo de API
    antes de escrever, contra alucinação. Sem superfície de supply-chain (binário local).
- **`CLAUDE.md`** (novo) — build via XcodeGen, loop de snapshot (`tools/snapshot.sh`),
  quando usar cada MCP, e o guardrail: **nunca editar `Knobler.xcodeproj` à mão** (é
  artefato gerado; mexer em `project.yml` + `xcodegen generate`).
- Commits `4b5dd3c` (tooling) + este (HANDOFF); **push pra origin** limpando ~12 commits
  órfãos locais.

## Validação

- **Nenhum código Swift alterado** → gates de build/snapshot da v0.14 (Debug+Release
  SUCCEEDED, snapshots verdes) permanecem válidos; não re-rodados por não haver superfície
  compilável tocada.
- Pré-reqs conferidos: `npx`/node 25.9, `xcrun mcpbridge` presente (Xcode 26.6),
  `xcodegen` 2.45.4. `npm view xcodebuildmcp version` → 2.6.2 (pin confere).
- ⚠️ **Os MCPs NÃO estão ativos nesta sessão** — só carregam no start.

## Pendências e followups

- **AÇÃO DO USUÁRIO: reiniciar a sessão** e **aprovar** os servers do `.mcp.json` no
  prompt do Claude Code. O server `xcode` precisa do **Xcode aberto** pra responder.
- Bump futuro do XcodeBuildMCP é **manual**: `npm view xcodebuildmcp version` → editar o
  pin no `.mcp.json` → revisar changelog antes.
- **Opt-in não feitos** (só se pedir): hook `PostToolUse` de auto-build a cada edição
  (barulhento; loop do MCP já cobre sob demanda); `apple-docs-mcp`/`Context7` (redundantes;
  Context7 só vale pra docs de deps SwiftPM de terceiros).

---

# 🏁 SESSÃO 2026-07-18 — v0.14: Pomodoro no notch (pílula + card + menu)

## O que foi feito

- **Timer Pomodoro** (`Pomodoro.swift`, engine no naipe do CalendarCountdown): fases
  clássicas foco→pausa→pausa longa a cada N ciclos, durações configuráveis em Ajustes,
  **relógio de parede** (`endDate` absoluto, imune a tick perdido/sono), estado
  in-memory (some ao fechar). Lógica pura `advance`/`duration` + `selfCheck` embutido
  (rodável isolado via `@main` + `-parse-as-library`).
- **Controle pelo menu da barra** (itens dinâmicos por `runState`) e **pílula própria
  no notch** (compacto, toma conta do fechado): 🧠 tomate=foco, ☕ verde=pausa, MM:SS;
  HUD de volume/brilho interrompe 1,5s e volta sozinho.
- **Para no fim de cada fase**, notifica no notch + som (`Glass`, com toggle), espera
  você iniciar a próxima. Skip não conta o foco pro ciclo da pausa longa.
- **Card expandido do Pomodoro** (hover): fase + timer grande + "Ciclo N de M" +
  controles clicáveis (pausar/retomar/pular/resetar/iniciar próxima + ⚙︎ Ajustes),
  reusando o padrão do `AskCardView` (view → closure na vm → engine). Enquanto o
  Pomodoro está ativo a **música some do notch** (volta ao resetar); shelf/atividade
  seguem. Corrige o "hover abria a música" — o notch centra no que está ativo agora.

## Validação

- Self-check verde; snapshot harness com todos os estados (pílula + cards) inspecionados
  a olho; build Debug e Release **SUCCEEDED**. **E2E: usuário confirmou "está ótimo".**
- Feito por subagent-driven-development (5 tasks + review por task + review final opus,
  "merge com 1 ressalva" adjudicada: rótulo `Pausa longa ▸` equivale ao HUD de bateria
  já embarcado). Correções de rota: expressão top-level não compila no harness
  multi-arquivo → self-check via `@main`; `Snapshots/` e `Knobler.xcodeproj/` são gitignored.

## Pendências e followups

- Nova seção "Pomodoro" nos Ajustes (foco/pausa curta/longa/ciclos até a longa/som).
  Nada externo requerido.
- Minors não-bloqueantes: sem `deinit` invalidando o `Timer` (engine é singleton);
  `selfCheck` cobre a lógica pura (paths stateful via E2E). Se "só o pomodoro" incomodar
  com shelf/atividade visíveis no card, é gate de uma linha.

---

# 🏁 SESSÃO 2026-07-17 (noite 3) — v0.13: formatação de transcript com IA local

## O que foi feito

- **Ditado agora limpa o texto com IA local** (`TranscriptFormatter.swift`), no estilo
  "Fluid Intelligence" do FluidVoice: depois de transcrever (Parakeet), passa o transcript
  por um LLM local OpenAI-compatible (Ollama/LM Studio) que remove fillers ("é", "ééé",
  "tipo", "sabe"), falsos começos e arruma pontuação/acento/capitalização — **sem inventar
  conteúdo**. POST `{model,messages,temperature:0,stream:false}` → `choices[0].message.content`.
  Schema OpenAI puro (serve Ollama /v1 + LM Studio). Timeout 15s.
- **Modelo default `gemma3:4b`**, escolhido por benchmark na máquina (M3 Pro): ~0,9s quente,
  melhor PT-BR. **Abaixo de 4B a qualidade colapsa** (1B inverte sentido/apaga texto); **Qwen
  é armadilha** (thinking pode dar 120s, `think:false` inconsistente). Gemma 3 não pensa → imune.
- **Config** (seção Ditado): `formatTranscript` (default OFF, opt-in), `formatEndpoint`,
  `formatModel`. Prewarm no launch mantém o modelo quente. **Fallback pro cru em qualquer
  falha — nunca perde o ditado.** Formata uma vez → card de Ask e paste recebem texto limpo.

## Validação

- `xcodegen generate` + build Debug: **BUILD SUCCEEDED**. Self-check do parse roda no launch (DEBUG).
- Requisição real de produção validada contra o Ollama (curl idêntico ao que o Swift monta).
- **E2E: usuário confirmou** — transcrição + organização "quase instantânea", "funcionou
  maravilhosamente bem".

## Pendências e followups

- Modelos-cobaia do benchmark ainda no Ollama (~11 GB): gemma3:1b, gemma3n:e2b, llama3.2:1b,
  qwen3:1.7b, qwen3:4b. `gemma3:4b` é o que fica. Apagar quando quiser (`ollama rm <modelo>`).
- Nit menor: gemma às vezes não capitaliza/pontua o começo — ajustável no prompt se incomodar.
- `graphify-out/` NÃO regenerado (mudança modesta: 1 módulo novo). Regerar se quiser o grafo fresco.
- Requer `ollama serve` rodando + `ollama pull gemma3:4b` (uma vez) pra a feature funcionar.

---

# 🏁 SESSÃO 2026-07-17 (noite 2) — v0.12: suprimir preview nativo do print

## O que foi feito

- **Preview flutuante nativo do print suprimido** (`ScreenshotPreviewSuppressor.swift`,
  espelha `OSDSuppressor`): escreve `com.apple.screencapture show-thumbnail=false`
  enquanto o app roda; restaura no quit e ao desligar o toggle. **Só reverte se a
  supressão foi nossa** (flag `screenshotPreviewSuppressedByUs` em UserDefaults) —
  respeita quem já tinha o preview off. Toggle "Esconder preview nativo do print"
  nos Ajustes, visível quando "Capturas → shelf" está ligado; gate exige os dois.
  Wire no mesmo sink de `objectWillChange` + `applicationWillTerminate` do OSD.

## Validação

- Build Release verde. Ciclo verificado por `defaults read`: abre → show-thumbnail=0
  + flag=1; quit → chave deletada (preview volta) + flag=0; relança → 0 de novo.
  E2E: usuário confirmou que o thumbnail nativo NÃO aparece mais no ⌘⇧4.
- **Não precisou de `killall SystemUIServer`** (o macOS lê a pref a cada print) —
  sem piscar a barra de menus. Bônus: thumbnail off → print grava na hora → shelf
  captura mais rápido.

## Pendências e followups

- [ ] (herdados) E2E formal do v0.10 (toggle off/on, captura durante pergunta);
      trade-off do drag pro Finder; re-enfileirar notificação durante pergunta longa.

---

# 🏁 SESSÃO 2026-07-17 (noite) — v0.10 capturas no shelf + v0.11 arrastar imagem

## O que foi feito

- **v0.10 — capturas de tela vão pro shelf** (`ScreenshotWatcher.swift`):
  `NSMetadataQuery` (`kMDItemIsScreenCapture == 1 && public.image`) detecta cada
  print novo e joga no shelf; o card dá um peek de 1,5s (renovável, respeita o
  cursor em cima e não abre durante pergunta/ditado). Toggle "Capturas de tela
  vão pro shelf" nos Ajustes (default ligado). Só referência, não move o arquivo.
- **v0.11 — arrastar imagem do shelf ANEXA a foto** (`ShelfThumbnailDragView.swift`):
  a miniatura virou view AppKit + um monitor de mouse (`NSEvent` local) que
  inicia uma sessão de drag AppKit real. O item leva **bytes PNG + file-url no
  mesmo `NSPasteboardItem`** → o terminal do Claude Code (Electron) e browsers
  anexam a imagem; o Finder recebe o arquivo.

## GOTCHAS (caros de descobrir)

- `.onDrag` do SwiftUI só entrega **file-url** → Electron cola o CAMINHO.
- Um `NSView` de drag (overlay OU base) dentro do `NSHostingView` do notch
  **não recebe mouseDown** — o hit-testing do SwiftUI blinda. `acceptsFirstMouse`
  e `FirstMouseHostingView` NÃO resolveram. Solução: **monitor local**
  (`NSEvent.addLocalMonitorForEvents`) que pega o evento antes do SwiftUI e chama
  `beginDraggingSession` (técnica do Dropover/Dropshit). Registro das miniaturas
  por frame de tela; o monitor acha a que está sob o cursor.
- Receita do pasteboard pro Electron anexar imagem: **bytes da imagem tipados
  (public.png) via `NSPasteboardItem.setData` (síncrono) + file-url no MESMO item**.
  Só PNG → "nada"; só file-url → caminho; os dois juntos → anexa. (`NSItemProvider`
  assíncrono/`registerDataRepresentation` NÃO servem — o Chromium lê síncrono.)

## Validação

- Build Release verde. v0.10: print cai no shelf com peek (confirmado). v0.11:
  arrastar a miniatura pro terminal → imagem anexada (confirmado por captura do
  usuário); teclado e ditado seguem normais (sem `canBecomeKey=true`, revertido).

## Pendências e followups

- [ ] E2E formal do v0.10 (toggle off/on, captura durante pergunta) — o núcleo
      está validado; faltam os casos de borda.
- [ ] Trade-off do drag de imagem: verificar salvar no Finder (bytes+file-url
      juntos devem cobrir, mas não testado a fundo).
- [ ] (herdado) re-enfileirar notificação que chega durante pergunta longa.

---

# 🏁 SESSÃO 2026-07-17 (tarde 2) — v0.9 polido: transcript limpo, origem no card, fix do hover

## O que foi feito

- **"Error:" eliminado do transcript** (46432a5): hook migrado de deny+reason
  pro fluxo oficial `allow + updatedInput` — ecoa `questions` e preenche
  `answers {"<pergunta>": "<label(s)/texto>"}`; a tool completa como resultado
  normal. GOTCHA: `updatedInput` SUBSTITUI o input inteiro (sempre ecoar
  questions). Doc: hooks.md#askuserquestion.
- **Fix hover→música** (cfc93ac): hover no card de pergunta armava
  `expanded=true` invisível via `setHover`; ao responder, o mode caía em
  `.music` e o card de música abria sozinho. Modo `.question` agora não dirige
  expansão no hover de entrada (saída continua passando pra desarmar).
- **Origem da sessão no card** (3eb823f): hook manda `source` = basename do
  cwd; cabeçalho mostra "◐ knobler" — com várias sessões/FIFO você sabe quem
  pergunta. `knobler ask` manda "◐ CLI".

## Validação

- Tudo validado em sessão real com o hook ativo: pergunta com previews ASCII
  (split + hover trocando preview) OK; resposta virou tool result normal (sem
  vermelho); "◐ knobler" confirmado no card; bug da música reproduzido antes
  e ausente depois do fix. Build verde, app redeployado em /Applications.

## Pendências e followups

- [ ] (herdadas da sessão v0.9 abaixo — próximo escolhido: re-enfileirar
      notificações que chegam durante pergunta longa)

---

# 🏁 SESSÃO 2026-07-17 (tarde) — v0.9: perguntas do Claude Code no notch

## O que foi feito

- **AskUserQuestion → card no notch**: hook PreToolUse global
  (`~/.claude/hooks/knobler-ask.sh`, instalado por `tools/claude-hook/install.sh`,
  idempotente, matcher `AskUserQuestion`, timeout 600s) intercepta a pergunta,
  faz `POST /ask` e polling em `GET /ask/<id>` (300ms); resposta volta ao Claude
  via `permissionDecision: deny` + reason ("...NÃO repita a pergunta").
  Knobler fechado/✕/timeout → exit 0 sem output → pergunta cai no terminal.
- **Servidor** (`NotchAPIServer`): `POST /ask`, `GET /ask/<id>` (read-once),
  `POST /ask/<id>/cancel`; estados pending/answered/cancelled, TTL 15min,
  `ask: {pending}` no `GET /status`.
- **Card** (`Ask.swift` — modelo + `AskCardView`): botões com label+descrição,
  multi-select (toggles+Confirmar), paginação 1/N com envio único, preview
  ASCII em split (hover troca), campo "Outra resposta…" (Enter envia), ✕ e Esc
  cancelam. `Mode.question` com prioridade máxima; fila FIFO; fan-out a todos
  os monitores, primeira resposta vence; som "Pop" na chegada.
- **Teclado condicional** (`NotchWindow.allowsKeyboard`): janela só pode virar
  key com card na tela (sink Combine em `$ask` reverte com `resignKey`);
  digitar no card não ativa o app — terminal segue frontmost.
- **Ditado no card**: `DictationController.transcriptSink` desvia a transcrição
  pro campo (nível dentro do card); sem card, cola no app ativo como antes.
- Spec + plano 7 tasks por subagentes (implementer+reviewer por task, review
  final de branch): `docs/superpowers/specs/2026-07-17-perguntas-notch-design.md`
  e `docs/superpowers/plans/2026-07-17-perguntas-notch.md`.

## Validação

- Build Release verde em toda task; 4 snapshots novos (ask-simple/multiselect/
  preview/paged) conferidos; E2E real: ciclo curl (answered/404 read-once/
  pending 0), fila FIFO com cancel trocando o card, clique em botão, texto
  digitado e texto DITADO via `tools/knobler ask`; hook instalado exercitado
  de ponta a ponta (payload real → clique → deny JSON correto no stdout);
  regressão com Knobler fechado (exit 0, output vazio). Review final: aprovado.

## Pendências e followups

- [x] **Validação de 1º uso** ✅ (2026-07-17): grill real com 3 perguntas
      respondidas pelo notch — o modelo usou cada resposta e seguiu sem
      re-perguntar. O "Error:" vermelho do deny foi eliminado em seguida
      (46432a5): hook migrado pro fluxo oficial allow + updatedInput.answers —
      a tool completa como resultado normal, validado em sessão real.
      Nota: o modelo às vezes pergunta em texto puro em vez de AskUserQuestion;
      se incomodar, instruir via CLAUDE.md/skill a preferir a tool.
- [ ] Próximo (escolhido pelo usuário via card 🙂): re-enfileirar notificação
      que chega durante pergunta longa (hoje expira mascarada).
- [ ] Notificação que chega durante pergunta longa roda o auto-dismiss de 5s
      mascarada e some do notch (banner nativo ainda aparece — mesmo caso do
      ditado v0.8). Spec prometia re-enfileirar.
- [ ] HUD de volume/brilho invisível durante pergunta (OSD nativo suprimido +
      mode question no topo) — ajuste de volume num grill longo fica sem feedback.
- [ ] Ask promovido da fila FIFO chega sem som (Pop só no POST).
- [ ] `askKeyCancellables` não podado em desconexão de monitor (vazamento
      minúsculo; fix: dict por displayID).
- [ ] `GET /status` ask sem `queued` (spec pedia); `knobler ask` sem deadline e
      depende de python3 (ferramenta de teste, ok).
- [ ] graphify-out/ segue desatualizado (v0.8 + v0.9) — regenerar quando valer.

---

# 🏁 SESSÃO 2026-07-17 — v0.8: ditado por voz (estilo Superwhisper)

## O que foi feito

- **Ditado local-first** (`Dictation.swift`): segurar ⌥ direita → pílula "Ouvindo"
  com barra de nível → soltar → "Transcrevendo…" → texto inserido no app ativo
  (pasteboard + ⌘V sintético, clipboard restaurado em 0,5s). Esc/outra tecla
  cancela; toque <0,5s descartado.
- **Engine local default**: Parakeet TDT v3 via FluidAudio (1ª dependência SPM;
  pediu 0.12.4, resolveu 0.15.5 — `transcribe` exige `TdtDecoderState` inout).
  Modelo ~600MB baixado no 1º launch (~80s), ~66MB RAM. **Deepgram opcional**
  (nova-3, PCM linear16, key no Keychain) via toggle nos Ajustes.
- **⌥ direita** no tap existente do VolumeHUD (flagsChanged, keycode 61, bit
  device-específico 0x40 — `.maskAlternate` agregado prendia com as duas ⌥).
- Spec + plano com 7 tasks executados por subagentes (implementer + reviewer por
  task, review final de branch): pegou data race no buffer de mic (NSLock),
  preparo do modelo não re-disparável e o bug das duas ⌥ — os 3 corrigidos.
- Docs: `docs/superpowers/specs/2026-07-17-ditado-design.md` e
  `docs/superpowers/plans/2026-07-17-ditado.md`.

## Validação

- Build Release verde em toda task; harness com 23 cenários (3 novos de ditado,
  PNGs conferidos); `GET /status` → `dictation: {enabled:true, modelReady:true,
  cloud:false}`, axTrusted/tapEnabled true; E2E manual aprovado pelo usuário.

## Pendências e followups

- [ ] Timeout no DeepgramEngine (default 60s de URLSession — rede pendurada
      prende a pílula em "Transcrevendo…").
- [ ] Progresso real do download do modelo (hoje: flash `.preparing` de 2s).
- [ ] Erro de mic apontar Ajustes do Sistema (hoje: "Sem acesso ao microfone").
- [ ] Notificação que chega durante ditado fica atrás da pílula e pode expirar.
- [ ] GOTCHA de build: arquivo .swift novo → rodar `xcodegen generate` (o
      .xcodeproj é gitignored e fica stale → "cannot find X in scope").
- [ ] graphify-out/ desatualizado (novo módulo Dictation) — regenerar quando valer.

---

# 🏁 SESSÃO 2026-07-16 (tarde) — v0.7: espelho, mic e a saga do OSD do Tahoe

## O que foi feito

- **Espelho** (`Mirror.swift`): preview da câmera no card expandido (espelhado, como
  espelho real) pra se checar antes de reunião. Gatilhos: botão no card, auto-open
  2min antes de evento com link de call (Zoom/Meet/Teams/Webex/Whereby/Jitsi),
  `POST /mirror` na API. Música cede o lugar enquanto aberto; sessão da câmera
  liga/desliga com a view. Prefere a câmera EMBUTIDA (a default era "USB Video").
- **Indicador de microfone** (`MicMonitor.swift`): pontinho laranja no notch fechado
  enquanto qualquer app captura o input padrão (CoreAudio, sem permissão nova).
- **HUD de brilho por qualquer via**: poll 0.5s do brilho da tela embutida →
  pílula aparece pra tecla, Central de Controle e brilho automático.
- **Supressão do OSD nativo do Tahoe** (`OSDSuppressor.swift`): ver lição abaixo —
  a maior descoberta da sessão.

## Lição principal: OSD do Tahoe + tecla de brilho de teclado externo

Root cause confirmada com instrumentação (ring buffer de eventos no /status, sonda
IOHIDManager, watcher CGWindowList):

1. Tecla de brilho de teclado Apple EXTERNO é consumida ABAIXO do CGEventTap —
   nenhum evento chega à sessão. Interceptação é impossível nessa camada (o
   volumeHUD e o boring.notch têm o mesmo ponto cego).
2. O balão do Tahoe é desenhado pelo **ControlCenter** (janela layer 2005), não
   pelo OSDUIHelper — matar ControlCenter não é opção.
3. Fix em duas partes: `EnableSystemBanners=false` (OSD volta ao estilo
   Sequoia/OSDUIHelper; quebra no macOS 27 beta) + congelar OSDUIHelper com
   SIGSTOP (truque do SlimHUD). Aplicado pelo app no launch; restaurado no quit.

Processo que funcionou (usar da próxima vez DESDE O INÍCIO): instrumento com ring
buffer timestampado + validar o instrumento + watcher de janelas pra achar quem
desenha um overlay + ler o fonte dos concorrentes.

## Pendências

- [ ] Commit/push desta sessão (Mirror, MicMonitor, OSDSuppressor, brilho, docs).
- [ ] Teclado EMBUTIDO não testado: teclas de brilho dele podem ainda emitir NX 2/3
      (interceptáveis). Irrelevante na prática — o OSD já está suprimido.
- [ ] macOS 27: EnableSystemBanners deixa de funcionar — reavaliar supressão lá.
- [ ] Seletor de câmera do espelho (hoje: embutida fixa), antecedência configurável.

---

# 🏁 SESSÃO 2026-07-16 — v0.1 → v0.6: do esqueleto ao produto completo

## O que foi feito

Uma sessão-maratona que levou o Knobler de casca com Now Playing a app completo:

- **Harness de validação visual** (`tools/snapshot.sh`): 20 estados renderizados em
  PNG antes de cada entrega de UI. Processo obrigatório: rodar → olhar → só então deploy.
- **Design**: glow da capa no card, HUDs com ícones dinâmicos, sombras, molas
  diferenciadas (abrir com overshoot, fechar seco), crossfade na troca de faixa,
  peek do pausado, Reduced Motion.
- **Visualizador com áudio real**: CoreAudio process tap + FFT 5 bandas, auto-gain
  por banda, cor vibrante da capa. Perf: barras por scaleEffect, 20Hz, ~11% de um
  core tocando / 0,0% parado.
- **HUDs**: som + brilho (DisplayServices) + bateria (IOKit) em TODAS as telas.
- **Apple Music** além do Spotify (MediaController), shuffle real.
- **API local 4477**: /notify, /activity (anel de progresso persistente), /status
  (diagnóstico TCC/tap). CLI `knobler` em /opt/homebrew/bin + integrado ao deploy
  do zoi-studio.
- **Countdown de calendário** (EventKit, 15min antes, anel regressivo).
- **File shelf**: arrastar arquivo pro notch, guarda até 8, arrasta de volta.
- **Gestos** de swipe, **Ajustes** com toggles + login item, **ícone**, **Release
  build**, **repo GitHub privado** (luccas-silveira/knobler).

## Validação

- Harness com 20 cenários verdes; xcodebuild Release SUCCEEDED; app rodando.
- API testada de ponta a ponta com curl (notify, activity com progresso, done).
- Pixel-diff para provar estados estáticos; `GET /status` confirmou
  `axTrusted:true, tapEnabled:true` ao final.

## Pendências e followups

- [ ] Prompts de permissão restantes pós-`tccutil reset All com.zoi.knobler`:
      Automação (Spotify/Music), Gravação de Áudio do Sistema (visualizador),
      Calendário — aprovar quando aparecerem no primeiro uso de cada recurso.
- [ ] zoi-studio-frontend: commit local `0e77a6d` (knobler no deploy.sh) — push pendente.
- [ ] Backlog deprioritizado: AirPods (bateria = BLE reverso), lock screen,
      progresso de downloads, pomodoro nativo (a API já cobre via CLI).
- [x] Shelf persiste em UserDefaults (paths simples; app não é sandboxed).

## Lições da sessão (gravadas também em MEMORY.md)

- Trocar assinatura de código INVALIDA TCC silenciosamente: o tap "nasce" mas fica
  inerte; app lançado pelo terminal HERDA as permissões do shell (falso-positivo
  clássico ao diagnosticar). Correção: health-check recria o tap na transição de
  confiança + `tccutil reset All <bundle>` força prompt limpo.
- OSD de dispositivo do macOS (fone conectou/volume no fone) NÃO é interceptável;
  a pílula só aparece para mudanças iniciadas pelas nossas teclas.
- ImageRenderer não renderiza platform views (`.onDrop`) — placeholder amarelo;
  o harness desliga drop targets.
