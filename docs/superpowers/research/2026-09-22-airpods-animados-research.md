# Pesquisa — AirPods animados

Spec: `docs/superpowers/specs/2026-09-22-airpods-animados-design.md`

## Achados

### A1 — Hover no card de AirPods hoje não promove nada; liga o card de música por baixo
- Fonte: `Knobler/NotchView.swift:234-243` (`onHover` → `vm.setHover`), `Knobler/NotchPresentation.swift:31-35` (`airpods` vence `expanded`)
- Contradiz a spec: parcial — a spec supõe "hover promove ilha para card", mas não existe mecanismo; com o `setHover` atual, quando o timer dos AirPods vence, o notch cai direto no card de música.
- Pergunta que levanta: ao tirar o cursor do card grande dos AirPods, o notch fecha, ou pode abrir o card de música que "acordou" por baixo?

### A2 — Não há hold de timer para o card de AirPods
- Fonte: `Knobler/NotchViewModel.swift:619-644` (`holdNotification`/`scheduleDismiss`), `:532-535` (`holdIncoming`), `:674-680` (`showAirPodsCard`, 4 s fixos)
- Contradiz a spec: não — a spec pede "fica aberto enquanto o cursor estiver nele"; o padrão existe e se copia.

### A3 — Conectar já com bateria ≤ 10 % dispara dois anúncios seguidos
- Fonte: `Knobler/BluetoothMonitor.swift:100-110`
- Contradiz a spec: parcial — a spec separa conexão (ilha) de bateria baixa (card), mas não diz qual vence quando os dois chegam juntos.
- Pergunta que levanta: fone chegando descarregado mostra a ilha e depois o card, ou vai direto pro card de alerta?

### A4 — A ilha precisa de posição na prioridade de modos
- Fonte: `Knobler/NotchPresentation.swift:26-37` (ordem `… hud > update > airpods > expanded > pomodoro`)
- Contradiz a spec: parcial — a spec dimensiona a ilha como HUD mas não a posiciona.
- Pergunta que levanta: se você mudar o volume enquanto a ilha dos AirPods está aberta, o volume toma o lugar (como hoje) ou os AirPods seguram?

### A5 — O nome do modo aparece no `GET /status` da API local
- Fonte: `Knobler/KnoblerApp.swift:674`
- Contradiz a spec: parcial — um caso novo em `NotchMode` muda a string exposta.
- Pergunta que levanta: aceitável um valor novo (`airpodsIsland`) na API, ou a ilha deve aparecer como `airpods` também?

### A6 — O iPhone pinta o anel de verde; vermelho na bateria baixa
- Fonte: https://techwiser.com/dynamic-island-icons-and-symbols-meaning-guide/ , https://discussions.apple.com/thread/254336086
- Contradiz a spec: parcial — a spec não fixa a cor normal do anel.
- Pergunta que levanta: anel verde como no iPhone, ou branco pra combinar com o resto do notch?

### A7 — Nomes de símbolos na spec estão parcialmente errados
- Fonte: `/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist`
- Contradiz a spec: parcial — lados usam o singular (`airpod.left`, `airpodpro.left`, `airpod.gen3.left`), não `.left` sobre o nome do par; AirPods 4 (`airpods.gen4*`) só existe a partir do macOS 15.2; Pro 3 só no macOS 27; Max não tem lados nem estojo. Correção de tabela, sem pergunta.

### A8 — Tabela de Product IDs confirmada por dois projetos
- Fonte: https://github.com/lihaoyun6/AirBattery/blob/134e02f/AirBattery/Supports/Supports.swift#L525-L570 , https://github.com/lingyired/status-trio/blob/6900596/Sources/StatusTrioCore/Audio/AirPodsModel.swift#L97-L107 ; `system_profiler` local devolve `"device_productID" : "0x2024"`
- Contradiz a spec: não. IDs: 0x2002 (1ª), 0x200F (2ª), 0x2013 (3ª), 0x2019/0x201B (4 / 4 ANC), 0x200E (Pro), 0x2014/0x2024 (Pro 2), 0x2027/0x2028 (Pro 3), 0x200A/0x201F (Max). Parse como inteiro hex, não comparação de string.

### A9 — No macOS 14 o `bounce` só dispara por mudança de valor
- Fonte: `.swiftinterface` do Symbols.framework; WWDC23 10258
- Contradiz a spec: não — `.symbolEffect(.bounce, value:)` com contador; `isActive:` e repetição contínua são macOS 15.

### A10 — Já existe anel de progresso reutilizável
- Fonte: `Knobler/NotchView.swift:1532-1555` (`ActivityRingView`, cor laranja fixa, spring que ignora reduceMotion)
- Contradiz a spec: não — parametrizar cor/tamanho em vez de criar outro. Com `lineCap .round` em 0 sobra um ponto: esconder quando vazio.

### A11 — Dois cenários de snapshot de AirPods estão mortos
- Fonte: `tools/main.swift:639-647` (`airpods-strip-music`, `airpods-card-nomusic`), UI removida no commit `12c765f`
- Contradiz a spec: parcial — a spec só "atualiza" os cenários; esses dois não correspondem a UI nenhuma. Decisão sem pergunta: substituí-los pelas poses novas.

### A12 — Spec de 2026-07-19 descreve glance no hover que não existe mais
- Fonte: `docs/superpowers/specs/2026-07-19-airpods-notch-design.md` (Escopo), commit `12c765f`
- Contradiz a spec: não — registro; a spec nova marca a antiga como substituída.

### A13 — O tamanho do card está duplicado à mão
- Fonte: `Knobler/NotchPresentation.swift:154` e `Knobler/NotchView.swift:196`
- Contradiz a spec: não — mudar os dois juntos.

## Fila do grill

1. A1 — ao sair do card grande, fecha tudo ou pode cair no card de música? (trava A4)
2. A4 — volume/brilho no meio da ilha: toma o lugar ou espera?
3. A3 — fone chegando descarregado: ilha e depois card, ou card direto?
4. A6 — anel verde (iPhone) ou branco?
5. A5 — valor novo no `GET /status` ou mantém `airpods`?
