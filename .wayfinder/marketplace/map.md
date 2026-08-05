# Preparar o Knobler pra viver de plugins

<!-- wayfinder:map -->

## Destination

O app aprende a ser feito de **peças**: uma feature pode nascer ou não nascer
conforme estiver instalada, sem `if` espalhado e sem custo nenhum quando
desligada. O mapa fecha com **uma feature-cobaia** convertida de verdade —
compilando, com gate em `tools/check.sh`, doc e entrada no `CHANGELOG.md` — mais
a lista decidida de quem é de fábrica e quem é plugin. **A loja em si fica de
fora** (ver Out of scope): no fim deste mapa o catálogo tem um item só, e é de
propósito.

## Notes

- Domínio: macOS, AppKit + SwiftUI, deployment target 14.2. Convenções em `CLAUDE.md`.
- Este mapa **carrega a execução** (override do "plan, don't do"): as últimas
  fases implementam o piloto. Até lá, tickets decidem.
- **Linguagem simples**: o dono do projeto é leigo em arquitetura. Nada de jargão
  sem explicar; recomendação explícita em toda pergunta.
- Restrições que já derrubaram alternativas: sem XCTest (só os harnesses
  `tools/*check*.swift`), sem framework de arquitetura obrigatório, assinatura
  local (`Knobler Local Signing`), promessa de `~0% CPU parado / ~22MB RAM`
  (`PRODUCT.md`).
- Precedente que vale copiar: o piloto Ask de 2026-07-24
  (`docs/superpowers/specs/2026-07-24-arquitetura-modular-design.md`) — uma
  feature convertida, padrão validado, resto intocado.
- Skills por sessão: `superpowers:brainstorming` antes de desenho novo,
  `grill-me` nos tickets de grilling, `ponytail` sempre (o risco deste mapa é
  inventar framework de plugin), harnesses `tools/*check*.swift` na execução.
- Sem tracker remoto — este diretório é o tracker. O mapa de webhooks (fechado)
  vive em `.wayfinder/map.md`.

## Decisions so far

- Destino é o **app preparado**, não a loja pronta e não um documento —
  charting, 2026-08-04.
- **Todo plugin é do próprio autor do app.** Terceiros não publicam. Motivo:
  código de estranho rodando dentro do Knobler teria as permissões do Knobler
  (Acessibilidade, microfone, tela, calendário) — buraco grande demais pro
  ganho. Não fecha a porta pra terceiros depois — charting.
- **Plugin não é arquivo baixado; é chave ligada.** Todo o código viaja no app
  (7,5 MB zipado — não há o que economizar) e "instalar" é marcar como ligado.
  Derruba junto: carregar código em tempo de execução, afrouxar a assinatura, N
  builds por release — charting.
- **Uma cobaia só neste mapa.** As outras ~14 features ficam como estão; cortar
  com a forma errada é retrabalho vezes 14 — charting.
- **Plugin desligado custa zero**: o serviço nem nasce. Vem do número prometido
  no `PRODUCT.md`; é o que obriga o `AppDelegate` a perguntar "quem está ligado?"
  em vez de ligar tudo na mão — charting.
- **Ninguém perde feature na atualização**: quem já tinha algo ligado ganha o
  plugin marcado como instalado, uma vez só, na primeira abertura da versão nova
  — charting.
- **O mapa implementa**, não só decide: a forma da peça só se prova compilando —
  charting.
- [Como uma feature está grudada no app hoje](tickets/001-como-uma-feature-esta-grudada-hoje.md)
  — levantamento das 15 features em
  [`research/001-amarras.md`](research/001-amarras.md). Quatro achados que mudam
  o desenho: **dez das quinze features não têm como não nascer** hoje (e dois dos
  toggles existentes só escondem da tela, não desligam); **quatro features são
  `.shared`** e nem passam pelo `AppDelegate`; **o ditado depende do tap global do
  VolumeHUD**, então peça pode depender de recurso de outra peça; e **`publicar()`
  é o funil de sete features**, o que provavelmente faz das notificações um
  serviço de base, não um plugin.
- [Quem é de fábrica e quem é plugin](tickets/002-quem-e-de-fabrica-e-quem-e-plugin.md)
  — critério: **de fábrica é o que substitui algo que o macOS já fazia; plugin é
  o que acrescenta**. Dá **4 de fábrica** (Música/HUDs, Notificações, Shelf,
  AirPods) e **11 plugins** (Pomodoro, Lembretes, Descanso, Mensagens LAN,
  Webhooks, Ditado, Espelho, Anotação, Nota rápida, Preview de Link, Conversão de
  arquivo) — catálogo grande o bastante pra valer loja. A única dependência
  plugin→plugin é Pomodoro→Descanso, e a regra é **a opção some, sem avisar**:
  logo a peça precisa saber perguntar se outra peça está instalada, com "não"
  sendo caminho normal.
