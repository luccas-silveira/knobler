# 🏁 SESSÃO 2026-08-05 — as 10 conversões restantes → v0.24.0

Fecha a etapa do marketplace: **nenhum card da vitrine diz mais "Em breve"**. As
11 features são peças de verdade — nascem pelo `PluginHost`, morrem no `parar()`
e somem caladas dos pontos de uso quando desinstaladas.

Escopo confirmado com o dono no começo: tudo direto (sem mapa/tickets novos no
wayfinder), **fáceis primeiro** (as com painel de Ajustes), uma release MINOR no
fim. Execução por SDD — um subagente implementador por peça, revisão de
tarefa depois de cada uma, revisão da branch inteira no fim. Plano em
`docs/superpowers/plans/2026-08-04-conversoes-plugins.md`.

## O que foi feito

Dez conversões, na ordem: **Lembretes, Descanso, Mensagens, Webhooks, Ditado,
Desenho, Espelho, Nota rápida, Preview de Link, Conversão de arquivo**. Cada uma
com `pronta: true`, caso novo no `plugincheck` e linha no `CHANGELOG.md`.

**O padrão do Pomodoro aguentou as dez**, com três variações que nasceram da
prática e viraram precedente:

- **Efeito que não cabe em Foundation vira closure emprestada** (`XEfeitos` +
  `montarX`). Quando o tipo real não pode nem ser *citado* em `Plugin.swift` —
  `DictationController` importa FluidAudio (SPM), que o `plugincheck` (swiftc
  avulso) não resolve —, a peça empresta **um** closure `nascer`
  (`DitadoEfeitos`, `AnotacaoEfeitos`, `EspelhoEfeitos`, `NotaRapidaEfeitos`,
  `PreviewLinkEfeitos`). É indireção mais rasa, e está marcada como tal.
- **Instância ociosa** onde um `environmentObject`/init exige o objeto mas a peça
  pode estar desinstalada (`lanMessagingOcioso`, `messageStoreOcioso`,
  `webhookClientOcioso`). Só é legítima porque nenhum desses tipos faz nada no
  `init` — foi verificado, não presumido.
- **Singleton `.shared` continua singleton** (`AnnotationController`,
  `MirrorController`, `QuickNote`, `LinkPreview`): o `montarX` chama o start e
  devolve o próprio singleton como `PluginServico`. Transformar em instância
  seria refatorar a feature.

**As duas peças sem serviço** (Preview de Link, Conversão) não ganham nada ao
"nascer": o valor está nos **guards nos pontos de uso**, na prateleira. A regra é
a opção **sumir**, então o `Button`/`Menu` inteiro fica dentro do `if` — botão
desabilitado teria violado a decisão de 002.

**O `ABRIR` das peças sem painel** (dívida aberta desde o ticket 006) foi
resolvido: `switch peca.id` no ramo `painel == nil` de
`PluginsSettingsPane.abrir(_:)`, quatro casos, todos roteando pelo
`viewModelPrincipal()` (que cai em `notches.values.first` quando a tela principal
não tem notch). Espelho acende a câmera, Nota rápida abre a nota, Preview e
Conversão focam a prateleira — sem URL nem arquivo não há o que espiar ou
converter, e inventar tela seria mentira.

## Validação

- `./tools/check.sh` → **36 ok** (11 casos no `plugincheck`, mais o gate novo
  `app-selfcheck`).
- Build Debug e Release ok; `--selfcheck` ok.
- Release publicada: <https://github.com/luccas-silveira/knobler/releases/tag/v0.24.0>
  (GitHub Releases + cask do tap).

**A revisão da branch inteira pegou dois bugs Critical que os 35 gates não
pegavam** — e nenhuma das dez revisões de tarefa podia ver, porque cada uma
enxergava só a própria fatia:

