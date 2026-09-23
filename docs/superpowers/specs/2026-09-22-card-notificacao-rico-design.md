# Card de notificação rico — design

Sub-projeto 1 de 4 da melhoria de notificações. Os outros três (ruído/controle,
confiabilidade, ações) têm ciclo próprio e ficam fora daqui.

## Problema

O card de uma notificação de app é mais pobre que o banner nativo que ele
substitui, e em um ponto está errado:

1. **Todo banner interceptado sai como WhatsApp.** `NotificationInterceptor.process`
   descarta o nome do app lido do banner e carimba `defaultBundleID =
   "net.whatsapp.WhatsApp"` (`NotificationInterceptor.swift:207`). Ícone, nome,
   clique do card e linha do histórico apontam pro WhatsApp, venha a notificação
   de onde vier.
2. Texto truncado: título em 1 linha, corpo em 2, sem jeito de ler o resto.
3. Subtítulo (ex.: nome do grupo) vai colado no corpo com " — ".
4. Sem hora no card.
5. Linha do histórico sem ícone.
6. Sem imagem/anexo (avatar do remetente, miniatura).

## Objetivo

O card identifica o app de origem corretamente, mostra o texto inteiro quando
você pede, separa subtítulo e mostra há quanto tempo chegou; o histórico ganha
ícone. Sem permissão nova.

## Fora do escopo

- Qualquer permissão além da Acessibilidade (Acesso Total ao Disco, Gravação de
  Tela).
- Regras por app, agrupamento, ações, mudanças na captura/fechamento do banner.
- Cards de webhook, lembrete, Pomodoro, avisos: já têm ícone próprio e não mudam.

## Desenho

### Identidade do app

O `defaultBundleID` do WhatsApp sai, junto com o comentário que o justificava
(`NotificationInterceptor.swift:202-207`). O nome do app vem do `AXDescription`
do banner — formato `"<app>, <título>, <corpo>"`, o nome é o trecho antes da
primeira `", "` — limpo de caracteres invisíveis (o WhatsApp manda U+200E).

O interceptor passa `appName` com esse nome e `bundleID: nil`. Ícone e clique
saem da resolução por nome que o card já faz (`NotchView.appPath`,
`runningApp(named:)`); não há resolvedor novo. Duas correções nela:

- O clique abre também app instalado e fechado, não só rodando (hoje o ícone
  aparece e o clique não faz nada).
- A busca por nome olha `~/Applications` além de `/Applications` (web apps do
  Safari e PWAs do Chrome moram lá).

Sem nome legível: `appName = nil`, card com sino, clique não abre nada. Errar pra
um app específico é pior que não saber.

**Gate antes do código:** um dump ao vivo de um banner real (WhatsApp) confirma o
formato do `AXDescription` e os rótulos dos textos. Se não bater, o plano para e
volta ao usuário.

Confirmado em 2026-09-23 (macOS 27.0): o banner expõe a descrição só como
`AXAttributedDescription` (`"\u{200E}WhatsApp, Ana, Grupo, Teste"`),
não como `AXDescription`; os textos vêm com `AXIdentifier` `title`, `subtitle`,
`body`.

### Título, subtítulo, corpo

Os textos do banner são lidos pelo rótulo que o macOS dá a cada um
(`AXIdentifier` `title`, `subtitle`, `body`, `date`). Só quando faltar rótulo o
parse cai na posição: 1 texto = título; 2 = título e corpo; 3+ = título,
subtítulo, resto como corpo. O texto de hora (`date`) é descartado. A regra
"textos rotulados/posicionais → (título, subtítulo, corpo)" e a extração do nome
do `AXDescription` são funções puras em `NotificationRules`.

`NotchNotification` ganha `subtitle: String? = nil` logo após `body`,
`Codable` com `decodeIfPresent`/`encodeIfPresent` (histórico antigo continua
carregando). A chave de dedupe do interceptor passa a incluir o subtítulo.

### Hora

Canto superior direito do card: "agora" até 1 min, depois "há N min", "há N h".
Vem de `NotchNotification.date`. Função pura em `NotificationRules` (o
`CalendarAviso.quando` conta pra frente e não serve).

### Texto completo no hover