- [A forma da peça](tickets/003-a-forma-da-peca.md) — a peça é **dado, não
  protocolo**: um `struct Plugin` com id, nome, ícone e as superfícies que
  ocupa, mais **uma** função `nascer`. A lista é um **array literal**
  (`PluginRegistry`) com gate de compilação, sem descoberta mágica. `nascer`
  ser closure é o que alcança os quatro singletons `.shared`; morrer é
  `parar()` + soltar a referência, e é só disso que o custo zero depende. Peça
  pergunta por peça com `deps.instalado(_:)`, e `false` é caminho normal.
  Superfície de peça desligada nem é iterada. O enum `NotchSection` **fica como
  está** — a ficha só cita o nome da seção, com assert conferindo. Protótipo
  compilando em
  [`prototypes/003-forma-da-peca.swift`](prototypes/003-forma-da-peca.swift).
- [Qual feature é a cobaia](tickets/004-qual-e-a-cobaia.md) — **é o Pomodoro**.
  Ganhou por ser a **única** feature com a dependência plugin→plugin (chama o
  Descanso nas pausas), por **não ter toggle nenhum hoje** (logo o piloto prova
  `nascer`/morrer de verdade, e não um toggle reaproveitado) e por não ser
  crítica. Descartado o Espelho, que cobria rota e permissão mas tem três donos
  abrindo ele. Piloto concluído = cinco itens: preferência manda no nascimento,
  as três superfícies somem, o `Timer` de 1 s não existe, a opção do Descanso
  some sem avisar, e um gate novo em `tools/check.sh` falha se qualquer um
  regredir. O item da dependência é provado **só no harness** (com o Descanso
  sempre presente no app real, o caminho "sem Descanso" nunca roda de verdade).

- [Onde vive o "instalado" e como quem já usa atravessa](tickets/005-onde-vive-o-instalado.md)
  — instalado é **uma lista de ids** (`["pomodoro", ...]`) numa chave só de
  `UserDefaults` (`pluginsInstalados`), não um booleano por plugin: o
  `AppDelegate` faz uma pergunta e a lista responde numa leitura, e id que sai do
  catálogo morre limpo em vez de virar lixo nos ajustes. **Todo mundo atravessa
  com os 11 instalados** — quem atualiza e quem instala do zero — com os
  interruptores antigos intactos; a migração roda uma vez com o truque de versão
  do `Onboarding` (`plugins.migracao`). Ler o toggle antigo pra decidir foi
  descartado: interruptor desligado não é feature perdida. **Id órfão ignora
  calado** (mesma regra do Pomodoro→Descanso) e não é apagado, então plugin que
  volte com o mesmo nome volta instalado. Custo aceito: o ganho de `~0% CPU
  parado` só aparece quando a pessoa desinstala de propósito.

- [A tela mínima de instalar e desinstalar](tickets/006-tela-minima-de-instalar.md)
  — é uma **vitrine em grade** num **painel próprio "Plugins"** na barra lateral
  de Ajustes. Card = capa (o símbolo SF da ficha da peça sobre degradê da cor
  dela — **zero arte nova**), nome, uma frase e botão pílula. Duas seções fixas,
  "Incluído no Knobler" (as 4 de fábrica, rótulo "Incluído", sem ação) e
  "Plugins" (as 11): o card **não muda de lugar** ao instalar, só o botão muda.
  Botão em três estados lidos da lista de ids de 005; o **⋯ com "Desinstalar"**
  só existe em peça instalada, como na App Store; e **`ABRIR` é sempre vivo** —
  peça com painel abre o painel, peça sem painel **abre a própria feature**
  (convenção Apple: nada de rótulo cinza morto "INSTALADO"). Contra a
  recomendação, o dono escolheu grade em vez de lista e pôs as de fábrica na
  vitrine — custo aceito: as 4 de fábrica ganham ficha decorativa (sem `nascer`,
  sem `PluginID`) e as três peças anônimas ficaram com nome provisório. Se
  desinstalar **avisa** é o 007. Protótipo compilando e renderizando PNG em
  [`prototypes/006-tela-de-plugins.swift`](prototypes/006-tela-de-plugins.swift).