1. **Lembretes e Descanso paravam de disparar depois que o Mac dormia.** O
   observer de wake era registrado **antes** do `start()`, e
   `ScheduleEngine.start()` começa chamando `stop()` — que desliga o wake. O
   observer morria no nascimento, e o `parar()` não tinha mais o que
   desregistrar (vazamento na desinstalação, por cima). O gate correspondente
   era **vacuous**: afirmava o desligamento que o próprio `start()` já causara.
2. **A seção Mensagens do card ficava vazia pra sempre.** `placeWindows()` rodava
   antes de `plugins.subir()`, então o `.environmentObject` capturava as
   instâncias **ociosas** enquanto o Bonjour de verdade subia depois.

Ambos corrigidos, e os gates agora falham se a ordem voltar.

Mais dois Important da mesma revisão: instalar Mensagens/Webhooks pela vitrine só
funcionava de verdade após relançar (a janela de Ajustes é cacheada e a raiz
capturava os objetos ociosos — a raiz agora é refeita quando esse par muda); e o
`--selfcheck` não estava em gate nenhum (cinco provas de teardown nunca rodavam
sozinhas).

## Pendências e followups

- **Na CI o gate `app-selfcheck` sempre pula** — ele roda o binário do
  DerivedData quando existe, e lá não existe. Build completo (com o SPM do
  FluidAudio) leva minutos e quebraria a hermeticidade dos outros gates. Efeito:
  as cinco provas de teardown são, na prática, locais.
- **Nada prova o disparo real pós-wake.** O gate prova que o observer está
  registrado com a peça viva e desregistrado depois — não que o Mac acordando
  dispara o lembrete.
- **Dívidas do mapa que continuam abertas**: permissões por plugin (o painel
  Permissões ainda pede Acessibilidade e Calendário pro app todo, com peça
  instalada ou não) e ligar plugin com gancho global sem reiniciar — no Ditado o
  caminho é síncrono e acorda, mas isso foi deduzido por leitura, não medido com
  microfone de verdade.
- **Duas migalhas da revisão final**, ambas Minor e sem risco: o comentário do
  `stashToPasteboard` ficou órfão acima de `desativarPelaDesinstalacao`
  (`QuickNote.swift`), e o `app-selfcheck` pega o DerivedData mais novo sem
  checar frescor (`tools/check.sh`) — um binário velho pode passar o gate.
- Herdadas e intocadas: Notion travado (plano pago), `POST /profiles` falhando em
  silêncio no assistente.

## Armadilhas medidas

- **Self-check pode encostar no hardware do usuário.** A primeira tentativa de
  provar o `parar()` do Espelho chamava `MirrorController.acquire()` de verdade —
  que despacha `AVCaptureDeviceInput` + `startRunning()`. Num Mac autorizado isso
  **acende o LED da câmera** a cada `--selfcheck`; num Mac com TCC
  `.notDetermined` é o gatilho clássico do diálogo implícito de permissão.
  Revertido: o check forja o estado e a lacuna do refcount ficou documentada.
  Gate mais fraco é aceitável; acender a câmera do usuário não é.
- **Gate de vazamento precisa de asserção nos dois lados.** O `desligou == true`
  depois de desinstalar não distingue "desligou na desinstalação" de "nunca
  esteve ligado" — foi exatamente assim que o Critical 1 passou por dez
  revisões. Afirme também o estado **vivo** antes.
- **Ordem no `applicationDidFinishLaunching` é contrato invisível.**
  `.environmentObject` captura o objeto no instante em que a view é construída:
  quem nasce depois nunca chega na tela. Não há gate observando isso.

# 🏁 SESSÃO 2026-08-04 (noite) — Fase 5 do marketplace → v0.23.0

Última fase do mapa wayfinder do marketplace de plugins: docs, imagens e
release. Fecha o ticket 015 e o **mapa inteiro** (15 tickets). Escopo confirmado
com o dono no começo: tudo, com release, e autorização pra matar o Knobler de
`/Applications` durante a captura de tela.

## O que foi feito

