# 🏁 SESSÃO 2026-07-29 (tarde) — o crash em Mac novo e a conversa que abria no topo

Sessão curta e reativa: dois bugs relatados de fora, dois releases publicados
(**v0.13.1** e **v0.13.2**). O primeiro era grave — o app não abria em nenhuma
máquina limpa desde sempre.

## O que foi feito

**v0.13.1 — o app morria no launch em todo Mac que não fosse este.** Relato:
"crasha na hora que abre". O crash log entregou a resposta em uma linha:
`"termination": {"namespace":"TCC", ...}` pedindo
`NSBluetoothAlwaysUsageDescription`. O `BluetoothMonitor` registra
`IOBluetoothDevice.register` no startup (`KnoblerApp.swift:462`, e
`airpodsNotch` tem default `true`), o TCC pede a permissão, não acha a chave no
`Info.plist` e chama `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__` — `abort`, não
erro recuperável. Fix: a chave em `project.yml`.

**Por que era invisível aqui.** O TCC só aborta no **primeiro** pedido. Esta
máquina já tinha a decisão gravada, então o caminho fatal nunca era percorrido —
o bug era 100% reproduzível lá fora e 0% aqui. Nenhum gate pegaria: não é
compilação, não é lógica, é uma chave de plist ausente exercitada só por TCC
virgem.

**v0.13.2 — a conversa abria no topo.** O `ScrollView` de `MessagesView.swift`
não tinha âncora, então nascia no histórico mais antigo e obrigava a rolar até
o fim toda vez. `.defaultScrollAnchor(.bottom)` (macOS 14.0+, dentro do target)
resolve abertura e mensagem nova de uma vez — sem `ScrollViewReader`, `id` ou
`onChange`.

**Documentação.** O `README.md` afirmava *"não pede Bluetooth"* e o caveat do
cask dizia o mesmo — a premissa errada que manteve a chave fora do plist.
Corrigidos os dois, mais `docs/airpods.md` (texto real do prompt),
`docs/messages.md` (âncora da conversa) e uma seção nova em
`docs/troubleshooting.md` pro sintoma "o app fecha sozinho ao abrir".

## Validação

`tools/check.sh` **16 ok**. Build Release limpo nos dois releases.

O fix do Bluetooth foi validado **com controle**, não por leitura de código:

| | TCC | Build | Resultado |
|---|---|---|---|
| A | Bluetooth resetado | v0.13.0 | morreu, `namespace: TCC`, assinatura idêntica à relatada |
| B | Bluetooth resetado | com a chave | vivo |
| C | 9 serviços resetados (tudo menos Acessibilidade) | com a chave | vivo 30 s, sem crash log novo |

`tccutil reset <Serviço> com.zoi.knobler` é o único jeito de simular Mac limpo
sem ter um. O serviço chama-se **`BluetoothAlways`**, não `Bluetooth`. O zip
publicado da 0.13.1 foi baixado e conferido: sha256 bate com o cask e a chave
está no `Info.plist` de dentro.

O fix da conversa **não tem validação automatizada** — `ScrollView` não
renderiza no harness de snapshot (`NSScrollView` por baixo, área preta) e a
conversa exige um peer real na rede. Confirmado só no app, pelo usuário.

## Pendências e followups

- **`Permission` não lista Bluetooth** (`Permissions.swift:27`). O painel
  Ajustes → Permissões mostra 7 permissões e o app usa 8 — a de Bluetooth não
  tem linha nem estado. As docs já foram corrigidas; falta o código.
- **Hipótese descartada, registrada pra não voltar:** o `codeSigningTrustLevel:
  4294967295` do crash log **não** indica problema de assinatura. É o normal de
  app não-notarizado com quarentena removida, e não impede o launch. O primeiro
  palpite da sessão (cert self-signed) estava errado.
- Notarização segue não feita — `release.sh` já tem o caminho pronto
  (`KNOBLER_NOTARY_PROFILE`), falta o Apple Developer Program.

# 🏁 SESSÃO 2026-07-29 (fim de manhã) — crítica de UX da nota rápida e os quatro fixes