- [O que acontece com os dados quando se desinstala](tickets/007-dados-orfaos-ao-desinstalar.md)
  — **desinstalar não apaga nada, nunca**, e é uma regra só pra todas as peças:
  dado, preferência, segredo no Keychain e perfil no relay ficam todos onde
  estão. Ganha por ser o padrão do macOS, por o dado insubstituível ser de quatro
  peças (Lembretes, Descanso, Mensagens LAN, Anotação) e o lixo ser de poucos KB,
  e por custar **zero linha** — a rotina de limpeza é que seria código novo, e é
  onde mora o bug que apaga demais. Sem diálogo de "tem certeza?" (não há perda;
  reinstalar é o desfazer, um clique no mesmo card), só a frase **"Desinstalar
  (seus dados ficam salvos)"** no menu ⋯ do 006. As chaves de armazenamento
  **não** são renomeadas pro id da peça — renomear é migração e quebraria a
  promessa. Efeito: desinstalar/reinstalar não toca em disco, logo "reinstalar
  reencontra o dado" sai sem código e sem gate novo.

- [Ordem das seções quando a peça entra e sai](tickets/010-ordem-das-secoes-quando-a-peca-entra-e-sai.md)
  — **a ordem salva nunca é tocada**: instalar e desinstalar não escrevem em
  `notchSectionOrder` nem em `notchSectionsFixadas`. Três das quatro perguntas
  saem de graça do código que já existe — `sanear` mantém a seção na lista salva
  (o enum não encolheu, decisão de 003) e `ordenar` só exibe quem tem conteúdo,
  então peça que não nasce some da tela sozinha e **reinstalar devolve a seção no
  lugar exato de antes**. Peça nova cai no fim da ordem personalizada, igual a
  qualquer seção de versão nova. Duas linhas de código novas: o **editor de ordem
  esconde** a seção de peça desinstalada (002: "a opção some, sem avisar") e a
  **fixação é ignorada, não apagada** (007: desinstalar não apaga nada) — senão a
  faixa apareceria vazia, já que fixada passa por cima de `hasContent`. O filtro
  entra como parâmetro de `ordenar`, não como consulta ao registro lá dentro, pra
  o `sectionordercheck` seguir rodando sem subir o app; dois casos novos no gate
  do piloto.

- [A API local quando o plugin está desligado](tickets/008-api-local-com-plugin-desligado.md)
  — o medo era maior que o problema: **uma rota só é de plugin** (`POST /mirror`,
  do Espelho); o resto da API é de fábrica ou é o canal de agentes, e a cobaia
  (Pomodoro) não tem rota, então isto não trava o piloto. Rota de peça
  desinstalada responde **`404` com `plugin` no corpo** — código que script
  antigo já trata, mais o id que deixa o outro lado dizer "instale o Espelho" em
  vez de "erro desconhecido"; sem o guard a rota **mentiria** `{"ok":true}`,
  porque chamar callback vazio não dá erro. No `GET /status` os campos de peça
  desligada **somem de graça** (cada serviço põe o próprio campo, e o doc já diz
  que o schema não é contrato), e entra **um campo `plugins`** com a lista de ids
  de 005, pra o script perguntar uma vez em vez de descobrir batendo em rota. A
  fronteira estável/opcional vira **marca no título da rota** (`(plugin: X)`),
  não seção nova. **A API não instala plugin** — as rotas antigas não têm
  autenticação, então seria qualquer processo local ligando microfone e câmera
  sem a pessoa ver. Custo total: um `guard`, uma linha e três de doc.

- [Fases de execução do piloto](tickets/009-fases-de-execucao.md) — **cinco
  fases** ([F1 peça e instalado](tickets/011-fase-1-peca-e-instalado.md),
  [F2 nascimento condicional](tickets/012-fase-2-nascimento-condicional.md),
  [F3 superfícies somem](tickets/013-fase-3-superficies-somem.md),
  [F4 vitrine](tickets/014-fase-4-vitrine.md),
  [F5 docs e release](tickets/015-fase-5-docs-e-release.md)) e **um gate só que
  cresce**. O código fixou a fatia antes da conversa: nenhum dos 30 gates compila
  `KnoblerApp.swift`, então o harness prova a **máquina de peças** e o
  **compilador** prova a fiação (o `let pomodoro` obrigatório virando opcional
  aponta cada ponto de uso); e o Pomodoro está grudado em **cinco** lugares do
  `AppDelegate`, não um — foi isso que quebrou a fase 3 original em duas
  (compilador numa, olho na outra). `tools/plugincheck.swift` nasce na F1 e ganha
  casos a cada fase, pra nenhuma fase terminar sem prova; os dois casos
  encomendados por 010 vão no `sectionordercheck` que já existe. **Uma linha nova
  no `Pomodoro.swift`** (`timerAtivo`): provar "sem objeto não há timer" seria
  asserção que nunca falha; o erro que morde é desinstalar com o foco rodando e
  esquecer o `invalidate()` — o único dos cinco itens invisível na tela. Contra a
  recomendação, a vitrine mostra os **15 cards** desde a F4, mas card de peça não
  convertida é **mudo** ("Em breve", sem `ABRIR` e sem ⋯) — senão desinstalar o
  Lembretes mentiria, e o `ABRIR` obrigaria a resolver 5 pontos de entrada dentro
  da F4. Custo: os 15 nomes/frases/símbolos são batidos na F4. Release MINOR
  única no fim da F5.