**`docs/architecture.md` ganhou "O app é feito de peças"** — seção nova entre
Composição e Ownership: a peça é dado + uma closure `nascer`, o registro é array
literal, o `PluginHost` só visita quem está instalado, peça pergunta por peça
(`deps.instalado`), as superfícies somem sozinhas, desinstalar não apaga nada, e
`Plugin.swift` importa só `Foundation` de propósito.

**`docs/plugins.md` (novo)** — doc de usuário, ligado em `docs/index.md`: as
duas seções da vitrine, os três estados do botão, o que some ao desinstalar, o
aviso de relançar pra peças com gancho global, e o parágrafo pra scripts.

**Duas capturas do painel real** (`NavigationSplitView` não renderiza no harness
offscreen): `settings-plugins.png` — rolada até a seção Plugins, com ABRIR + ⋯
no Pomodoro e "Em breve" nas outras — e `settings-plugins-fabrica.png`, o topo
com as 4 de fábrica.

⚠️ **O item 2 do ticket não era só doc.** O ticket 008 (API local com plugin
desligado) tinha sido **decidido e nunca implementado** — nenhuma das fases 1–4
tocou o `NotchAPIServer`. Documentar o `404` sem o `guard` seria doc mentindo,
então o código de 008 saiu aqui, nas três linhas que ele previa:
`guard PluginHost.shared.estaInstalado(.espelho)` no `POST /mirror` (sem ele a
rota responderia `{"ok":true}` chamando callback vazio), a marca
`(plugin: espelho)` no título e no `usage` do 404 genérico, e
`status["plugins"]` no `statusProvider` do `AppDelegate`.

**Release v0.23.0** — `./tools/release.sh minor` depois de um `--dry-run` limpo.
Tag, GitHub Releases e cask do tap; os 5 commits do marketplace foram pushados
agora (estavam locais desde a F1).

## Validação

- `./tools/check.sh` → **35 ok** (mesmo número da F4: nenhum gate novo).
- Build Debug ok; a captura saiu do painel real rodando com
  `--ajustes=plugins`, e o app de `/Applications` foi relançado no fim.
- Release publicada: <https://github.com/luccas-silveira/knobler/releases/tag/v0.23.0>

**Sem gate novo, de propósito.** Nenhum harness compila `NotchAPIServer.swift`
nem `KnoblerApp.swift` (fatia que o ticket 009 já tinha constatado), e o guard
depende do singleton `PluginHost.shared` — provar isso exigiria injetar o host
no servidor, mais código que o próprio guard. Vale revisitar quando existir uma
**segunda** rota de peça.

## Pendências e followups

- **As outras 10 conversões.** Trabalho mecânico agora; cada uma acende os
  botões do card correspondente na vitrine (hoje "Em breve"). Recomendação
  registrada nesta sessão: a próxima é o **Espelho** — é a única peça com rota
  de API (dá caminho real ao `guard` escrito hoje) e obriga a resolver o `ABRIR`
  de peça sem painel, fechando duas dívidas de uma vez. O Descanso é a
  alternativa (é a ponta da única dependência plugin→plugin).
- **Dívidas do mapa, nenhuma urgente** ("Not yet specified"): permissões por
  plugin, ligar plugin sem reiniciar, ponto de entrada do `ABRIR` nas 5 peças
  sem painel.
- Herdadas da sessão de webhooks, intocadas: Notion travado (plano pago),
  `POST /profiles` falhando em silêncio no assistente.

## Armadilhas medidas

- **Screenshot da barra lateral logo após desinstalar pega a `List` no meio da
  animação** e parece que painéis alheios sumiram. Recapture depois de assentar
  antes de diagnosticar.
- **`osascript … get {name, position, size} of every window` devolve os campos
  achatados** — todos os names, depois todas as positions, depois todas as
  sizes. Casar posição com a janela errada custou tempo.
- **Tecla não rola a `ScrollView` do painel**: precisa de
  `CGEventCreateScrollWheelEvent`/`scrollWheelEvent2` (o `python3` do sistema
  não tem o módulo `Quartz` — compilar um `.swift` de 10 linhas foi mais rápido
  que procurar alternativa).

