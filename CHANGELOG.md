# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/);
versionamento por [Semantic Versioning](https://semver.org/lang/pt-BR/).
Regras de bump em [VERSIONING.md](VERSIONING.md).

## [Unreleased]

## [0.22.0] - 2026-08-04

### Added
- **Foco do card entre reinícios**: a seção onde você deixou o card (Música,
  Mensagens, Nota…) volta na primeira abertura depois de reiniciar o app. Se a
  seção salva ainda não tiver conteúdo, o pedido espera em vez de abrir o card no
  vazio — e digitar na nota ou clicar na faixa continua vencendo a restauração.
- **Filtros no template do webhook** (relay): `{{caminho | semHifens}}`,
  `{{caminho | data}}` e `{{caminho | quill}}` — um filtro por token, sem
  encadeamento. Filtro desconhecido ou inaplicável devolve o valor cru.
  `GET /profiles/:id` passa a devolver `lastPayloadAt` e `payloadCount`
  (aditivo). Os testes herméticos do relay entraram em `tools/check.sh`.
- **Receitas de webhook no app**: quatro caminhos prontos (GoHighLevel por app do
  Marketplace ou por ação Webhook num workflow; ClickUp por webhook de API ou por
  automação "Call webhook"), cada um com instrução de onde colar o link,
  ressalva, payload de exemplo e mapa sugerido. Ainda não aparecem na tela — o
  assistente que os usa vem na sequência.
- **Assistente de perfil de webhook**: "Adicionar perfil" abre um assistente de
  cinco passos (Nome → Serviço → Link → Primeiro envio → Mapa). O passo Serviço
  lista os quatro caminhos prontos (ou "Outro serviço (sem preset)"), o passo
  Link traz a instrução e a ressalva do caminho escolhido, o Primeiro envio
  espera o webhook chegar de verdade e o Mapa já é o editor, com os campos
  semeados pela receita. Fechar no meio não perde nada: o perfil fica esperando
  e a linha dele no painel retoma de onde parou.
- **Colar JSON de exemplo**: dá pra montar o mapa sem esperar webhook nenhum —
  um clique lê o JSON que estiver copiado e monta a árvore. O exemplo é só local
  (some ao fechar) e vem marcado por uma faixa; quando o payload de verdade
  chega, ele troca o exemplo sozinho e avisa. Clipboard que não é JSON vira
  aviso inline com o começo do que foi lido, sem mexer na árvore que já estava
  na tela. Botão no estado vazio do editor e no passo Primeiro envio do
  assistente.
- **Auto-mapeamento dos campos**: quando a árvore do payload aparece (webhook de
  verdade ou JSON colado), os campos que estiverem **vazios** são preenchidos
  sozinhos — primeiro pela receita do serviço, depois por um chute a partir dos
  nomes de chave (`title`/`name`/`full_name` viram título, `text_content` vira
  corpo, e por aí). Campo que você já escreveu nunca é sobrescrito, o ícone
  nunca é chutado, e um aviso não-bloqueante no topo oferece "Limpar sugestões".
  Payload que não dá pra reconhecer deixa os campos vazios e convida a clicar na
  árvore.

### Changed
- **Doc de notificações externas reescrito**: `docs/webhooks.md` passa a começar
  pelo assistente como porta única (os cinco passos e o escape "Outro serviço
  (sem preset)"), com seções novas de Presets (o que é, por que o mesmo serviço
  aparece por caminho, reaplicar é manual) e de Filtros no template (os três,
  um exemplo cada, falha suave). Imagens do painel e do editor recapturadas e
  uma do passo Serviço criada.
- A linha do perfil de webhook mostra estado em vez de "Campos mapeados":
  "Esperando o primeiro envio" / "Sem mapa — último webhook há 3 min" /
  "Último webhook há 3 min". Clicar nela retoma a configuração.
- O motor de prévia do mapeamento saiu de dentro da tela para
  `WebhookTemplate.swift` e ganhou os mesmos três filtros do relay, com gate que
  repete os casos de lá.

## [0.21.0] - 2026-08-04

### Added
- **Silenciar durante chamadas**: com a opção ligada (Ajustes → Notch →
  Silenciar), notificação de app, API, webhook e avisos param de virar card
  enquanto algum app estiver usando o microfone há mais de 20 s — pega a call que
  não está no calendário. Nada se perde: vai pro Histórico, igual ao silêncio de
  reuniões. Opt-in, sem permissão nova.
  Ver [`docs/notifications.md`](docs/notifications.md).
- `GET /status` passa a expor `silenciando`, indicando se a próxima notificação
  vira card ou vai direto pro histórico.
- **Seção Anotação no card**: ferramentas, cores, desfazer/refazer, apagar e os
  quadros branco/negro viraram uma página do notch, com botão pra ligar e
  desligar o desenho. O card fica acima do overlay, então dá pra trocar de
  ferramenta sem sair — e ele abre direto nessa seção enquanto você desenha.
  Ver [`docs/annotation.md`](docs/annotation.md).
- **Atalhos de anotação** no mapa do DemoPro enquanto o overlay está ligado:
  `'` texto, `S` livre, `Q` linha, `A` seta, `Z` retângulo, `E` elipse,
  `L` laser, `H` holofote, `B` borracha, `U` desfazer, `R` refazer,
  `X` apagar, `W` quadro branco, `K` quadro negro.
- **Painel Desenho nos Ajustes**: painel próprio na sidebar, com o modo do
  Control esquerdo, o quadro de fundo, o auto-fade e a tabela de atalhos — que
  antes viviam espremidos em Ajustes → Notch.
  Ver [`docs/annotation.md`](docs/annotation.md).
- **Padrões do traço**: ferramenta, cor e **espessura** (1–24 pt, era fixa em 6)
  agora são configuráveis e sobrevivem ao relançamento. A seção Anotação do card
  continua mudando o traço da sessão; o painel define com o que ele nasce.
- `GET /status` passa a expor `annotation.tool`, `annotation.background` e
  `annotation.lineWidth`.

### Changed
- **Anotação de tela**: o atalho passa a ser o **Control esquerdo** (era o
  direito) — teclados sem a tecla da direita deixavam o recurso inacessível.
  A tecla agora liga só o desenho: soltar o Control **não** apaga nem esconde
  o que já foi desenhado, que fica na tela (sem bloquear cliques) até
  "Apagar tudo". Ver [`docs/annotation.md`](docs/annotation.md).

### Removed
- Os itens de anotação do menu da barra (ferramenta, cor, fundo, desfazer,
  apagar e "Anotar na tela"): tudo isso agora mora na seção Anotação do card.

## [0.20.0] - 2026-08-03

### Added
- **Avisos do desenvolvedor**: novidades e recados sobre o Knobler chegam como
  card no notch. O app lê um JSON público do repositório uma vez por dia — sem
  servidor, sem identificador do Mac na requisição, sem canal de volta. Cada
  aviso aparece uma vez só e respeita "silenciar durante reuniões". Desliga em
  Ajustes → Geral; avisos **críticos** (segurança, falha que perde dado)
  continuam chegando mesmo desligado, e o rótulo do interruptor diz isso.
  Ver [`docs/avisos.md`](docs/avisos.md).

## [0.19.0] - 2026-08-03

### Added
- **Janela de boas-vindas na primeira abertura**: dois passos informativos —
  onde o app vive (notch + ícone da barra de menus, sem Dock nem janela) e os
  dois atalhos globais (⌥ direita pro ditado, Control direito pra anotação).
  Cada passo é versionado: quem já usava o Knobler vê só o dos atalhos, e uma
  versão futura com passo novo mostra só o que é novo. Reabre pelo menu da
  barra → **Boas-vindas…**. Ver [`docs/onboarding.md`](docs/onboarding.md).
- **Próximo evento durante o Pomodoro**: o card de foco ganha uma linha com o
  título do evento e quanto falta ("Retrospectiva em 12 min"), e nos últimos
  5 minutos a pílula fechada troca o timer pelo aviso. Antes o countdown do
  calendário sumia justamente durante o foco, porque o Pomodoro suprime a seção
  de atividade. Respeita o mesmo interruptor de sempre (Ajustes → Notch); sem
  evento à vista, nada muda.

### Fixed
- **Calendário não pede permissão no launch**: o balão do EventKit subia na
  abertura — por cima da janela de boas-vindas, e contra a regra de pedir no
  primeiro uso. Quem pede agora é o painel Permissões; o countdown fica quieto
  até a concessão e liga sozinho quando ela chega, sem reabrir o app.
- **Rede local agora aparece como concedida sem depender de outro Mac**: a prova
  era achar um peer, então quem estava sozinho na rede ficava para sempre em
  "ainda não usada". O próprio serviço anunciado já basta — sem a permissão o
  Bonjour não devolve nada.
- **Botão "Verificar" nas permissões sem status**: Rede local e Arquivos e
  pastas ganham um botão que usa a permissão de leve (liga o Bonjour, lê a Mesa)
  e resolve o estado na hora, em vez de esperar o recurso rodar por acaso.
- **Permissão sem status não parece mais defeito**: Rede local, Arquivos e
  Gravação de áudio do sistema não têm API de consulta no macOS; o painel agora
  diz "Sem status até usar" em vez de "Ainda não usada".
- **Evento do calendário não disputa mais o card com o Pomodoro**: com o timer
  ativo, o mesmo evento aparecia duas vezes (anel de atividade + card) e a seção
  de atividade, que se atualiza a cada 30 s, subia ao topo sem parar — o
  Pomodoro nunca ficava na frente. Agora a atividade do calendário fica calada
  enquanto o Pomodoro está na tela, onde o evento já é mostrado.

### Changed
- **Acessibilidade deixa de ser pedida no launch**: quem pede agora é o painel
  Permissões, que abre depois da janela de boas-vindas — antes o balão do
  sistema e a janela do app disputavam o foco na primeira abertura. Concedida a
  permissão, ditado e notificações religam em poucos segundos, sem reabrir o app.
- **Pergunta do agente não trunca mais**: expandido, resumo e detalhes moram no
  mesmo bloco rolável — antes o resumo era cortado em 160 caracteres e duas
  linhas mesmo com o card aberto. "Ver tudo" aparece agora também quando só o
  resumo é comprido, sem detalhes anexos.

## [0.18.1] - 2026-08-03

### Added
- **Apagar o histórico**: cada linha ganha um `X` no hover e o topo da seção
  ganha "Limpar". Antes só a poda de 24 h tirava algo da lista.

### Changed
- **Nota rápida não esconde mais a faixa de seções**: o rascunho deixou de ser
  modo exclusivo — dá pra pular pra outra seção pelo rodapé sem perder o texto.
- **Zona de escrita da nota** ganhou um fundo um tom acima do card, pra separar
  o campo da moldura preta.

### Fixed
- **Player descentralizado**: o trio anterior/play/próxima agora fica no centro
  do card; o shuffle virou sobreposição à esquerda em vez de empurrar a fila.
- **Clique na faixa durante a nota** era desfeito pelo recálculo de seções, que
  puxava o foco de volta pro campo.
- **Espelho sem câmera** ficava em "Ligando a câmera…" pra sempre; agora mostra
  "Câmera indisponível" quando abrir o dispositivo falha (sem webcam, USB fora,
  câmera tomada por outro app). `GET /status` ganhou `mirrorFailed`.
- **Rodapé do painel de Permissões** dizia que toda permissão é pedida no
  primeiro uso — a acessibilidade é pedida na abertura.
- **`X` do histórico** podia ficar aceso quando o ponteiro saía da lista por um
  canto.

## [0.18.0] - 2026-08-03

### Added
- **Barra de endereço no preview de link**: sem página aberta, a seção Link
  mostra um campo já focado — cole (⌘V) e tecle Enter. Antes só arrastar um
  link do navegador abria uma página. Aceita `exemplo.com` sem esquema.

### Changed
- **Espelho fixado liga sozinho**: abrir a aba do espelho no card já acende a
  câmera, em vez de esperar o clique no botão.
- **Player sem o ícone de câmera**: a fila de controles voltou a ser só mídia
  (shuffle · anterior · play/pause · próxima), e o estado "Nada tocando" também
  perdeu o botão do espelho.
- **Espelho avisa que está ligando**: enquanto a sessão da câmera não sobe, o
  preview mostra um spinner com "Ligando a câmera…" em vez de um retângulo preto.

### Fixed
- **Abrir o espelho congelava o card por ~1 s**: a entrada de vídeo era criada
  na main thread. A sessão agora sobe vazia e recebe a câmera em background.

## [0.17.0] - 2026-08-03

### Added
- **Seções fixadas**: o alfinete em Ajustes › Notch mantém uma seção no card aberto
  mesmo sem conteúdo.
- **Painel de Permissões na primeira abertura**: o app roda como agente, sem
  janela nem ícone no Dock, então quem instalava não tinha de onde partir pra
  achar as permissões. Agora o painel se apresenta sozinho uma vez.
- **Diagnóstico de instalação**: o painel detecta app translocado pelo
  Gatekeeper, rodando de fora de `/Applications` ou ainda em quarentena — os
  estados em que o macOS descarta a concessão e o Knobler **não aparece** na
  lista do Ajustes do Sistema. Mostra a causa, o passo de correção, e reaparece
  a cada abertura enquanto durar.
- **Conceder sem sair do app**: botão *Permitir* nas linhas de Acessibilidade,
  Microfone, Câmera e Calendários abre o balão do sistema direto no painel, em
  vez de mandar o usuário pro Ajustes do Sistema. Só enquanto o macOS ainda
  aceita o pedido — depois de negada, o balão não aparece mais e o *Abrir*
  continua ao lado.
- **Saída manual quando o app não está na lista**: botão *Revelar o Knobler no
  Finder*, pra arrastar pro **+** do Ajustes do Sistema.
- **`Knobler --permissoes`**: relatório headless com o estado das oito
  permissões e o caminho do bundle, pra suporte remoto.

### Changed
- **Foco inicial do card**: passa a ser a primeira seção **com conteúdo**, e não
  a primeira da lista — sem isso, fixar a Música faria o card abrir em "Nada
  tocando" toda vez.
- **Nota rápida**: o swipe horizontal agora sai da nota como sai de qualquer
  outra seção, sem encerrá-la — o texto continua lá quando você volta. E o
  card deixou de ficar congelado enquanto o campo está focado: com o mouse
  fora, ele encolhe depois de 3 segundos.

### Fixed
- **Nota rápida fixada**: com a seção fixada nos Ajustes, o campo aparecia sem
  a nota estar ligada e não aceitava teclado. Entrar na seção agora liga a nota
  na tela em que você está.

## [0.16.2] - 2026-07-31

### Fixed
- **Ativação da anotação de tela**: o atalho Control direito agora recupera o
  event tap depois que a permissão de Acessibilidade é concedida, sem exigir
  reiniciar o app.

## [0.16.1] - 2026-07-31

### Added
- **Anotação de tela inteira** inspirada no DemoPro: desenho livre, linhas,
  setas, retângulos, elipses, texto, laser, holofote, borracha, undo/redo,
  auto-fade, quadros transparente/branco/negro e persistência por monitor.
  O atalho padrão é o Control direito, com modo Pressionar e Segurar ou
  Alternar configurável.

## [0.16.0] - 2026-07-30

### Added
- **Preview da conversão do shelf**: escolher um destino no menu "Converter" não
  grava mais nada de imediato. A prateleira entra em modo preview e mostra o que
  vai sair — miniatura do resultado, tamanho antes/depois e dimensão — com
  presets de **Qualidade** (Alta/Média/Baixa, em JPEG e HEIC) e **Tamanho**
  (100%/50%/25%, em imagem, PDF→PNG e vídeo). Trocar um preset reconverte na
  hora. **Salvar** move pra junto do original; **Descartar** apaga sem deixar
  rastro. Antes a conversão gravava às cegas: sem ver o resultado, sem escolher
  qualidade, e com um arquivo pra apagar na mão quando não prestava.
- PDF com várias páginas agora converte **todas** — o card avisa quantas e
  Salvar grava o conjunto ao lado do original (só a primeira entra na
  prateleira, pra não estourar a capacidade de 8 itens).

- **Silenciar durante reuniões** (Ajustes › Notch, opt-in): enquanto um evento
  do calendário com link de call está em curso, notificação de app, da API local
  e de webhook vai direto pro Histórico em vez de virar card. Lembretes,
  Pomodoro e perguntas do Claude continuam aparecendo — são coisas que você
  agendou, não ruído. Evento sem link de call e evento de dia inteiro não
  silenciam nada.
- **Estado do AirDrop no notch**: enviar pelo shelf mostra uma atividade
  "Enviando por AirDrop" e um card 📤 no fim. Desistir na janela do sistema não
  mostra nada. A atividade é indeterminada porque `NSSharingService` não expõe
  bytes transferidos — limite da plataforma, não simplificação.
- **↗ Enviar por AirDrop…** no menu da barra, com seletor de arquivo: mandar
  algo não obriga mais a arrastá-lo pra prateleira antes.
- **Preview de link no card**: arrastar um link do navegador pro notch abre a
  página **dentro do card**, numa seção nova (Link). Sem janela e sem barra de
  navegador. A página é renderizada numa viewport de 1280 px CSS e encolhida por
  zoom, pra manter o layout de desktop em vez de cair no breakpoint mobile; o
  card fica 16:9 (736×414) e não tem rolagem horizontal. O card não recolhe
  enquanto o link está aberto e o scroll vertical é da página — as mesmas
  mecânicas que a nota rápida e o histórico já usavam.
- **Arrastar texto pro notch**: um trecho selecionado vira um `.txt` nomeado
  pela primeira linha, em `~/Library/Application Support/Knobler/Arrastados/`,
  e entra na prateleira como item normal.

- **Teclado no preview de link**: a seção Link aceita digitação, com ⌘C/⌘V/⌘X/⌘A.
  Dá pra buscar, logar e preencher formulário sem sair do card. Como o app não
  tem barra de menus, os atalhos de edição passam por um monitor próprio, ativo
  só com o preview aberto. Esc fecha.
- **Histórico de notificações sobrevive ao restart**: gravado em
  `~/Library/Application Support/Knobler/notificationHistory.json` e recarregado
  já podado pela janela de 24 h. Virou necessário quando o silêncio em reunião
  passou a mandar notificação só pro histórico — um restart no meio da reunião
  apagava a única cópia dela. Os botões espelhados (Aceitar/Recusar, Adiar) não
  voltam do disco: apontam pra elementos vivos do alerta original, e botão que
  não faz nada é pior que botão nenhum.

### Changed
- Conversão de vídeo perdeu a faixa de atividade do notch: o progresso agora
  aparece no próprio card do preview. Em 100% ela continua saindo por remux
  instantâneo; abaixo disso reescala via `AVMutableVideoComposition`.

## [0.15.0] - 2026-07-29

### Added
- **Bluetooth entra no painel de Permissões**: o app usava oito permissões e o
  painel listava sete — a do Bluetooth, que o monitor dos AirPods pede logo na
  abertura, não tinha linha nem estado. Agora tem, com o botão **Abrir** pro
  painel certo do Ajustes do Sistema. O estado sai do `CBManager.authorization`:
  quem pede é o IOBluetooth, mas os dois batem no mesmo registro do TCC e só o
  CoreBluetooth expõe o estado sem instanciar nada.

### Fixed
- **`docs/settings.md` dizia que a Acessibilidade era a única permissão pedida
  na abertura** — o Bluetooth também é, desde que **AirPods no notch** esteja
  ligado (o padrão). Era a mesma premissa errada que manteve a chave do
  Bluetooth fora do `Info.plist` até a v0.13.1.
- **O anel do Pomodoro na faixa podia discordar do relógio do card**: a fatia
  lia os minutos crus dos Ajustes e o engine lia os mesmos minutos com clamp
  mínimo de 1. Com uma fase configurada em 0, o relógio contava 1 min e o anel
  não desenhava. Os dois passaram a sair do mesmo `pomodoroConfig`.

## [0.14.0] - 2026-07-29

### Changed
- **Card do notch mostra uma coisa de cada vez**: em vez de empilhar música,
  atividade, prateleira e Pomodoro numa ordem fixa, o card agora mostra uma
  seção em foco e deixa as outras como ícones no rodapé, cada uma com um sinal
  vivo (anel de progresso, contagem, ponto de tocando). A ordem em repouso é
  sua — arrastável nos Ajustes › Notch — e o que acabou de acontecer sobe
  sozinho por alguns segundos. Clicar num ícone (ou deslizar na horizontal)
  trava o foco até o notch recolher. A cortina do histórico e as abas saíram:
  histórico e Mensagens viraram seções como as outras.
- **`GET /status` diz qual seção o card está mostrando**: cada entrada de
  `notches` ganhou o campo `focus` (`musica`, `atividade`, `pomodoro`, `shelf`,
  `espelho`, `mensagens`, `historico`, `nota`, ou vazio).
- **Ícone do app e da barra viraram a marca do site**: a silhueta do notch
  (mesma geometria de `NotchShape`) substitui o ícone antigo e o caractere
  `◐` que fazia as vezes de ícone na barra de menus. O da barra é template —
  acompanha claro/escuro e o realce do menu aberto. O `.icns` é gerado por
  `tools/makeicon.swift`, direto do vetor, e o favicon do site (que ainda era
  o padrão do Astro) passou a ser a mesma marca.

### Fixed
- **Clicar num card de mensagem com o notch já aberto vai pra Mensagens**: o
  pedido de foco só era atendido quando o card precisava abrir. Com o card já
  na tela o clique não fazia nada — e o pedido ficava guardado, roubando a
  abertura seguinte pra uma seção que ninguém tinha pedido e travando o foco
  até o notch recolher.
- **O ícone do Pomodoro na faixa ganhou o anel do tempo restante da fase**,
  como o da atividade já tinha. Antes saía chapado.
- **O scroll de dois dedos responde nas bordas do card aberto**: a zona do
  gesto era 2 pt mais estreita que o card, então uma tira de 1 pt de cada lado
  reagia ao ponteiro mas não à rolagem.

### Removed
- **O atalho direto pro histórico saiu**: o puxão longo de dois dedos (a mesma
  passada que abria o card e seguia até ~120 pt) levava ao histórico em um
  gesto só. Com a cortina aposentada, chegar lá custa um passo a mais — abrir o
  card e clicar no sino da faixa, ou deslizar na horizontal até ele. É perda de
  conveniência assumida: o histórico virou uma seção como as outras, e um gesto
  exclusivo pra uma seção não se sustentava.

## [0.13.2] - 2026-07-29

### Fixed
- **Conversa abre na mensagem mais recente**: a lista nascia no topo, no
  histórico mais antigo, e obrigava a rolar até o fim pra ver o que tinha
  acabado de chegar. Agora abre embaixo e segue colada quando chega mensagem
  nova.

## [0.13.1] - 2026-07-29

### Added
- **Nota rápida, avisos nas duas pontas**: o campo vazio ganhou o placeholder
  "Rascunho — some ao desligar" (o único lugar onde cabia dizer que o texto é
  efêmero), e o notch fechado ganhou um pontinho de 4 pt na asa direita
  enquanto houver texto guardado — antes dava pra fechar o card, esquecer, e
  desligar achando que o campo estava vazio.

### Fixed
- **Abertura em Mac novo**: o app morria no launch em qualquer máquina que ainda
  não tivesse concedido Bluetooth. O `BluetoothMonitor` registra notificação de
  conexão dos AirPods, o TCC pede a permissão, e sem
  `NSBluetoothAlwaysUsageDescription` no `Info.plist` o processo é abortado no
  ato. Não aparecia em quem já tinha a permissão gravada — só em instalação
  limpa.
- **Nota rápida, teclado no meio da frase**: com o campo focado, notificação e
  HUD deixaram de tomar o card. Antes eles tiravam o campo da tela, o painel
  largava a janela chave e as teclas seguintes iam pro app da frente sem aviso
  nenhum. A notificação agora espera na fila e aparece quando você solta o
  campo (Esc, clique fora ou desligar o interruptor); o HUD de volume/brilho
  fica de fora enquanto você digita. Ditado e mensagem recebida continuam
  passando na frente.
- **Nota rápida, texto apagado sem volta**: ao desligar, o texto vai pro
  clipboard antes de ser apagado — cola com ⌘V se foi sem querer. Vale pros
  três caminhos de perda (o interruptor do menu, desconectar o monitor dono e
  sair do Knobler). Nota vazia, ou só com espaço e enter, não mexe no que você
  tinha copiado.
- **Nota rápida, barra de rolagem dentro do card**: quem usa "Mostrar barras de
  rolagem: sempre" via um scroller cinza do sistema parado dentro do notch, com
  o campo até vazio. Sumiu. E o placeholder estava 8 pt abaixo de onde a
  primeira letra digitada nasce — pulava na primeira tecla; agora os dois saem
  do mesmo ponto.
- **Nota rápida, controle que não fazia nada**: com a nota aberta, os
  pontinhos de página saíram do rodapé e o swipe horizontal deixou de trocar de
  aba. Os dois mexiam em `tab` por baixo do campo, então o ponto de Mensagens
  acendia numa tela que seguia mostrando a nota, e a troca só aparecia no
  hover-out. Com o card fechado o swipe segue pulando faixa.

## [0.13.0] - 2026-07-29

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
