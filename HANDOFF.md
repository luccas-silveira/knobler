# 🏁 SESSÃO 2026-08-03 (noite, 2ª) — avisos do desenvolvedor → v0.20.0

Feature nova de ponta a ponta, mais uma limpeza de backlog. Fecha o item "canal
de notificações do desenvolvedor" do `IDEIAS.md`.

## Limpeza de backlog antes

**Apple Notes sync** e **Integração com Claude API** foram descartadas pelo dono
do projeto. As duas eram destino novo de ditado, e ficou gravada a regra que as
mata: **o ditado só escreve no campo de texto que a pessoa tem selecionado** —
nunca num app terceiro, num arquivo ou numa API. Qualquer pitch futuro que crie
um `case` novo em `DictationDestination` bate nisso primeiro. **WhatsApp Web**
ficou marcado no `ROADMAP.md`: como estava descrito lá ("mais um destino de
ditado") cai na mesma regra; só sobrevive como envio a partir do notch.

## O que foi feito

`Knobler/DevAvisos.swift`: o app baixa um `avisos.json` público do repo no
launch (+45 s) e a cada 24 h, e cada aviso vira card no notch. Publicar = editar
o JSON e commitar no `master`. Sem servidor, sem deploy.

**Não foi pelo relay, como o ROADMAP previa.** `webhookNotifications` é opt-in e
nasce desligado (`AppSettings.swift`), então um broadcast pelo relay só
alcançaria quem já pareou — provavelmente a minoria. Polling alcança 100% da
base sem infra nova.

**Timer próprio, não carona no `Updater.check()`:** lá existe um
`guard force || automatic`, e quem desligasse "verificar atualizações" perderia
junto os avisos críticos.

O card entra por `AppDelegate.publicar` — o mesmo funil de tudo que vem de fora —
e por isso respeita "silenciar durante reuniões" **inclusive o crítico**
(silenciar não descarta: fica no Histórico). Toggle em Ajustes › Geral, opt-out;
desligado silencia os normais e os críticos passam, e o rótulo diz isso.

Guardas de fronteira, já que é JSON remoto virando UI clicável: tetos de 64 KB /
10 avisos / 80 / 400 chars / 2 ações, ações **só em https**, `versaoSchema`
desconhecido descarta o arquivo inteiro. Faixa de versão malformada **falha
fechada** — `isNewer` devolve false pra lixo, então um typo em `minVersao`
viraria aviso pra toda a base; por isso `versionComponents` deixou de ser
`private` no `Updater`.

`actionURLs` novo no `NotchNotification`: o `actionToken` normal resolve num
`AXUIElement` vivo do interceptor, e um aviso vindo de JSON não tem banner atrás.
Não persiste, pela carona do `actionTitles`.

**Corte deliberado:** o "read/dismiss" do pitch original colapsou em um. O aviso
aparece uma vez e o id fica em `avisos.vistos` (últimos 100). Estado "não lido"
separado pediria badge e contador no histórico — não se paga num canal que emite
uma vez por mês.

## Validação

- `./tools/check.sh` → **25 checks ok** (novo: `avisoscheck`).
- **Teste de mutação**: removi o `critico ||` do filtro e o gate falhou. O check
  pega a regressão, não é decoração.
- **Integração real** contra `python3 -m http.server`: toggle off silenciando o
  normal e deixando o crítico passar, `minVersao: "1.0.0"` filtrando, ação
  `file:///etc/passwd` descartada com só a `https` sobrevivendo, segunda rodada
  sem repetir nada.
- **Ao vivo, na tela**: o card renderizou com emoji, título, corpo e o botão
  "Ver release"; `avisos.vistos` gravou o id e o ciclo seguinte não repetiu.
- Builds Debug e Release ok.

## Pendências e followups

- ⚠️ **O clique no botão do aviso não foi provado ao vivo.** Automatizar o
  clique falhou (a janela de 45 s entre launch e disparo torna o alvo instável —
  o clique caiu na toolbar do app de trás). O caminho reusa o
  `onNotificationAction` que os lembretes já usam; o que é novo é o lookup em
  `avisoActionURLs`. Se o primeiro aviso real tiver botão morto, é ali.
- `avisos.json` está **vazio** (`{"versaoSchema":1,"avisos":[]}`). Nenhum aviso
  publicado ainda.
- ⚠️ Publicar aviso é **irreversível**: o app que já baixou não reconsulta por
  24 h e o `raw` do GitHub ainda cacheia. Apagar a linha não desfaz — corrigir é
  publicar outro `id`. Reciclar `id` é pior: quem viu o antigo não recebe o novo.
- O `/Applications/Knobler.app` da máquina do dono continua sendo a build local
  de uma branch anterior. `brew upgrade --cask knobler` alinha com a 0.20.0.
- `graphify-out/` segue o de 28/jul: um arquivo novo não paga os ~640k tokens.

## Release

**v0.20.0 publicada** (`tools/release.sh minor`): tag `v0.20.0`, release no
GitHub, `Knobler-0.20.0.zip` (sha256 `d4a9b4e0…`), cask bumpado no tap. A branch
`feat/avisos-desenvolvedor` foi merjada em `master` com `--no-ff`. Espelhado em
`zoi-tech/knobler` (remote `zoi`, não `zoi-tech`).

## Documentação

`docs/avisos.md` novo (uso + seção de publicação pra mantenedores, com a receita
de teste local). Atualizados: `README.md` (feature + linha na tabela "o que sai
da sua máquina"), `docs/index.md`, `docs/settings.md`, `docs/architecture.md`
(diagrama + ownership), `docs/notifications.md` (o aviso no silêncio de reunião),
`docs/troubleshooting.md` (seção "nunca recebi um aviso"), `docs/development.md`
(a lista de gates virou ponteiro pro `check.sh` em vez de cópia que envelhece),
`CHANGELOG.md`, `docs/IDEIAS.md` e `docs/ROADMAP.md`.

# 🏁 SESSÃO 2026-08-03 (noite) — janela de boas-vindas → v0.19.0

Execução do plano escrito na sessão anterior
(`docs/superpowers/plans/2026-08-03-boas-vindas.md`), na branch
`feat/boas-vindas`. Fecha dois itens do `IDEIAS.md` de uma vez: "Wizard de
primeira execução" e "Dicas de hotkeys".

## O que foi feito

Uma `NSWindow` própria na primeira abertura, com dois passos informativos: onde
o app vive (o notch responde ao mouse, não há Dock nem janela, o acesso é a
barra de menus, e Mensagens te anuncia na rede local) e os dois atalhos globais
(⌥ direita = ditado, Control direito = anotação). Ela **não escreve** em
`AppSettings` — o "minimal setup" do pedido original não existia: ditado e API
já nascem ligados, Mensagens não tem toggle, Spotify não tem login.

Cada passo carrega `criadoEm`/`revisadoEm`; `onboarding.versao` guarda o que a
instalação já viu. Passo novo numa versão futura aparece sozinho, marcado
"Novo"/"Atualizado"; **lista filtrada vazia = a janela não abre**. Quem já tinha
a chave velha `onboarding.permissoes.apresentado` migra pra versão 1 e vê só os
atalhos. Tudo isso vive em `Knobler/Onboarding.swift`, sem SwiftUI e sem
`AppSettings`, pra o `onboardingcheck` compilar isolado (mesma razão do
`CalendarAviso`).

`Permission.promptAccessibilityOnce()` **saiu** do
`applicationDidFinishLaunching` — quem pede Acessibilidade agora é o painel
Permissões, encadeado no fechamento da janela. Há um comentário no lugar da
linha removida, senão ela volta.

**Desvio consciente do plano:** o painel Permissões só é encadeado quando
`versaoVista == 0`. Quem só está vendo um passo novo já passou por aquele painel
e não devia levá-lo na cara de novo.

**Bug que só a captura achou:** o `NSHostingView` adota o fitting size do
conteúdo e o `setContentSize` não o segura — a janela nascia com **4666 pt** de
altura. A rootView leva `.frame(width: 800, height: 520)`.

## Validação

- `./tools/check.sh` → **24 checks ok** (novo: `onboardingcheck`, que cobre o
  filtro, a migração da chave legada e o esquecimento de subir `versaoAtual` —
  o erro que reabriria a janela em todo launch).
- Builds Debug e Release ok.
- **Ao vivo** (build Release rodando de `~/Applications`, defaults da máquina
  restaurados no fim): instalação zerada abre os dois passos e o painel
  Permissões vem depois; relançar não abre nada; base migrada
  (`onboarding.permissoes.apresentado = true`) vê **só** os atalhos com o selo
  "NOVO", e fechar não traz Permissões; menu → "Boas-vindas…" abre os dois
  passos; `--boas-vindas` fecha **sem** gravar versão.
- Rodar de `/tmp` mostrou o outro caminho funcionando: `installIssue =
  foraDeApplications` manda direto pro painel Permissões, sem passar pela
  janela.

## Achados do teste de instalação limpa

O dono zerou a máquina de verdade (domínio `com.zoi.knobler`, Application
Support e TCC) e subiu a build como instalação nova. Três defeitos vieram à
tona, todos **anteriores** ao wizard — ele só os deixou visíveis:

1. **Calendário pedia permissão no launch.** `CalendarCountdown.start()`
   chamava `requestFullAccessToEvents` sem condição: o balão do EventKit subia
   por cima da janela de boas-vindas, e contra a regra do app de pedir no
   primeiro uso. Agora só liga se o acesso já existe; se não, repolla a cada
   3 s e liga sozinho quando a concessão chega. Quem pede é o painel Permissões.
2. **Rede local nunca virava "concedida" num Mac sozinho.** A prova positiva era
   achar um peer. Qualquer resultado do browser serve — inclusive o próprio
   anúncio, e sem a permissão o Bonjour não devolve nada.
3. **"Ainda não usada" lia como defeito.** Virou "Sem status até usar", e Rede
   local e Arquivos e pastas ganharam um botão **Verificar** que força o
   primeiro uso na hora (liga o Bonjour, lê a Mesa). O áudio do sistema fica de
   fora: só um player tocando cria o tap.

Verificado ao vivo pelo dono: os três resolvidos, wizard sem balão por cima.

## Release

**v0.19.0 publicada** (`tools/release.sh minor`): tag `v0.19.0`, release no
GitHub, `Knobler-0.19.0.zip` (sha256 `97ec384d…`) e cask bumpado no tap. A
branch `feat/boas-vindas` foi merjada em `master` com `--no-ff` antes disso e
ficou mantida no local, a pedido do dono. O espelho `zoi-tech/knobler`, que
estava indisponível em julho, aceitou o push desta vez (`master` + `v0.19.0`).
O `graphify-out/` segue o de 28/jul: dois arquivos novos não pagam os ~640k
tokens de uma regeneração.

⚠️ O `/Applications/Knobler.app` da máquina do dono é a build local da branch
(assinatura `Knobler Local Signing`), **não** a do release. Um `brew upgrade
--cask knobler` alinha as duas.

## Documentação

Varredura completa depois do release: `README.md` (boas-vindas na lista de
features + quem pede Acessibilidade), `docs/architecture.md` (nenhuma permissão
é pedida no launch; o módulo `Onboarding` na tabela de ownership),
`docs/settings.md` (botão Verificar, "Sem status até usar", o painel vindo
depois do wizard), `docs/calendar-countdown.md` e `docs/messages.md` (quem pede
cada permissão agora), `docs/troubleshooting.md` (duas seções novas: permissão
concedida que continua "sem status", e countdown que não aparece),
`docs/onboarding.md` novo, `docs/index.md`, `docs/IDEIAS.md` e `CLAUDE.md` (a
receita de captura em @2x e a das PNGs do wizard). `settings-permissoes.png`
recapturado com os rótulos novos.

## O que ficou de fora

- **Cenário 6 do plano** acabou rodando de graça: o wipe da máquina levou o TCC
  junto, o dono reconcedeu Acessibilidade pelo painel e o app voltou a
  funcionar sem relaunch. Confirmado ao vivo.
- **Nenhuma pendência de código.** O que ficou aberto é operacional: a máquina
  do dono roda a build da branch, não a do release (`brew upgrade --cask
  knobler` resolve), e o backup pré-wipe segue no scratchpad da sessão
  (`backup-knobler/`: `prefs.plist` + `AppSupport/`), descartável quando ele
  quiser.

---

# 🏁 SESSÃO 2026-08-03 (noite, tarde) — calendário no Pomodoro

Dois itens soltos do roadmap escolhidos pelo dono: **calendário no pomodoro** e
**cache de imagens em disco**. O segundo morreu na exploração (ver abaixo).

## O que foi feito

O `CalendarCountdown` já lia o próximo evento, mas só publicava como *live
activity* — e a seção de atividade é justamente a que o Pomodoro suprime. Durante
o foco, quando saber "falta 8 min pra reunião" mais importa, a informação sumia.

Agora o card de foco ganha uma linha com o título do evento e quanto falta, e nos
últimos **5 minutos** a pílula fechada troca o timer pelo aviso. Sem toggle novo:
vale o mesmo `calendarCountdown` (Ajustes → Notch) e a mesma janela de 15 min.

`CalendarAviso` (novo) mora num arquivo sem dependência nenhuma **de propósito** —
é o que deixa o `calendariocheck` compilar a formatação isolada, sem arrastar
`AppSettings`/`NotificationRules`. A string "em N min" passou a ter uma fonte só:
o `NotchActivity.detail` também a consome.

`alturaDaSecao(.pomodoro)` vai de 128 para 150 com evento — no mesmo diff da
linha nova, senão o conteúdo sai da moldura em silêncio (modo de falha clássico
do `NotchView`).

**Correção que só o teste ao vivo achou**: com o Pomodoro ativo o mesmo evento
aparecia duas vezes (anel de atividade + card), e a seção de atividade — que se
atualiza a cada 30 s e carimba evento — subia ao topo sem parar, então o Pomodoro
**nunca** ficava na frente. `currentActivity` agora cala a atividade do calendário
enquanto o Pomodoro está na tela, e `pushActivity()` só recalcula nas bordas
idle↔ativo (`onState` chega a cada segundo; republicar a cada tique carimbaria
evento de seção pra sempre).

## Validação

- `./tools/check.sh` → **23 checks ok** (novo: `calendariocheck`).
- Builds Debug e Release ok; Release instalada em `/Applications` (`ditto`),
  assinatura `Knobler Local Signing` confirmada.
- `tools/snapshot.sh`: dois cenários novos, `foco-pomodoro-evento` e
  `pomodoro-evento`.
- **Ao vivo, com evento real no Calendário** (calendário local `Knobler QA`,
  apagado no fim): pílula trocando o timer aos 4/3/2/1 min, no foco e na pausa;
  timer intacto fora dos 5 min; linha no card aberto com a tipografia final;
  `GET /status` devolvendo `focus: "pomodoro"` — antes era sempre `"atividade"`.

## Receita: como abrir o card do Pomodoro por automação

Custou meia sessão, fica registrado. **Hover sintético não expande a pílula do
Pomodoro** e o gesto de puxar **não é sintetizável** (`handleScroll` usa
`addLocalMonitorForEvents`, que não vê `CGEvent` postado por fora). O que funciona:

1. cursor no notch (`CGWarpMouseCursorPosition` em passos pequenos, x = `midX` da
   tela — 864 aqui; errar o centro foi a causa de metade das tentativas falhas);
2. `screencapture -x ~/Desktop/qualquer.png` — a captura cai na prateleira e
   dispara `peekShelf()`, que abre o card; **mouse em cima segura aberto**;
3. `GET /status` pra confirmar (`mode: music`, `focus: pomodoro`), nunca o palpite.

Lembrar que a ordem das seções é **congelada na abertura** do card
(`NotchViewModel`): mudar o estado com o card já aberto não põe a seção nova na
faixa.

## Cache de imagens em disco — descartado

A premissa do roadmap estava errada. Existe **um** consumidor de imagem de rede:
o ícone de notificação de webhook (`RemoteAvatarLoader`, teto de 512 KB, `NSCache`
já pronto). A capa do Spotify **não** vem da rede (base64 pelo MediaRemote) e as
mídias das mensagens são locais. Registrado em `IDEIAS.md`.

## Pendências e followups

- **Suspeita não investigada**: no modo pílula do Pomodoro o hover não expande o
  card, embora `setHover` tenha caminho explícito pra isso ("com Pomodoro ativo
  abre o card direto"). Ou o comentário está desatualizado, ou há caso não
  coberto. Não toquei.
- A folga vazia embaixo do card do Pomodoro é anterior a esta sessão (altura fixa
  por seção); a linha nova não a criou.
- `Pomodoro.selfCheck()` continua órfão do `check.sh` (existe atrás de
  `#if POMODORO_SELFCHECK`, ninguém o roda).
- Sem release nesta sessão, por decisão do dono: `## [Unreleased]` do CHANGELOG
  acumula esta feature e a do card de pergunta.

---

# 🏁 SESSÃO 2026-08-03 (fim de noite) — card de pergunta para de truncar

Item solto do roadmap escolhido pelo dono: **UI das perguntas do Claude**.

## O que foi feito

`AgentRequestCard` cortava o resumo em 160 caracteres e duas linhas — e mantinha
o corte mesmo expandido (`lineLimit(4)` sobre um texto já truncado na string).
Só os detalhes ganhavam bloco rolável, e a altura do card em `NotchView` só
crescia quando havia `details`, então resumo comprido sem anexo não tinha como
aparecer inteiro de jeito nenhum.

Agora, expandido, resumo e detalhes dividem **um** bloco rolável (176 pt de
teto). O botão passa a aparecer também quando só o resumo é comprido
(`> 110` caracteres), com o rótulo "Ver tudo"; com detalhes anexos segue "Ver
detalhes". Fechado, nada mudou: duas linhas e o resumo com reticências.
`NotchView` soma 156 pt à altura quando o card está expandido e há o que
expandir.

## Validação

- `./tools/check.sh` → 22 checks ok.
- Build Debug e Release ok.
- `tools/snapshot.sh` regenerado; `agent-permission-expanded.png` lido: resumo
  inteiro dentro do bloco, botões no lugar.
- Instalado em `/Applications/Knobler.app` (Release, `ditto`), assinatura
  confirmada `Knobler Local Signing` — Acessibilidade preservada. `GET /status`
  responde com `tapEnabled: true`.

## Pendências e followups

- O bloco expandido tem altura fixa: conteúdo curto deixa folga vazia embaixo.
  Medir o texto de verdade só se incomodar.
- `agent-permission-expanded.png` continua sendo o único snapshot que cobre esse
  card; a variante "resumo longo sem detalhes" não tem cenário no harness.
- Roadmap: sobraram calendário no pomodoro, cache de imagens em disco, canal de
  notificações do dev e o resto dos itens soltos.

---

# 🏁 SESSÃO 2026-08-03 (noite) — sync entre Macs: feito e revertido

Trilha A do roadmap (canal pareado + sync) foi implementada inteira e **revertida
no mesmo dia**, a pedido do dono do projeto. Nada disso está no código.

## O que foi construído (e não existe mais)

Canal Bonjour próprio `_knobler-sync._tcp` sobre TLS 1.2 com PSK de 256 bits,
chave em base32 no Keychain, painel de pareamento nos Ajustes; merge
LWW-Element-Set com relógio híbrido e lápides; lembretes, Ajustes com allowlist
explícita e histórico de mensagens com mídia em duas fases. Gate `synccheck`
(23 checks) e um harness de fio (`synclive`) que provava, com Bonjour e TLS de
verdade, que os dois lados convergiam e que **PSK errada não passava do
handshake**.

## Por que caiu

Decisão de produto, não falha técnica. Nas palavras do dono: Mensagens LAN
abertas **não** são um problema a ser corrigido, pareamento por chave engessa um
app que se usa sem configurar nada, e o campo único de chave não serve pra quem
quer falar com mais gente. O sync de histórico de mensagens, em particular, foi
escopo que eu ampliei seguindo a spec — não foi pedido.

## Estado

- Working tree limpa, 22 checks verdes, build Debug ok — igual ao início da
  sessão. Nada commitado em momento algum.
- `docs/IDEIAS.md` e `docs/ROADMAP.md`: item movido pra descartadas, Trilha A
  encerrada (caem junto typing indicator, reações, busca e lista de transmissão
  enquanto dependerem de canal pareado). A spec de 29/07 ganhou aviso no topo.
- O diff completo ficou no scratchpad da sessão (`sync-revertido.patch` +
  `sync-revertido-novos.tgz`), caso um dia isso volte. **Não sobrevive à
  limpeza do /tmp** — se importa, resgate agora.

## Lição

O grilling de 29/07 desenhou o canal antes de alguém perguntar se pareamento era
aceitável no produto. Toda a sequência da Trilha A pendia dessa premissa não
verificada.

---

# 🏁 SESSÃO 2026-08-03 (fim de tarde) — nota que não toma o card, player centrado, histórico que se apaga

Micro-correções pedidas na tela, todas validadas no app Debug rodando.

## O que foi feito

**A nota rápida deixou de ser modo exclusivo.** A faixa de seções continua no
rodapé com o rascunho em foco, e a altura do card soma a faixa sempre. Sair pela
faixa não apaga nada: `active` e `text` seguem. A zona de escrita ganhou fundo
`white 7%` (cantos 8) pra se separar da moldura preta — `alturaDaSecao(.nota)`
subiu de +20 pra +28 por causa do padding.

**Clique na faixa durante a nota era desfeito.** Só o swipe zerava
`QuickNote.editing`; o clique não, e o `recalcularSecoes` seguinte via
`travadaNaNota` ainda true e puxava o foco de volta. A trava agora cai dentro de
`NotchViewModel.focar` — o caminho que clique e swipe atravessam. A linha
duplicada no handler de scroll de `KnoblerApp` saiu.

**Player descentralizado.** Era um `HStack` de 4 com Spacers iguais, então o
play caía à direita do centro. O trio anterior/play/próxima virou um HStack
centrado com espaçamento fixo e o shuffle virou `.overlay(alignment: .leading)`.

**Apagar o histórico.** `NotificationHistory.remover(_:)` e `limpar()` (esta
escreve na hora, sem esperar o debounce de 1 s). Na lista: `X` por linha, visível
só no hover, e "Limpar" no topo direito. `historycheck` ganhou `testApagar`.

**Espelho sem câmera não trava mais.** `MirrorController` virou `ObservableObject`
com `falhou` publicado quando abrir o dispositivo falha; o preview troca o
spinner por "Câmera indisponível". `GET /status` ganhou `mirrorFailed`.

**Rodapé do painel de Permissões** corrigido: a acessibilidade é pedida na
abertura, não no primeiro uso.

## Estado

- **`v0.18.1` publicada** (commit `3ecb1cd`, tag, GitHub Release, cask). Foi
  `patch` a pedido do usuário, embora carregue um `### Added` — o
  `VERSIONING.md` pediria `minor`. Fica registrado, não é pra repetir por
  descuido.
- 22 checks verdes, 55 snapshots gerados, build Debug rodando.
- Os handoffs de julho saíram daqui pra `docs/handoffs/2026-07.md`; este arquivo
  guarda só as sessões de agosto.

## Riscos e dívidas

- **Nada disso entra no harness de snapshot** a não ser o player
  (`music-expanded.png`, que confirma o trio centrado). Nota (`TextEditor`),
  histórico populado (`ScrollView`) e espelho (câmera real) só têm teste manual.
- **"Câmera indisponível" não foi visto de verdade**: a máquina tem webcam e não
  dá pra desconectar a FaceTime HD. O caminho de erro está exercitado só por
  leitura de código.

---

# 🏁 SESSÃO 2026-08-03 (tarde) — espelho que liga sozinho, link que se cola

Quatro pedidos curtos do usuário, todos validados no app rodando. Saiu a
`v0.18.0`.

## O que foi feito

**Espelho fixado liga sozinho** (`NotchView.ligarEspelhoSeEmFoco`, chamado no
`onChange` de `vm.focus` e de `vm.expanded`). O `expanded` também entra porque
recolher o card desliga a câmera — na reabertura o `focus` não muda.

**Abrir a câmera congelava o card por ~1 s.** Causa: `MirrorController.acquire()`
criava o `AVCaptureDeviceInput` na main thread. A sessão agora sobe vazia e
recebe a entrada no background; o preview mostra spinner + "Ligando a câmera…"
até o `AVCaptureSessionDidStartRunning`. Sem isso o spinner nem chegava a ser
desenhado — foi por isso que a primeira tentativa "não mostrou nada".

**Ícone de câmera saiu do player** (fila de controles e estado "Nada tocando").
O espelho agora se liga pela própria seção.

**Barra de endereço na seção Link.** Sem página, a seção mostra um `TextField`
já focado: ⌘V + Enter. `keyboardAllowed` deixou de exigir `linkPreview.hosted`
(o campo existe antes de haver página) e os atalhos de edição do `LinkPreview`
(⌘C/⌘V/⌘X/⌘A — o app não tem menu bar) passaram a `internal` pra serem
instalados também pelo campo. `alturaDaSecao`/`larguraDoCard` ganharam
`linkAberto`: os 780 pt são do preview, não da barra.

## Estado

- `v0.18.0` publicada (tag, GitHub Release, cask) e instalada em
  `/Applications`, rodando em 3 monitores.
- 22 checks verdes.

## Riscos e dívidas

- **Sem câmera utilizável o espelho fica no "Ligando a câmera…" pra sempre**
  (`ponytail:` em `Mirror.swift`). Vira estado de erro quando alguém sem webcam
  reclamar.
- Nada disso tem check automatizado: espelho e link dependem de `NSView` real e
  ficam fora do harness de snapshot.

---

# 🏁 SESSÃO 2026-08-03 — seções fixadas, e a nota que prendia o card

Uma feature pedida em uma frase ("escolher as funções fixadas no notch") que
expôs três bugs de interação na nota rápida — todos achados com o app rodando e
log real, não com leitura de código.

## O que foi feito

**Seções fixadas** (`v0.17.0`): alfinete por linha em Ajustes › Notch. Seção
fixada aparece no card mesmo sem conteúdo, na posição da ordem-base.
`NotchSectionOrder.ordenar` ganhou o parâmetro `fixadas`;
`AppSettings.notchSectionsFixadas` persiste (chave homônima, padrão vazio, sem
migração). Estados vazios novos: atividade, Pomodoro, Link e espelho desligado.
Foi executada por subagentes (5 tasks, spec + plano em `docs/superpowers/`).

**Foco inicial passou a ser a primeira seção COM conteúdo.** Sem isso, fixar a
Música abre o card em "Nada tocando" toda vez.

**A nota rápida deixou de ser uma armadilha.** Três bugs, nesta ordem:

| Sintoma | Causa real |
|---|---|
| "perdi o texto ao sair" | não havia saída: o swipe era engolido com a nota em foco (`KnoblerApp.swift`, gate `vm.focus != .nota`) e a única saída era o interruptor, que apaga |
| "seção fixada não aceita teclado" | `keyboardAllowed` exigia `noteVisible`, mas a seção fixada desenha o campo antes de a nota ter dono → `QuickNote.adotar(_:)` |
| "não encolhe com o mouse fora" | `mode` devolve `.music` enquanto `typingNote`; zerar só o `expanded` deixava o card na tela, e o campo desenhado segurava o `editing` que sustentava o modo |

O card agora encolhe 3 s depois de o mouse sair (0,3 s no resto), e
`fecharPorHoverOut()` derruba `editing` junto. Só o **link** ainda congela o
card contra o hover-out.

## Como os bugs foram achados

`NSLog` temporário em `keyboardAllowed`, `setHover` e no work de fechar; app
Debug rodado com stdout em arquivo; o usuário reproduziu o gesto real. Os dois
últimos bugs eram invisíveis na leitura do código — o log mostrou
`fechar work rodou` seguido do card ainda aberto. **Vale repetir a receita:**

```bash
APP=~/Library/Developer/Xcode/DerivedData/Knobler-*/Build/Products/Debug/Knobler.app/Contents/MacOS/Knobler
nohup "$APP" > /tmp/knb.log 2>&1 &
```

O menu da barra é acionável por AppleScript (`System Events` → `menu bar item 1
of menu bar 1`), o que dá pra ligar a nota sem tocar no mouse. Clique e scroll
sintéticos **não** funcionaram nesta máquina (3 monitores).

## Estado

- 22 checks verdes; `eventoscheck` ganhou 6 casos novos (fixadas, swipe, adotar,
  atraso de fechar, hover-out).
- O harness agora zera `notchSectionsFixadas` no `main()`: um teste que aborta
  no meio contaminava a rodada seguinte.
- Instalado em `/Applications` e validado no app rodando.

## Pendências deixadas de propósito

- **Persistência da nota em disco** — o usuário adiou explicitamente ("persistência
  vemos depois"). A nota continua morrendo com o app.
- **Link fixado não reabre o último link**: a seção mostra "Nenhum link copiado".
- `docs/images/settings-notch.png` foi recapturado com o alfinete ainda como
  botão; hoje é um checkbox. Vale refazer na próxima captura de painéis.
- Harness de snapshot não cobre os quatro estados vazios novos (são `Image` +
  `Text`, a lógica de quando aparecem está travada por asserção).