Sessão de auditoria, não de feature. `/impeccable critique` na nota rápida
entregue de manhã deu **15/40 (Poor)** — nota concentrada em segurança do dado
e controle, não em aparência (visualmente a feature já estava dentro do
DESIGN.md). Quatro dos cinco achados foram fechados; o quinto virou brief.

## O que foi feito

Tudo em `fix/nota-rapida-ux` (`3d61617`), **não mergeado em `master`**.

**P0 — a tecla ia pro app errado.** `mode` prioriza `.notification`/`.hud`
acima de `.music`. Quando uma delas entrava, o `TextEditor` saía da árvore, o
`.onDisappear` zerava o foco, `keyboardAllowed` caía e `KnoblerApp.swift:815`
chamava `panel.resignKey()`. As teclas seguintes iam pro app frontmost, sem
sinal nenhum, por até 5 s — e depois o `.onAppear` roubava o foco de volta no
meio da palavra. Agora `typingNote` vence as duas no `mode`. **Esconder pelo
`mode` não bastava**: o auto-dismiss de 5 s correria invisível e a notificação
morreria sem ninguém ver, então ela também passou a ser enfileirada, com
`resumePendingNotifications()` no fim da digitação.

**P1 — desligar apagava sem volta**, por três caminhos (menu, monitor dono
desconectado, quit). O `didSet` de `active` copia pro `NSPasteboard` antes de
zerar; nota vazia ou só com espaço não encosta no clipboard.
`applicationWillTerminate` desliga a nota pra cobrir o quit.

**P1 — os pontinhos de página mentiam.** Ficavam visíveis e clicáveis com a
nota aberta, mudando `vm.tab` por baixo do campo: o ponto de Mensagens acendia
numa tela que seguia mostrando a nota. Saíram, e o eixo horizontal do gesto
ficou de fora na tela dona (card fechado ainda pula faixa).

**P2 — nem o campo vazio nem a nota cheia se anunciavam.** Placeholder no campo
e ponto de 4 pt na asa do notch fechado.

## Validação

`tools/check.sh` **16 ok** (o `quicknotecheck` é novo — cobre copiar-antes-de-
apagar, os dois casos de nota vazia, `hosted(by:)` e `typing(on:)`; validado por
mutação: tirando a chamada do stash, o gate quebra na asserção certa).
`tools/snapshot.sh` **62 PNGs**, exit 0 — o cenário `closed-note` é novo.

**O screenshot manual achou dois bugs que o harness nunca pegaria** (o campo é
um `ScrollView`): uma barra de rolagem do sistema parada dentro do card mesmo
vazio, e o placeholder 8 pt abaixo de onde a primeira letra nasce — pularia na
primeira tecla. Os dois só apareceram no app rodando de verdade.

## Pendências e followups

- **Branch não mergeada e não decidida.** `fix/nota-rapida-ux` está local e
  pushada; falta merge em `master` ou PR.
- **Brief do caminho de entrada rápido aguarda OK.** `/impeccable shape`
  produziu o brief completo (atalho global configurável + puxão longo pra cima +
  alcinha no topo, os três confirmados pelo usuário). **A única questão aberta é
  o blink**: com o card aberto, chegar a −120 passa antes por −24, que fecha.
  Recomendação registrada: gesto pra cima só liga a nota a partir do card
  **fechado**, onde −24 é no-op. Nada disso foi implementado.
- **Restos da crítica não atacados**: puxão longo pra baixo com a nota ligada é
  gesto morto (não abre a cortina, correto, mas não dá feedback nenhum);
  `noteEditorHeight` fixo em 120 sem indicação de que há texto acima; sem
  limite de tamanho no colar.
- **Mensagem recebida (`.message`) ainda interrompe a digitação** — ficou fora
  do escopo do P0 de propósito (tem campo de teclado próprio), mas segue sendo
  vetor de tecla no app errado.

---

# 🏁 SESSÃO 2026-07-29 (manhã) — histórico de notificações + nota rápida, **v0.13.0 publicada**

Duas features do `IDEIAS.md` entregues juntas porque dividem o mesmo pedaço de
tela: o card expandido do notch. Ciclo completo — brainstorm, spec, plano, nove
tasks em TDD com subagentes, review de branch inteira, release.

## O que foi feito