# 🏁 SESSÃO 2026-08-04 — Fase 5 dos webhooks → v0.22.0

Última fase do mapa wayfinder de notificações externas: docs, imagens e release.
Fecha o ticket 021 e o mapa inteiro (19/22 tickets; só o Notion segue travado).

## O que foi feito

**`docs/webhooks.md` reescrito** num arquivo só. "Como usar" começa pelo
assistente como porta única — os cinco passos (Nome → Serviço → Link → Primeiro
envio → Mapa) e o escape "Outro serviço (sem preset)" nomeado —, mais a
subseção do editor de mapa e duas seções novas: **Presets** (tabela dos quatro
caminhos, por que o mesmo serviço repete por caminho, reaplicar é manual) e
**Filtros no template** (`semHifens`, `data`, `quill`, um exemplo cada, falha
suave). O doc antigo não falava de template nenhum. O item (a) do ticket —
espelhar os filtros na prévia do app — já tinha saído na Fase 1.

**Imagens à mão** com a build Debug rodando: `settings-webhooks.png` e
`mapping-editor.png` recapturadas, `assistente-servico.png` criada.

⚠️ **A receita de captura do CLAUDE.md estava incompleta** (corrigida lá):
`screencapture -l<windowID>` **reescala** a janela — num sheet o PNG sai com a
janela-mãe em volta, e coordenada de clique tirada dessa imagem **erra o alvo**
(perdi várias rodadas achando que o botão "Continuar" estava desabilitado).
Pra automatizar clique + captura: `screencapture -R x,y,w,h` com os bounds de
`CGWindowListCopyWindowInfo`, e `sips -z` pra 1x. Clique sintético em SwiftUI só
responde com `CGWarpMouseCursorPosition` **mais** eventos `.mouseMoved` em
passos pequenos antes do down/up — um `Button` (ao contrário de `onTapGesture`)
ignora o clique sem isso.

**Feature de foco persistente commitada** (`ae55397`). Estava solta na árvore
desde uma sessão anterior e já anunciada no `## [Unreleased]`; o `release.sh`
trava com fonte modificada. Autorizado pelo usuário incluir no release.

**Release v0.22.0** — `./tools/release.sh minor`, cask bumpado.

## Validação

- `./tools/check.sh` → **34 ok**.
- **Fluxo exercitado clicando no app rodando** — pendência arrastada desde a
  Fase 2, enfim fechada. Perfil criado pelo assistente, preset do GHL de
  Marketplace escolhido, POST real no link do perfil → o passo Primeiro envio
  virou "Recebido" pelo polling de 2s, o editor semeou os campos da receita,
  o mapa salvou e o POST seguinte chegou como card no notch
  ("Marina Duarte / ContactCreate · marina@exemplo.com").
- Limpeza feita: perfis de teste (`Vendas`, `Deploys`, `__probe__`) apagados no
  relay, toggle "Receber notificações externas" de volta a desligado (estava
  assim antes), build Debug encerrada. O app de `/Applications` não foi tocado.

## Pendências e followups

- **Notion travado** (011 → 022): a automação de database "Enviar webhook" é
  recurso de plano pago e o login cai em onboarding de conta nova. Decisão do
  usuário nesta sessão: **deixar de lado**. Nada no mapa depende disso.
- **Névoa registrada no mapa** (nenhuma virou ticket): prévia fiel ao card real,
  aviso de token/filtro não resolvido (hoje renderiza vazio ou devolve o cru em
  silêncio), sinal de saúde no painel, descoberta da árvore clicável, renomear e
  duplicar perfil, ajuda inline do campo "ID (dedupe)".
- `POST /profiles` do app falha em silêncio (`createProfile` devolve `nil` e o
  assistente simplesmente não avança). Não me mordeu no fim — era coordenada de
  clique errada —, mas o caminho de erro não tem UI nenhuma.

