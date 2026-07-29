# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/);
versionamento por [Semantic Versioning](https://semver.org/lang/pt-BR/).
Regras de bump em [VERSIONING.md](VERSIONING.md).

## [Unreleased]

### Added
- **Histórico de notificações (24 h)**: puxe o card do notch pra baixo numa
  passada só — ~24 pt abre o card normal, ~120 pt no mesmo gesto entra na
  cortina de histórico — pra ver banner do sistema, card de webhook, lembrete
  disparado, fim de fase do Pomodoro e conta-gotas das últimas 24 h. Uma
  alcinha no rodapé do card aberto avisa que dá pra puxar. Fechar é tirar o
  mouse (não gesto) ou clicar numa linha; com a cortina aberta e lista pra
  rolar, o scroll pertence à lista. Mora só em memória (teto de 300 linhas) —
  não sobrevive ao restart do Knobler.
- **Nota rápida**: **✎ Nota rápida** no menu da barra (◐) liga um campo de
  texto simples no card expandido, focado ao abrir. Digitar segura o card
  aberto mesmo com o mouse fora; **Esc** solta o foco. Com mais de um monitor,
  a nota mora na tela onde o mouse estava ao ligar — desconectar essa tela
  desliga a nota. Desligar o interruptor apaga o texto e recolhe o card. Sem
  persistência entre restarts.

## [0.12.0] - 2026-07-29

### Added
- **Markdown → PDF desenha tabela, imagem embutida e regra horizontal**: a
  tabela sai com uma coluna por tab stop (respeitando `:---` / `---:` e o
  cabeçalho em destaque), a imagem do markdown entra no PDF resolvida contra a
  pasta do próprio arquivo e reduzida pra caber na página, e a regra horizontal
  vira uma régua de ponta a ponta. A paginação passou de CoreText pra TextKit —
  era o `CTFramesetter` que ignorava anexo e tab stop.

### Fixed
- **Citação não sumia mais no PDF**: o cinza da citação vinha de
  `.secondaryLabelColor`, cor dinâmica que no modo escuro resolvia pra branco —
  no papel branco, texto invisível. Agora é tinta fixa.
- **O adiamento de lembrete sobrevive ao restart**: até a 0.11.0 o "Adiar 5 min"
  morava só na memória — reiniciar o Knobler antes de vencer devolvia o lembrete
  ao horário original. Agora ele é gravado no disco e restaurado no primeiro
  tick após o restart; ao vencer (ou se o lembrete for apagado), some sozinho.
  Coberto por um novo caso do `reminderscheck`.

## [0.11.0] - 2026-07-29

### Added
- **Adiar lembrete no card**: quando um lembrete dispara, o card no notch traz
  **Adiar 5 min** e **30 min** — empurra o próximo disparo sem abrir os Ajustes.
  O adiamento vale uma vez: depois de tocar, o lembrete volta pra agenda normal
  (um "uma vez" é religado pra o adiamento poder vencer). Mora na memória —
  reiniciar o app antes de vencer devolve o horário original. Coberto pelo
  `reminderscheck`, novo no `tools/check.sh`.
- **Conta-gotas (color picker)**: item **◉ Selecionar cor…** no menu da barra
  abre a lupa nativa do macOS (`NSColorSampler`); a cor amostrada vai pro
  clipboard em HEX e o notch mostra um card com a amostra da cor e os outros
  formatos (RGB e SwiftUI) pra consulta. Coberto pelo `colorpickercheck` no
  `tools/check.sh`.
- **Conversão de arquivos no shelf**: botão direito num item da prateleira abre
  **Converter para …** com os destinos que fazem sentido pro tipo do arquivo —
  imagem → PNG/JPEG/HEIC/PDF, PDF → PNG (uma por página), vídeo → MP4/MOV,
  Markdown → PDF. Mais "Mostrar no Finder" e "Remover do shelf". O arquivo novo
  nasce ao lado do original com nome livre (`foto-1.png` se `foto.png` já
  existir) e entra no shelf; o original nunca é tocado.
  - O **Markdown → PDF** é renderizado no app (parser do Foundation + CoreText),
    com cabeçalho, negrito/itálico, listas, citação e bloco de código, paginado
    em Letter. Sem tabela, imagem embutida nem regra horizontal.
  - O **vídeo** tenta remux instantâneo (passthrough) e só recodifica se o codec
    não couber no contêiner de destino; o progresso aparece na faixa de
    atividade do notch.
  - Coberto pelos `imageconvertercheck` e `documentconvertercheck`.

- **Compartilhar do shelf**: o menu de contexto da miniatura ganhou
  **Compartilhar ▸ Enviar por AirDrop / Compartilhar… / Enviar tudo por
  AirDrop**. O AirDrop abre a janela do sistema com os arquivos engatilhados; o
  "Compartilhar…" abre o menu nativo (Mensagens, Mail, Notas…). Path que não
  existe mais no disco é filtrado antes de enviar. O menu inteiro virou dois
  níveis (**Converter ▸** e **Compartilhar ▸**), que estava virando um paredão
  com até quatro destinos de conversão soltos.

### Fixed
- **O Knobler não atrapalha mais o AirDrop**: o interceptor fechava *qualquer*
  coisa que a Central de Notificações mostrasse, inclusive o alerta que
  acompanha uma transferência de AirDrop em curso (a ação `Fechar` do alerta
  casava com a lista de dicas de fechamento). Agora o alerta do AirDrop e
  qualquer alerta com botão de ação ficam na tela — o card do notch passa a ser
  um espelho, não um substituto. O card do AirDrop mostra 📥 e revela a pasta
  Downloads no clique; alertas com botão têm as ações espelhadas no card
  (clicar no notch aciona o botão real via Accessibility) e duram 30s em vez de
  5s. Regras puras em `NotificationRules.swift`, cobertas pelo `sharingcheck`.
- **`tools/snapshot.sh` voltou a compilar**: faltava `Knobler/Permissions.swift`
  na lista manual de fontes desde que o painel de Permissões entrou (0.10.0), e
  o harness morria antes de renderizar qualquer PNG.

## [0.10.1] - 2026-07-28

### Changed
- **A decisão de pareamento do relay virou função pura testada**: escolher entre
  pareado, trancado e nunca pareado estava embutida no cliente do webhook, junto
  da chamada de rede, e por isso nunca teve teste. Agora é
  `WebhookKeychainStore.pairingState()`, sem efeito nenhum, coberta pelo
  `webhookcheck` no `tools/check.sh`. O comportamento do app é o mesmo.

## [0.10.0] - 2026-07-28

### Added
- **Painel de Permissões nos Ajustes**: novo painel que lista as 7 permissões
  que o app usa, o estado de cada uma, o que quebra sem ela e um botão que abre
  o painel certo do Ajustes do Sistema. Antes não havia lugar nenhum pra ver
  isso. Acessibilidade, Microfone, Câmera e Calendários mostram o estado real;
  Rede Local, Arquivos e Gravação de Áudio do Sistema não expõem status ao app,
  então aparecem como "ainda não usada" até o primeiro uso revelar. O aviso
  **◐⚠** da barra de menus agora abre esse painel em vez do Ajustes do Sistema.
- **Caminho de notarização no `tools/release.sh`**: com `KNOBLER_NOTARY_PROFILE`
  apontando pra um perfil do `notarytool`, o release passa a assinar com
  Developer ID + hardened runtime + timestamp, submeter à Apple, dar `stapler` e
  re-zipar com o ticket dentro. Sem a variável, o fluxo é exatamente o de antes
  (certificado local, sem notarização). `tools/knobler.entitlements` destrava só
  o que o hardened runtime bloquearia: microfone, câmera, calendário e o
  carregamento do `MediaRemoteAdapter` pelo perl.

### Changed
- **O Keychain não pede mais a senha do Mac**: os três segredos do relay de
  notificações externas (`deviceId`, `deviceSecret`, `publishToken`) têm uma ACL
  presa ao requisito de assinatura de quem os gravou. Quando a assinatura do app
  muda, a ACL deixa de bater e o macOS pedia a senha do login keychain — três
  diálogos, um por item, no meio da abertura. Agora a leitura roda com a
  interação desligada: em vez do diálogo, o app detecta que está trancado e
  mostra o aviso em Ajustes › Notificações externas, com um botão **Parear de
  novo**. O re-pareamento é decisão do usuário, e não automático, porque troca o
  `publishToken` — que é a URL pública já colada nos serviços externos.
- **Documentação de assinatura e privacidade honesta**: o README explicava a
  assinatura em uma linha (“assinado ad-hoc”) e listava permissões que o app
  nunca pede (Automação, Bluetooth). Agora traz a tabela das 7 permissões reais,
  o que o macOS bloqueia e por quê, e uma tabela do que sai da máquina — checagem
  de update, relay, Deepgram, formatação de transcript, imagem de notificação —
  com como desligar cada um. Os caveats do cask foram reescritos no mesmo tom.
- **Só a Acessibilidade é pedida na abertura**: as outras permissões esperam o
  primeiro uso real do recurso. O microfone era pedido no launch junto do
  pré-aquecimento do modelo de ditado — mas baixar o modelo não usa microfone;
  agora ele é pedido no primeiro ⌥ direito segurado. A Acessibilidade também
  era pedida duas vezes (ditado e notificações); virou um pedido só, porque sem
  ela o `CGEventTap` não existe e o gatilho do ditado é invisível — não há
  "primeiro uso" que dê pra esperar.

### Removed
- **`NSBluetoothAlwaysUsageDescription`**: linha morta no `Info.plist`. É a
  descrição do TCC de CoreBluetooth, e o `BluetoothMonitor` lê os AirPods por
  `IOBluetooth` + `system_profiler` — o app nunca instanciou um `CBCentralManager`,
  então essa permissão nunca chegou a ser pedida.

### Fixed
- **`tools/release.sh` encontra o tap sozinho**: o caminho era fixo em
  `../homebrew-knobler` e abortava quando o clone estava em outro lugar. Agora
  procura ao lado do repo e no tap do `brew`, lista o que tentou quando não acha,
  e dá `pull --ff-only` antes de bumpar o cask — com mais de um clone na máquina,
  o clone atrasado só falhava lá no push, com o cask já editado.

## [0.9.0] - 2026-07-28

### Added
- **Aviso de Acessibilidade na barra de menus**: com o ditado ligado e a
  permissão faltando, o ícone vira **◐⚠** e o menu ganha um item que abre o
  painel de Acessibilidade. Sem ela o `CGEventTap` nem é criado e a ⌥ direita
  não chega ao app — a pílula de 2s do launch passava despercebida. A marca some
  sozinha quando a permissão é concedida.
- **Aviso de atualização**: o Knobler consulta o GitHub uma vez por dia e mostra
  um card no notch quando sai versão nova — uma vez por versão, e nunca por cima
  de um ditado, notificação ou HUD. O botão **Atualizar** instala na hora e o app
  reinicia sozinho: `brew upgrade --cask knobler` para quem instalou pelo cask,
  download direto do `.zip` do release para quem não. Antes de substituir o
  bundle o app confere a origem do download (host e repo oficiais), a assinatura
  e o bundle ID do que baixou; se não puder instalar (sem brew, sem `.zip`, ou
  rodando fora de `/Applications`), o botão vira **Ver release**. Em
  Ajustes › Geral ficam a versão instalada, o botão de atualizar, o
  **Verificar agora** e o toggle da checagem automática.
- **Perguntas e permissões de agente no notch**: além do `AskUserQuestion` que
  já existia, o Claude Code espelha o hook `PermissionRequest` — ferramenta,
  detalhes e as ações Permitir / Permitir na sessão / Negar — e o Codex espelha
  os três pedidos de aprovação do `app-server` (comando, alteração de arquivo e
  permissões) através de `tools/knobler codex bridge`. O terminal continua
  funcionando: quem responder primeiro vence e o outro lado vira no-op. O notch
  só exibe dados e devolve a decisão — não executa comando, não aplica diff e
  não grava permissão persistente. Sem API, sem token ou sem resposta a tempo,
  nenhuma decisão sai do notch e o prompt nativo do agente segue valendo.
  As rotas `/agent-requests` exigem um token efêmero de sessão gravado com modo
  `0600`. Documentado em [`docs/agent-requests.md`](docs/agent-requests.md).

### Fixed
- **Identidade de assinatura unificada**: o `project.yml` assinava com
  `Apple Development: …` e o `tools/release.sh` com `Knobler Local Signing`.
  Instalar um build do `xcodebuild` por cima de um release (ou o contrário)
  trocava a identidade, invalidava o `csreq` guardado pelo TCC e matava o ditado
  em silêncio. Agora as duas vias usam `Knobler Local Signing` — rode
  `tools/make-signing-cert.sh` uma vez por máquina antes do primeiro build.

### Documentation
- Organizada a documentação por objetivo, com índice, arquitetura,
  desenvolvimento, troubleshooting, contribuição e segurança/privacidade.
- Atualizados README, API local, Ask e handoff para refletir o `AskStore`
  compartilhado, o hook e os checks atuais.
- **Corrigido o que a doc dizia sobre Acessibilidade no ditado**: `docs/dictation.md`
  afirmava que a permissão servia só pro ⌘V sintético. Ela é necessária antes
  disso, pro `CGEventTap` detectar a ⌥ direita — sem ela o ditado não começa,
  em vez de gravar e não colar.
- **Troubleshooting do ditado reescrito** com o diagnóstico por `/status`
  (`axTrusted`, `tapExists`, `tapEnabled`, `keyLog`), o caso da entrada de TCC
  stale que aparece marcada mas não vale (desmarcar/marcar não resolve) e a
  confirmação de que o `checkTapHealth` recria o tap sem novo relançamento.
- **Documentada a causa da recorrência**, que o fix de 0.8.4 não cobre:
  instalar em `/Applications` um build do `xcodebuild` (assinado
  `Apple Development: …`) por cima de uma cópia vinda do `tools/release.sh`
  (assinado `Knobler Local Signing`) troca a identidade e invalida o `csreq`
  guardado pelo TCC. Registrado em `docs/development.md` e no troubleshooting.

## [0.8.4] - 2026-07-22

### Fixed
- **Ditado parava de funcionar a cada release, de vez**: o `release.sh`
  re-assinava o app ad-hoc (`codesign --sign -`). Sem identidade estável o TCC
  ancora a permissão de Acessibilidade no `cdhash`, então toda versão nova
  invalidava a concessão (`tccd: Failed to match existing code requirement`) —
  o `CGEventTap` não era criado e a ⌥ direita nunca chegava ao ditado. Agora o
  release assina com um certificado local fixo, criado uma vez por
  `tools/make-signing-cert.sh`; o `csreq` gravado pelo TCC passa a casar entre
  builds. Sem o certificado, o release ainda sai (ad-hoc) mas avisa. Quem já
  acumulou concessões stale limpa com
  `tccutil reset Accessibility com.zoi.knobler` e reconcede uma última vez.

## [0.8.3] - 2026-07-22

### Added
- **Escolha da câmera do espelho**: uma setinha no canto do preview abre a lista
  das entradas de vídeo da máquina (embutida, USB, OBS Virtual Camera, Câmera de
  Continuidade, Desk View) — antes o espelho sempre pegava a FaceTime HD. A
  setinha só aparece quando há mais de uma câmera. Em "Automática" o
  comportamento é o de sempre. A escolha é guardada pelo
  `uniqueID` do device (índice quebraria quando um USB entra/sai) e cai de volta
  pra embutida se a câmera escolhida sumir. Trocar com o espelho aberto reponta
  a sessão na hora, sem fechar o notch.

## [0.8.2] - 2026-07-22

### Fixed
- **Ditado morria em silêncio depois de um update**: o release é assinado
  ad-hoc, então o TCC ancora a permissão de Acessibilidade no cdhash e a
  revoga a cada versão nova. Sem Acessibilidade o `CGEventTap` nem é criado
  e o `flagsChanged` da ⌥ direita nunca chega ao ditado — nenhuma pílula,
  nenhum log. Agora o app detecta isso no launch, dispara o prompt do sistema
  e mostra a pílula "Ditado precisa de Acessibilidade". Reconceder em Ajustes
  › Privacidade e Segurança › Acessibilidade volta a valer na hora (o
  `checkTapHealth` recria o tap sozinho, sem reiniciar o app).

### Added
- **Documentação de usuário** (`docs/*.md`): um arquivo por feature (Now
  Playing, HUDs, Notificações, Countdown de Calendário, Ditado, Ask,
  Pomodoro, Descanso, Lembretes, Shelf, Mensagens, Webhooks, API local,
  AirPods, Mirror, Ajustes), cada um com descrição, modo de uso, permissões
  e screenshot real (`docs/images/`). README linka cada feature pro doc
  correspondente.

## [0.8.0] - 2026-07-21

### Changed
- **Ajustes redesenhados no estilo do Ajustes do Sistema**: a janela deixou o
  `TabView` 400×580 e virou `NavigationSplitView` (800×520, redimensionável)
  com sidebar de 8 painéis e ícones coloridos — Geral, Notch, Ditado, Pomodoro,
  Lembretes, Descanso, Notificações externas e Mensagens. A antiga aba "Geral"
  (parede de 20+ controles) foi dividida em quatro painéis; todo toggle agora é
  switch com descrição do que faz; sub-opções dependentes ficam desabilitadas
  em vez de escondidas. O menu do Pomodoro abre os Ajustes direto no painel
  Pomodoro. (`SettingsView.swift` novo; `AppSettings.swift`, `KnoblerApp.swift`.)
- **Notificações externas**: aba refeita como Form agrupado; ações de cada
  perfil (mapear, rotacionar, apagar) num menu "…" e copiar link virou ícone.
  Ícone de perfil que era URL de imagem não quebra mais o layout da lista.
  `ProfilesListView.swift` foi fundido em `WebhookSettingsView.swift`.
- **Lembretes/Descanso**: linhas com menu de contexto (Editar/Apagar), switch
  compacto e botão rotulado "Novo lembrete"/"Novo bloqueio" no rodapé.
- **Mensagens**: botão "Remover" foto de perfil (novo
  `AppSettings.removeMyAvatar()`); avatar maior no painel.

### Added
- Flag de desenvolvimento `--ajustes[=painel]` abre a janela de Ajustes direto
  (usada pelos screenshots de UI).

### Fixed
- Perfis de webhook: falha de rede não "esvazia" mais a lista carregada
  (`listProfiles` agora distingue erro de zero perfis), reload automático ao
  reconectar, respostas atrasadas de reloads antigos são descartadas e criar
  perfil com o relay fora do ar não come mais o nome digitado.
- Remover a foto de perfil agora propaga: peer que responde o perfil sem foto
  tem o avatar limpo do cache dos outros Macs (`MessageStore.removeAvatar`).

## [0.7.0] - 2026-07-21

### Added
- **Anexo por link nas Mensagens LAN**: botão 🔗 no composer transforma o campo
  de mensagem em campo de URL; o app baixa a imagem/GIF (https, link direto,
  timeout 15 s), valida pelos bytes mágicos e anexa pelo pipeline existente —
  o fio não muda e o destinatário nunca toca a URL.
  (`MessagesView.swift`, `MessageMedia.swift`.)

## [0.6.0] - 2026-07-21

### Changed
- **Now playing universal**: o card de música agora mostra e controla qualquer
  fonte de mídia do macOS (YouTube no navegador, podcasts, IINA…), não só
  Spotify/Apple Music. Motor novo: mediaremote-adapter v0.7.6 vendorado
  (framework carregado via `/usr/bin/perl`, contornando o bloqueio do
  MediaRemote no 15.4+; ver `Vendor/PROVENANCE.md`). O AppleScript saiu; se um
  update da Apple quebrar o adapter, o card fica vazio sem derrubar o app.
  Shuffle aparece apagado quando a fonte não reporta (navegador); barra de
  progresso lida com duração desconhecida (live). A capa agora chega em base64
  pelo próprio stream (sem download da URL do Spotify).
  (`MediaRemoteSource.swift`, `MediaController.swift` reescrito por dentro.)

### Removed
- `NSAppleEventsUsageDescription` do Info.plist — nada mais usa AppleScript.

## [0.5.0] - 2026-07-21

### Changed
- **Card de música enxugado**: a barra de abas "Música | Mensagens" saiu. A troca
  de tela agora é por swipe horizontal de dois dedos sobre o card aberto, com um
  par de pontinhos discretos no rodapé como indicador (também clicáveis). Com o
  notch fechado, o mesmo gesto continua pulando faixa.
- A bateria dos AirPods saiu do card expandido: aparece só no card transitório de
  conexão e quando algum componente cai a ≤10%.
- O botão do espelho saiu de junto do título e assumiu o 5º slot dos controles,
  no lugar do atalho pros Ajustes de Som.

### Removed
- Barras de áudio do card expandido (o notch fechado já as mostra) e o botão que
  abria os Ajustes de Som.

## [0.4.0] - 2026-07-21

### Added
- **Foto e GIF nas Mensagens LAN**: botão de anexo no compositor manda uma imagem
  (JPEG/PNG/GIF) pro outro Mac; ela aparece no card que desce do notch e no balão
  da conversa, com GIF animando. Imagem grande é reamostrada pra 1600 px/JPEG antes
  de ir; GIF vai cru pra não perder a animação (teto de 6 MB). O recebedor valida
  os bytes mágicos contra o tipo declarado e grava em `media/` com nome gerado
  localmente. (`MessageMedia.swift`, `MediaKind` em `Wire.swift`.)
- GIF acima do teto é reamostrado mantendo a animação (reduz o lado maior e,
  se preciso, pula quadros somando o tempo do quadro pulado) — um GIF de 46 MB
  do Giphy vira 5,7 MB e continua girando.

### Fixed
- **Card de mensagem não sumia mais da tela**: com resposta permitida ele ficava
  para sempre. Agora some em 20 s (6 s sem resposta), com o relógio pausado
  enquanto o ponteiro está sobre o card.
- **Fechar o card fechava só num monitor**: o X (e abrir a conversa) agora vale
  para todas as telas, como a resposta rápida já fazia.
- **Pacote acima de 64 KB era descartado calado**: `NWConnection` não entrega
  mais que isso por `receive`, e pedir o corpo inteiro de uma vez fazia a leitura
  falhar sem erro — nenhuma imagem passaria. O corpo agora é lido em pedaços, e o
  tempo-limite da troca subiu de 5 s para 20 s (anexo de MBs em Wi-Fi ruim).

## [0.3.0] - 2026-07-21

### Added
- **Mensagens LAN**: descubra outros Macs com Knobler na mesma rede e mande recados
  que aparecem no notch da pessoa, com nome e foto. Aba Mensagens no notch aberto,
  recado com ou sem resposta, histórico das últimas 20 conversas por pessoa.
  Identidade (nome/foto) configurável, pré-preenchida com a da conta do macOS.
- **Webhooks configuráveis (mapeamento por perfil)**: cada fonte externa (GitHub,
  Stripe, n8n…) vira um perfil com link próprio; manda um webhook de teste e um
  editor lado-a-lado mapeia os campos da notificação a partir do payload capturado
  (texto livre + `{{ variáveis }}` do payload, aninhado). Ícone fixo por perfil
  (URL ou emoji). O relay guarda o template e aplica; o app tem a lista de perfis +
  o editor com árvore do payload clique-pra-inserir e preview ao vivo.
  (`template.js`/`profiles` no relay; `MappingEditorView`/`ProfilesListView` no app.)
- **Notificações externas via webhook**: cada dispositivo tem um link próprio
  (`https://push.appzoi.com.br/w/<token>`) que recebe título, descrição, avatar
  e ação de clique, exibidos como card no notch. Relay próprio na VPS (Node/pm2
  atrás do nginx, TLS) + WebSocket que o Mac mantém aberto (reconecta sozinho,
  fila offline). Opt-in em Ajustes › Notificações externas (link + copiar +
  rotacionar + toggle de imagens remotas). Avatar remoto com guardas
  (só https, content-type de imagem, teto de tamanho, bloqueio de IP privado);
  clique abre só http/https. (`WebhookClient.swift`, `RemoteAvatarLoader.swift`,
  `WebhookKeychainStore.swift`, `WebhookSettingsView.swift`, `relay/`.)
- **AirPods no notch**: ao conectar, card transitório (~4s) com nome + bateria
  L / R / estojo; enquanto conectado, bateria no hover (faixinha junto da música,
  card dedicado quando não há música). Aviso de bateria baixa (≤10%) e toggle
  opt-out "AirPods no notch". (`AirPodsBattery.swift`, `BluetoothMonitor.swift` via
  `IOBluetooth` event-driven + `system_profiler` off-main.)
- `NSBluetoothAlwaysUsageDescription` no Info.plist (TCC exigia para o
  `system_profiler`/`IOBluetooth`).

## [0.2.2] - 2026-07-20

### Changed
- Progresso streaming do `--download-model` no `brew install`: stdout unbuffered
  (`setvbuf _IONBF`) + progresso por fase e monotônico (% no download,
  "compilando <modelo>…" na compilação CoreML). O install não fica mais mudo.
- Cask com `print_stderr: false` para esconder o ruído `[INFO]` do FluidAudio.

## [0.2.1] - 2026-07-20

### Fixed
- Crash determinístico do ditado em devices de formato de áudio estranho
  (Bluetooth/áudio virtual): `AVAudioEngine.installTap` lançava **NSException do
  ObjC**, que o `try/catch` do Swift não captura → `abort()`. Shim ObjC
  `ObjCException` converte a NSException em `Error`; `MicRecorder.start()` trata
  gracioso ("Sem acesso ao microfone") em vez de abortar.

## [0.2.0] - 2026-07-20

### Added
- Provisionamento do modelo de ditado no install: modo headless
  `Knobler --download-model` baixa o Parakeet (~461MB) para o cache do FluidAudio
  e sai, sem subir o `NSApp` (interceptado no topo de `KnoblerMain.main()`). Modo
  `--selfcheck`. O `postflight` do cask roda `--download-model` (best-effort;
  offline não quebra o install → fallback no launch). Primeiro ditado instantâneo.

## [0.1.0] - 2026-07-20

Primeira release pública (open-source), distribuída via Homebrew tap.

### Added
- **Now Playing** (Spotify/Apple Music): capa + visualizador no notch fechado;
  hover expande com controles, progresso e shuffle.
- **Visualizador com áudio real**: CoreAudio process tap no player + FFT em 5
  bandas, tingido pela cor da capa.
- **HUDs no notch**: volume, brilho e bateria substituem o OSD nativo.
- **Notificações do sistema** interceptadas e exibidas no notch.
- **Countdown de calendário**: próximo evento entra 15min antes com anel regressivo.
- **Ditado por voz** (FluidAudio/Parakeet) com formatação IA local opcional
  (Ollama/gemma3:4b) — remove fillers e conserta pontuação/acentos.
- **Pomodoro**, **shelf de capturas** com drag, **gestos**, **multi-monitor**.
- **API HTTP local** (`127.0.0.1:4477`): `/notify` e `/activity` — qualquer script
  publica no notch. CLI `tools/knobler` incluído.
- **Distribuição**: `tools/release.sh` (build → assina ad-hoc → zip → GitHub
  Release → bump do cask) + tap `homebrew-knobler` (cask com `postflight`/`zap`).