**Histórico das últimas 24 h** (`docs/notifications.md`). Tudo que virou card
entra num `NotificationHistory` singleton em memória: banner do sistema, card de
webhook, lembrete disparado, fim de fase do Pomodoro e conta-gotas. Abre com um
**puxão longo pra baixo numa passada só** — ~24 pt abre o card, ~120 pt no mesmo
gesto entra na cortina. Fechar é tirar o mouse, **não** é gesto: assim o eixo
vertical fica livre pra lista rolar de verdade, inércia inclusive.

**Nota rápida** (`docs/nota-rapida.md`). Interruptor no menu da barra liga um
`TextEditor` que toma o card. Enquanto o campo tem foco, o hover-out não recolhe
— digitar nunca é interrompido. Esc solta o foco (explicitamente, via
`onExitCommand`; o padrão do SwiftUI não garante isso). Desligar apaga.

## As três decisões que valem lembrar

| Decisão | Por quê |
|---|---|
| Gesto vertical virou **função pura do acumulado** | Menos código que o `scrollActed` que existia, e recuar dentro do mesmo gesto passou a desfazer de graça |
| Nada em disco, nas duas | Notificação e nota são efêmeras por natureza. **A justificativa antiga era falsa**: `NotchNotification` não carrega `NSImage` nem `AXUIElement` (o `AXUIElement` mora no interceptor, indexado por `actionToken`) |
| A nota tem **uma tela dona** (`hostDisplayID`) | Sem dono, ligar expandia todos os monitores sem nada recolhê-los, e as N cópias da `NotchView` disputavam foco escrevendo no mesmo `editing` |

## O que só a review de branch inteira pegou

Nenhuma review por task podia ver, e é o padrão que vale carregar pra próxima
vez: **cada task estava certa isolada; o defeito morava na costura.**

- **`currentSize` nunca aprendeu sobre os dois estados novos.** A cortina
  desenhava ~325 pt num quadro de ~176 pt e o SwiftUI centraliza o excedente:
  as notificações **mais recentes** ficavam acima da borda da tela e o cursor
  descendo na lista caía fora do hover, fechando o card. O
  `expanded-history-empty.png` já mostrava isso e ninguém tinha lido o PNG.
- **Lembrete e Pomodoro construíam a `NotchNotification` dentro do `forEach`
  das telas** — `id` é `let id = UUID()`, então cada monitor gerava uma linha
  no histórico. Os outros quatro call sites já construíam fora do laço.
- **Rodinha de mouse comum nunca emite `.began`**, então o acumulador nunca
  zerava: cruzava 120 sozinho e a cortina virava um beco sem saída.

Três defeitos foram **do plano**, não de quem implementou: a guarda de diagonal
(`|Δy| > |Δx| × 1,5`) que sumiu na reescrita, a inércia engolida antes de chegar
na lista, e a justificativa falsa acima.

## Validação

- `./tools/check.sh`: **15 checks** (`historycheck` novo — store, gesto, teto de
  300, `isGestureStart`). Os asserts do gesto foram conferidos com **controle
  negativo**: removendo a guarda, o assert falha.
- Release: build Release + `satisfies its Designated Requirement`, v0.13.0 no
  GitHub Releases e no cask.

## Pendências e followups

- **Nada foi exercitado num trackpad de verdade.** Todo o comportamento de gesto
  e foco é verificado só por leitura de código. O roteiro de 15 itens saiu na
  conversa da sessão; os checklists por task ficaram em `.superpowers/sdd/` (que
  é gitignored — se sumir, o roteiro se perde).
- **Dois screenshots faltando**: `docs/nota-rapida.md` e a seção do histórico
  estão com `<!-- TODO screenshot -->`. Precisam do app rodando.
- **`ScrollView` não renderiza offscreen** — descoberto aqui, já no `CLAUDE.md`.
  Por isso o cenário de histórico populado saiu do harness (PNG preto é gate
  falso, pior que gate nenhum).
- **Quatro PNGs do snapshot não são determinísticos** (`closed-music`,
  `closed-music-external`, `expanded-activity-only`, `update-installing`): mudam
  de hash a cada rodada sem mudança de código. Neles o harness não detecta
  regressão. Está no `CLAUDE.md` e no README.

---

# 🏁 SESSÃO 2026-07-29 (madrugada, 4ª) — pendências fechadas + **v0.12.0 publicada**

