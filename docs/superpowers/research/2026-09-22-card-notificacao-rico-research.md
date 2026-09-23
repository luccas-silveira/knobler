# Pesquisa — card de notificação rico

Spec: `docs/superpowers/specs/2026-09-22-card-notificacao-rico-design.md`

Nenhum dump ao vivo do banner foi obtido nesta máquina (macOS 27.0, 26A428):
`osascript`/`terminal-notifier` não geram banner porque só o WhatsApp tem
notificação ligada. A estrutura do banner abaixo vem de código de terceiros
atualizado pro Tahoe, não de medição própria.

## Achados

### A1 — O WhatsApp fixo é proposital, e as premissas dele já falharam
- Fonte: `Knobler/NotificationInterceptor.swift:202-207` ("o Tahoe não expõe o
  app de origem… o WhatsApp é o único app com notificação ligada neste Mac");
  `~/Library/Application Support/Knobler/notificationHistory.json`: um aviso do
  sistema ("Acesso aos dados bloqueado", sobre o Instagram) gravado como WhatsApp.
- Contradiz a spec: parcial — a spec trata como bug sem saber que foi escolha.
- Pergunta: quem instala pelo Homebrew vê todo banner como WhatsApp. Trocar o
  fixo por "app lido do banner, ou sino quando não der" é aceitável mesmo se
  nesta máquina o card do WhatsApp às vezes cair no sino?

### A2 — O app de origem está no `AXDescription` do banner, não nos textos
- Fonte: https://github.com/chessper53/NotificationNanny (`extractBannerContent`,
  `AppNameResolver.swift`); https://github.com/roycetech/applescript-core/blob/master/macOS-version/26-tahoe/notification-center.applescript
  (`_appNameFromAttributedDescription`); dump do AirDrop no repo,
  `docs/handoffs/2026-07.md:780`: `AXDescription="AirDrop, Recebendo uma foto"`.
- Formato `"<app>, <título>, <corpo>"`, vírgulas do conteúdo sem escape. O nome
  do app é o trecho antes da primeira `", "`.
- Contradiz a spec: parcial — a spec deixou a fonte em aberto; o comentário do
  código (A1) diz que não existe fonte.
- Pergunta: aposto no `AXDescription` sem ter visto um banner real desta
  máquina. Vale pedir um dump ao vivo (você manda uma mensagem de WhatsApp pra
  si mesmo com o Knobler fechado) antes de implementar?

### A3 — Os textos do banner vêm rotulados; o parse por posição está errado
- Fonte: roycetech (Sequoia e Tahoe) e https://github.com/lahfir/agent-desktop
  (`crates/macos/src/notifications/scan.rs`): cada `AXStaticText` tem
  `AXIdentifier` `title`, `subtitle`, `body`, `date`; o nome do app não é texto.
  `NotificationInterceptor.swift:235-249` assume `[app, título, corpo…]`.
- Evidência local: nas 75 notificações do histórico nenhuma tem corpo juntado
  com " — ", e o título é sempre o remetente — consistente com banner de 2 textos
  (título, corpo) no caminho `case 2`.