# 🏁 SESSÃO 2026-08-04 — painel Desenho → v0.21.0

Fecha a anotação de tela: a seção do card (feita na madrugada, nunca commitada)
saiu junto com um painel de Ajustes próprio e os padrões do traço.

## O que foi feito

**Painel Desenho nos Ajustes** (`SettingsView.swift`). `SettingsPane.desenho`
novo, entre `notch` e `ditado`. A seção "Anotação de tela" **saiu** de
`NotchSettingsPane` — não duplicar. Cinco blocos: Ativação, Padrões do traço,
Fundo, Desvanecer, Atalhos. A tabela de atalhos é **derivada** de
`AnnotationTool.key`, não escrita à mão — ferramenta nova aparece sozinha.

⚠️ `ColorPicker` do SwiftUI precisa ser qualificado (`SwiftUI.ColorPicker`): o
projeto tem um `ColorPicker` próprio (o conta-gotas) que sombreia o do
framework. O erro é `'ColorPicker' cannot be constructed because it has no
accessible initializers` — não parece um conflito de nome à primeira vista.

**Padrões do traço persistidos** (`AppSettings.swift`, `AnnotationController.swift`).
`annotationDefaultTool`, `annotationDefaultColor` (hex) e `annotationLineWidth`
(1–24 pt, era fixa em 6 dentro de `AnnotationStyle`). O controller lê as três no
init e `refreshScreens()` aplica cor e espessura ao state de cada monitor — é
por onde um display recém-plugado herda o estado corrente. `setLineWidth` novo,
espelhando `setColor`. `/status` ganhou `annotation.lineWidth`.

`AnnotationColor.hex` / `init?(hex:)` moram em **extension**, não no corpo do
struct: um `init` lá dentro apagaria o memberwise `init(red:green:blue:alpha:)`
que meio mundo usa.

**Release v0.21.0** — o commit levou junto as três frentes que estavam soltas na
árvore desde ontem (silêncio em chamadas, seção Anotação, painel Desenho).
Commit único de propósito: os arquivos estavam entrelaçados e picar por hunk
deixaria commits que não compilam.

## Validação

- `./tools/check.sh` → 25 ok. `annotationcheck` ganhou 5 asserções de hex.
  ⚠️ Round-trip de cor compara **hex**, não `Double`: `0.82` não sobrevive ao
  arredondamento pra byte (`0xD1` → `0.8196…`), então `AnnotationColor(hex:) == .yellow` é falso.
- Release build instalada e rodando; `--ajustes=desenho` abre no painel novo.
- Persistência provada por fora: `defaults write annotationLineWidth 18` +
  `annotationDefaultTool arrow` → relaunch → `/status` reflete os dois. Defaults
  restaurados no fim.
- `foco-anotacao.png` byte-idêntico depois da mudança.
- **A queixa "o lápis só aparece depois de desenhar" já estava resolvida**: o
  `.anotacao: true` em `NotchViewModel.estadoDasSecoes` é de ontem e ainda não
  estava commitado — a build de `/Applications` (21:46) não tinha. Confirmado no
  app real: card aberto sem nenhum traço mostra o lápis na faixa.

## Pendências e followups

- `docs/images/settings-desenho.png` foi capturado com `screencapture -R` na
  geometria da janela + 1 pt de borda (802×554, o mesmo dos outros painéis), num
  monitor @1x. Numa tela Retina o corte é outro — ver a receita no `CLAUDE.md`.
- `annotationBackground` continua em UserDefaults cru dentro do controller, fora
  do `AppSettings`. Migrar só se outra coisa precisar ler.
- Pendências antigas seguem abertas: hover não expande a pílula do Pomodoro,
  folga vazia embaixo do card do Pomodoro, `Pomodoro.selfCheck()` órfão do
  `check.sh`, Link fixado não reabre o último link.

---

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
(⌥ direita = ditado, Control esquerdo = anotação). Ela **não escreve** em
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