Sessão de pendência, não de feature nova: das cinco abertas no topo do handoff
anterior, **três fecharam** — duas com código, uma só com teste. As duas que
sobraram dependem de coisa que não está nesta mesa.

## O que foi feito

**1. O adiamento do lembrete sobrevive ao restart** (`aa65f8d`). O `ScheduleEngine`
ganhou um `snoozed: [UUID: Date]` espelhado no UserDefaults: `snooze()` grava,
`init` lê, e o primeiro `tick()` depois do restart semeia o `nextFire` a partir
dele. Vencido (ou lembrete apagado), o adiamento some sozinho — continua valendo
uma vez só.

O hash do schedule **não** é persistido junto de propósito: `hashValue` é
randomizado por processo e não sobreviveria ao restart de qualquer jeito. O
preço é editar o horário com um adiamento no ar mantendo o adiamento; está
comentado no código.

**2. Tabela, imagem embutida e regra horizontal no Markdown → PDF** (`151c5c7`).
As três lacunas que o conversor carregava desde que nasceu.

| Peça | Como |
|---|---|
| Paginação | saiu do **CoreText** e foi pro **TextKit** — um `NSTextContainer` por página |
| Tabela | célula da mesma linha vira `\t`, um tab stop por coluna, alinhamento `:---`/`---:` respeitado |
| Imagem | `run.imageURL` resolvido contra a pasta do `.md` → `NSTextAttachment` reduzido pra caber |
| Régua | o "⸻" do parser repetido até a caixa, com `kern` negativo |

A troca de motor foi o nó: era o `CTFramesetter` que ignorava anexo e tab stop.
`NSLayoutManager` dá os dois de graça e custa menos código que a alternativa
(`CTRunDelegate` reservando espaço + desenho manual).

## As duas descobertas que só o olho pegou

Ambas saíram de rasterizar o PDF e **olhar**, não de teste passando.

- **A citação saía invisível.** O cinza vinha de `.secondaryLabelColor` — cor
  dinâmica, que resolve pela aparência do sistema e no modo escuro vira branco.
  Em papel branco, nada. Bug que já existia desde a 0.11.0 e nenhum assert
  pegaria. Agora é tinta fixa (`quoteGray`), com assert de brilho no self-check.
  Foi ele também que escondeu a régua na primeira tentativa e me fez trocar o
  traço por um tab sublinhado antes de achar a causa real.
- **O parser omite célula vazia.** `| Total | | 50,50 |` não gera run pra célula
  do meio, então um tab por run puxava o valor pra coluna errada. O contador de
  coluna virou explícito (`tableCell(intent)`).

**3. `Compartilhar…` (menu nativo)** — fechada sem código: exercitada ao vivo,
o menu abre e envia. O plano B (`NSSharingService.sharingServices(forItems:)`)
não foi preciso.

## Validação

- `./tools/check.sh`: **14 checks**. `reminderscheck` ganhou o caso do restart
  (engine A adia, engine B com `nextFire` zerado dispara na hora certa, engine C
  confirma que o adiamento vencido não ressuscita); `documentconvertercheck`
  ganhou três (tabela + régua + brilho da tinta; imagem com anexo medido e
  caminho quebrado caindo no alt).
- **PDF real rasterizado e conferido a olho** — foi o que achou os dois bugs
  acima. Vale repetir o hábito: `DocumentConverter.pngPages(fromPDF:)` num md de
  exemplo e ler o PNG.
- Release: build Release + `satisfies its Designated Requirement`, v0.12.0 no
  GitHub Releases e no cask.

## Pendências e followups

Sobraram as duas de bloqueio externo — nenhuma depende de código:

- **Aceitar/Recusar espelhado nunca foi exercitado** — precisa de um AirDrop
  vindo de **outro Apple ID**. Entre dispositivos do mesmo ID o macOS aceita
  sozinho e esse par de botões nem aparece.
- **Sem notarização**: `KNOBLER_NOTARY_PROFILE` espera uma conta Apple Developer
  paga. A 0.12.0 saiu com o cert local; o cask remove a quarentena no install e
  os caveats explicam.

Ideias que a sessão deixou registradas em `docs/IDEIAS.md`: preview da conversão
(hoje é às cegas, sem escolher qualidade/resolução).