- Contradiz a spec: sim — a spec deriva subtítulo da posição ("o terceiro de
  quatro"). Com `AXIdentifier` o subtítulo sai rotulado.
- Pergunta: ler por rótulo, e cair na posição só quando o rótulo faltar?

### A4 — Imagem/anexo não é alcançável sem Gravação de Tela
- Fonte: nenhum projeto pesquisado acha `AXImage` útil no banner; todos
  reconstroem o ícone pelo nome do app. `CGWindowListCreateImage` obsoleto no SDK
  do macOS 15 (https://trac.macports.org/ticket/71136); ScreenCaptureKit exige
  Gravação de Tela.
- Contradiz a spec: não — é o ramo condicional que a spec previu.
- Pergunta: imagem sai deste sub-projeto e fica como decisão futura?

### A5 — O card já sabe achar ícone e clique pelo nome do app
- Fonte: `NotchView.appPath(bundleID:named:)` (`NotchView.swift:1418-1427`),
  `runningApp(named:)` (`:1409-1414`), `openSourceApp` (`:1377-1383`).
- Com `bundleID: nil` e o nome certo em `appName`, ícone e clique já funcionam
  pra app rodando. Um resolvedor novo em `NotificationRules` seria duplicata.
- Ressalva: o fallback `/Applications/<nome>.app` mostra ícone de app que não
  está rodando, mas o clique não faz nada (só `runningApp`). Não cobre
  `~/Applications` (web apps do Safari e PWAs do Chrome).
- Nome vem com U+200E do WhatsApp (o próprio histórico grava `"‎WhatsApp"`);
  comparar exige limpar caracteres invisíveis.
- Contradiz a spec: sim — a spec cria "nome + lista de apps → bundleID" puro.
- Pergunta: reusar a resolução que o card já faz, e só corrigir o clique pra
  abrir app instalado mas fechado?

### A6 — Ícone no histórico não precisa de truque no harness
- Fonte: `Snapshots/notification.png` mostra o ícone real do Finder;
  `tools/main.swift:409-415`. O que falha offscreen é o `NSView` de
  `ShelfThumbnailDragView.swift:92`, não `NSWorkspace.icon`. Diagnóstico errado
  registrado em `docs/notifications.md:107-110` e
  `.claude/skills/snapshot-ui/SKILL.md:39-42`.
- O que bloqueia snapshot do histórico cheio é o `ScrollView` (sai preto).
- Contradiz a spec: sim — a spec propõe ícone substituto no harness.
- Pergunta: snapshot só da linha isolada, fora da lista, basta como gate?

### A7 — Não existe estado de hover publicado pro card expandir
- Fonte: `NotchView.swift:239-247` (hover em modo notificação só chama
  `holdNotification`); `NotchViewModel.swift:622-629` (só mexe no timer);
  modelo a copiar: `airpodsHeld` (`NotchViewModel.swift:222`).
- Altura do card fixa em dois lugares que precisam concordar:
  `NotchPresentation.swift:152-153` e `NotchView.swift:174-178`; coberto por
  `tools/presentationcheck.swift`.
- Contradiz a spec: parcial — a spec supõe o estado pronto.
- Pergunta: nenhuma de produto; vira item do plano.

### A8 — Hora relativa: nada reutilizável no repo, a plataforma resolve
- Fonte: `CalendarAviso.quando` (`CalendarAviso.swift:9-17`) conta pra frente e
  arredonda pra cima. `RelativeDateTimeFormatter` não é usado; o histórico mostra
  "HH:mm" (`HistoryListView.swift:23-27`).
- Contradiz a spec: não.
- Pergunta: nenhuma; a regra "agora até 1 min" fica numa função pura.

### A9 — `NotificationRules` já tem self-check
- Fonte: `tools/sharingcheck.swift:117-131` (`isAirDrop`, `isActionTitle`),
  `tools/check.sh:91`; decode do histórico em `tools/historycheck.swift`
  (`check.sh:101`).
- Contradiz a spec: parcial — a spec pede check novo; estender os dois basta.
- Pergunta: nenhuma de produto.

### A10 — Registro, fora do escopo: estrutura do banner mudou no 26.6+
- Fonte: https://github.com/chessper53/NotificationNanny/pull/23 — banner vira
  view dentro de um `AXSystemDialog` permanente; `kAXWindowCreatedNotification`
  para de disparar; subroles `…Stack` pra grupos não tratados pelo Knobler.
- Pertence ao sub-projeto de confiabilidade. O polling de segurança do
  interceptor provavelmente mascara.

### A11 — Registro: banco de notificações exige Acesso Total ao Disco
- Fonte: https://9to5mac.com/2024/09/01/security-bite-apple-addresses-privacy-concerns-around-notification-center-database-in-macos-sequoia/;
  `sqlite3` nesta máquina: "authorization denied".
- Confirma a spec (caminho recusado).

## Fila do grill

1. A2 — dump ao vivo antes de implementar, ou apostar no `AXDescription`? (trava A1, A3, A5)
2. A1 — trocar o WhatsApp fixo por "lido ou sino", aceitando sino ocasional nesta máquina?
3. A3 — ler textos por rótulo, posição só como reserva?
4. A5 — reusar a resolução do card e corrigir o clique pra app fechado, sem resolvedor novo?
5. A4 — imagem sai do sub-projeto?
6. A6 — snapshot da linha isolada como gate do ícone no histórico?