- [Fase 1 — a peça, o registro e o instalado](tickets/011-fase-1-peca-e-instalado.md)
  — **executada**: `Knobler/Plugin.swift` (só `Foundation`) com as 15 fichas, o
  registro literal e o `PluginHost`; o instalado como lista de ids em
  `pluginsInstalados` com a migração de uma vez só em `plugins.migracao`; gate
  novo `plugincheck` (6 casos) em `tools/check.sh`. Só o Pomodoro tem `nascer`
  de verdade — as outras 10 fichas ficam com `nascer` vazio, e é isso que mantém
  o registro compilando antes da conversão. Duas coisas que o desenho não previa:
  `gravar` precisa **preservar** o id órfão (a regra "não apaga" de 005 morreria
  na primeira desinstalação), e `parar()` do Pomodoro saiu de graça no `reset()`
  que já existia. O app compila e **nada mudou na tela** — a fiação é a F2.
- [Fase 2 — o Pomodoro nasce condicional](tickets/012-fase-2-nascimento-condicional.md)
  — **executada**: o `AppDelegate` perde o `let pomodoro = Pomodoro()` e ganha um
  `PluginHost`; o Pomodoro virou opcional e os cinco pontos de acoplamento viraram
  `?.` (menu da barra inteiro dentro de um `if let`). O que o desenho não previa:
  a montagem **não cabia** na ficha como estava — `Plugin.swift` é `Foundation`
  puro (é o que dá o gate hermético) e a montagem citava Ajustes, som, view models
  e Descanso. A saída foi separar **ligação** de **efeito**: a ficha ficou com as
  decisões (quem escuta o quê, a borda de atividade, "só pausa trava a tela") e o
  `AppDelegate` empresta um `PomodoroEfeitos` de 5 closures dizendo só *como*
  cumprir cada uma. Efeito colateral bom: a montagem virou testável — o
  `plugincheck` foi a 8 casos e confere que ela está ligada, não só que o objeto
  nasceu. Com a peça fora da lista não há objeto nem `Timer` de 1 s (itens 1 e 3
  do piloto). Ajustes e anel da faixa continuam de pé — é a F3.

## Not yet specified

- **Permissões por plugin.** Hoje nenhuma permissão é pedida no launch, e o painel
  Permissões pede Acessibilidade e Calendário pro app todo. Se o plugin desligado
  não nasce, ele também não devia puxar permissão — mas como fica o painel quando
  a permissão serve a três plugins e só um está instalado? Revisitar depois da
  forma da peça.
- **Ligar plugin sem reiniciar.** Alguns serviços podem não acordar no meio do
  uso (hooks globais, taps de áudio, interceptador de notificação). 003 provou
  que a *forma* aguenta (`instalar`/`desinstalar` em tempo de execução) e 004
  escolheu uma cobaia que **acorda sem drama** (o Pomodoro é um `Timer` simples,
  sem tap global e sem permissão). Ou seja: o piloto não responde isto, e não
  precisa — a pergunta volta nas outras 14 conversões, com o remédio barato de
  um "reinicie o Knobler pra concluir".
- **O ponto de entrada do `ABRIR` nas cinco peças sem painel.** 006 decidiu que
  peça instalada sem painel de Ajustes abre a *própria feature* pelo botão
  (Espelho acende a câmera, Nota rápida abre a nota). Hoje três delas são
  `.shared` e são abertas por gesto/atalho, não por chamada de fora. Não bloqueia
  o piloto — o Pomodoro tem painel, e 009 deixou o card de peça não convertida
  **mudo** justamente pra manter esta dívida parada. Volta nas outras conversões:
  o `ABRIR` de cada peça nasce junto com a conversão dela.
- **As outras 10 conversões.** Depois da cobaia isso vira trabalho mecânico e
  cabe em sessões soltas; não é ticket deste mapa enquanto a forma não estiver
  provada. Cada conversão acende os botões do card correspondente na vitrine
  (hoje mudo, "Em breve") — é o próprio painel Plugins que mostra o progresso.

## Out of scope

- **A loja de verdade** — servidor, catálogo, tela de vitrine, atualização de
  plugin. Fica pra um mapa próprio: o destino aqui é o app aguentar plugin, e a
  loja é a parte fácil (mesma receita do `avisos.json`, que já está no ar).
- **Plugins de terceiros** — descartado no charting; volta só como camada extra
  em cima deste mesmo mecanismo, num esforço novo.
- **Carregar código em tempo de execução** (`.bundle` baixado) — descartado no
  charting por custo de assinatura e de release, sem ganho de tamanho.