---

# 🆕 SESSÃO 2026-07-29 (madrugada, 3ª) — adiar lembrete + **v0.11.0 publicada**

Sessão curta de uma feature só. O `[Unreleased]` que a sessão anterior deixou
acumulado **saiu**: `v0.11.0` está no GitHub Releases e no cask.

## O que foi feito

**Adiar lembrete direto no card do notch** (`1a29ef4`). Quando um lembrete
dispara, o card traz **Adiar 5 min** e **30 min**.

O diff é pequeno porque quase tudo já existia — a UI de botão no card
(`actionTitles` / `actionToken`) tinha sido escrita na sessão anterior pro
AirDrop e **só rodava em alerta de Apple ID alheio**. Agora roda todo dia.

| Peça | Onde |
|---|---|
| `snooze(_:minutes:now:)` — empurra o `nextFire` sem tocar na agenda | `Reminders.swift` (engine) |
| `onFire` manda `actionToken: r.id` + os dois títulos | `KnoblerApp.swift:336` |
| Roteamento por token: lembrete → snooze, resto → interceptor | `KnoblerApp.swift:749` |
| `snoozeOptions` (títulos + minutos, fonte única) | `KnoblerApp.swift:66` |

Duas decisões que valem lembrar:

- **O adiamento vence uma vez só.** Ao disparar, o tick recomputa a agenda
  normal — um diário adiado pras 09:05 volta pras 09:00 no dia seguinte.
- **Um `oneShot` precisa ser religado no snooze.** O `onFire` já o desligou
  quando o card apareceu, e o tick pula item desabilitado — sem religar, o
  adiamento nunca venceria. Custou uma linha, mas é invisível na leitura.

## A descoberta que matou a feature que eu ia fazer

A recomendação inicial era **notificações de app com ações** (Responder,
Marcar como lida) — parecia barata, já que a infra de botão existe. Não é.

Acionar a ação exige o `AXUIElement` do banner **vivo**, e o interceptor fecha
o banner justamente pra o notch substituí-lo. Ou o balão do sistema fica na
tela duplicado com o card, ou não há ação — não existe meio-termo via AX.
Anotado com ⚠️ em `docs/IDEIAS.md` pra não custar essa descoberta de novo.

Trocamos pelo snooze, que é a mesma UI sem nenhum AX no caminho.

## Validação

- `./tools/check.sh`: **14 checks** (eram 13). O `reminderscheck` entrou —
  o `-D REMINDERS_SELFCHECK` existia desde sempre no `Reminders.swift` mas
  **nunca rodava no CI**. O novo assert cobre adiar → não dispara antes →
  dispara na hora → não redispara → agenda diária intacta no dia seguinte.
- **Ao vivo, ciclo completo** (lembrete de teste via `defaults write`, removido
  depois): card com os dois botões às 00:14 · clique roteou pro snooze
  (o `enabled` do `oneShot` voltou a `true` no plist, coisa que **só** o snooze
  faz) às 00:16 · card reapareceu às **00:21**, exatos 5 min depois.
- Release: build Release + `satisfies its Designated Requirement` (cert local
  `Knobler Local Signing`, então o TCC não revoga a Acessibilidade).

## Pendências e followups

Novas desta sessão:

- **O adiamento mora na memória.** Reiniciar o Knobler antes de vencer devolve
  o lembrete ao horário original. Registrado no IDEIAS; persistir junto do
  `Reminder` resolveria. ✅ **Fechada na sessão de 29/07 (madrugada, 4ª).**

Herdadas e ainda abertas:

- ~~**`Compartilhar…` (menu nativo) não teve confirmação visual**~~ — exercitado
  ao vivo em 29/07: o menu abre e envia. Fechada sem código.
- **Aceitar/Recusar espelhado nunca foi exercitado** — precisa de um AirDrop de
  Apple ID diferente.
- ~~**Markdown → PDF ignora tabela, imagem embutida e regra horizontal.**~~ ✅
  **Fechada na sessão de 29/07 (madrugada, 4ª).**
- **Sem notarização**: `KNOBLER_NOTARY_PROFILE` não estava setado, então a
  0.11.0 saiu com o cert local. Quem instalar fora do cask vê o Gatekeeper.

---