O card chega como hoje (título 1 linha, corpo 2). Com o mouse em cima — o mesmo
momento em que `NotchViewModel.holdNotification` pausa o auto-dismiss — título,
subtítulo e corpo abrem sem limite de linha.

Hoje esse hover não é publicado: `holdNotification` só mexe no timer. Ele passa a
publicar `notificationHeld` (no molde do `airpodsHeld`), zerado no dismiss. A
altura do card está fixa em dois lugares que precisam concordar
(`NotchPresentation.swift:152-153` e `NotchView.swift:174-178`); os dois passam a
ler a altura do `Layout`, que ganha o estado expandido. Teto de altura pra texto
gigante, com o resto cortado.

### Imagem/anexo

Fora deste sub-projeto. O banner não expõe a imagem pela Acessibilidade, e o único
caminho é Gravação de Tela. Fica como decisão futura.

### Ícone no histórico

`HistoryListView` ganha o mesmo ícone do card: `RemoteAvatarView` e `appPath`
deixam de ser `private` e a linha os usa num frame menor. O motivo antigo de não
ter ícone estava errado — o ícone de app renderiza offscreen (o
`notification.png` mostra o do Finder); quem sai com "proibido" é o `NSView` do
`ShelfThumbnailDragView`. Corrigir o diagnóstico em `docs/notifications.md` e na
skill `snapshot-ui`.

## Testes

- `tools/sharingcheck.swift` (já testa `NotificationRules`): parse rotulado e
  posicional com 1, 2, 3+ textos; nome do app a partir do `AXDescription`
  (normal, vazio, com U+200E, com vírgula no título); hora relativa nos limites
  (59 s, 60 s, 59 min, 60 min).
- `tools/historycheck.swift`: decode de histórico sem `subtitle`; ida e volta
  com `subtitle`.
- `tools/presentationcheck.swift`: altura do card expandido.
- Snapshots: card com subtítulo e hora, card expandido, card sem app (sino), e a
  linha de histórico com ícone renderizada isolada — a lista inteira sai preta
  offscreen por causa do `ScrollView`.
- Ao vivo: banner real do WhatsApp (único app que notifica nesta máquina;
  `osascript` não gera banner aqui) conferindo ícone, nome, clique e hover.

## Critério de sucesso

Uma notificação do WhatsApp aparece com ícone e nome do WhatsApp porque foram
lidos do banner, não fixados; uma de outro app (ou do sistema) aparece com o
nome dele ou com sino, nunca como WhatsApp.
Corpo longo é legível inteiro com o mouse em cima. O histórico mostra ícone.

## Decisões do grill

Usuário aceitou todas as recomendações ("faz todo o recomendado").

- **A2** — nome do app vem do `AXDescription`, mas com gate: dump ao vivo de um
  banner real antes do código. Tentado na pesquisa e no grill; nenhum banner
  chegou (só o WhatsApp notifica nesta máquina), então o dump vira a tarefa 1 do
  plano.
- **A1** — WhatsApp fixo sai; sem nome legível, sino. Motivo: a premissa "só o
  WhatsApp notifica" já falhou nesta máquina (aviso do sistema sobre o Instagram
  gravado como WhatsApp) e nunca valeu pra quem instala pelo Homebrew.
- **A3** — textos lidos por rótulo, posição só como reserva. Motivo: o parse
  atual assume o app no primeiro texto, e as fontes do Tahoe dizem que o primeiro
  é o título.
- **A5** — sem resolvedor novo; reusa `appPath`/`runningApp` do card, com clique
  pra app fechado e busca em `~/Applications`. Motivo: o card já resolve por
  nome; um resolvedor puro seria duplicata.
- **A4** — imagem/anexo fora. Motivo: sem caminho sem Gravação de Tela.
- **A6** — sem ícone substituto no harness; snapshot da linha isolada. Motivo: o
  ícone renderiza offscreen; o bloqueio é o `ScrollView`.
- **A7** — hover publicado (`notificationHeld`) e altura unificada no `Layout`.
  Motivo: o estado não existia e a altura estava duplicada.
- **A9** — sem check novo; estende `sharingcheck` e `historycheck`.
- **A10** — mudança de estrutura do banner no 26.6+ fica pro sub-projeto de
  confiabilidade.
