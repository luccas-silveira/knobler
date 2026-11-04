# Relatório de verificação: mockup do WhatsApp no notch

Rodada final: **3** (de no máximo 3). As rodadas 1 e 2 foram a verificação própria. Depois veio uma revisão externa com 9 problemas (3 importantes e 6 menores). As correções entraram juntas e a rodada 3 conferiu. Os arquivos das rodadas 1 e 2 continuam na pasta.

- Mockup: `index.html`. É um HTML autocontido, com CSS e JS no próprio arquivo, sem build e sem recurso externo.
- Servido em `http://127.0.0.1:8771/index.html` com `python3 -m http.server 8771 --bind 127.0.0.1`. O servidor foi parado no fim.
- Tipo de tela: **Operar** (seção de app). Modo **direto**, dentro do design system do projeto. O `DESIGN.md` vence.

## O que a revisão apontou e como foi corrigido (rodada 3)

| # | gravidade | problema | correção | prova (rodada 3) |
|---|---|---|---|---|
| 1 | importante | A Marina chamava pelo nome real do dono do repo | Texto trocado para “Oi! Conseguiu ver as artes da campanha de Natal?”. `grep -i luccas index.html` não acha nada. | O texto renderizado do quadro B2 começa com “Oi! Conseguiu ver…”. Print `r3-1440-aba-b.png`. |
| 2 | importante | Corpo do notch 28 pt mais largo que no app, com as abas por fora | A moldura passou a ser a própria `NotchShape`: `clip-path: shape(...)` com as mesmas curvas quadráticas do `NotchShape.swift`. As abas ficam dentro da largura W, o corpo fica com W − 28 e o conteúdo é recortado pela forma, como no `.mask(shape)`. A sombra Float foi para um `filter: drop-shadow` no palco, porque o recorte cortaria uma `box-shadow`. Sem suporte a `shape()`, vale o `.nbg`, um corpo absoluto com `left/right: 14px` e abas em `left/right: 0`. CSS nas linhas 78–100. | Largura do preto medida em pixel, no print 1:1 de cada moldura: **430 → 402**, a 14 da borda; **780 → 752**; **360 → 331,5** (332 com o subpixel da posição); **380 → 352**. O conteúdo começa a 22 da borda da moldura, ou seja, a **8 pt do corpo**, e mede 386 na B. É o mesmo encaixe do `Snapshots/messages-online.png` (corpo de 402 pt, linhas a 8 pt). |
| 3 | importante | Cor da peça `#128C7E`, um verde perto do verde da LAN e fora das cores de sistema | `.indigo` do sistema (`#5E5CE6`, modo escuro) com o gradiente do `CardPeca` (`cor.gradient`): topo branco a 16% sobre a cor. O tile de Mensagens ganhou o mesmo gradiente. | O CSS computado da `.t-wa` dá `rgb(94,92,230)` com `linear-gradient(rgba(255,255,255,.16), transparent)`. Print `r3-1440-aba-v.png`. Matiz a ~110° do verde. |
| 4 | menor | Contagem da lista vazia: “Pessoal · 8292” mostrava 2 não lidas | O quadro “Lista vazia” marca como lidas as conversas da conta (`read: familia, rafa, mae`). A faixa passou a somar as não lidas das duas contas, em vez de usar um 7 fixo. | Texto renderizado: “ZOI Business · 4143 **5** Pessoal · 8292 Nenhuma conversa ainda…”, faixa **5**. |
| 5 | menor | Prévias alternativas fora da hora, e o separador “Hoje” na Mãe | As prévias alternativas viraram mensagens próprias, que chegam depois: Marina manda uma foto às 14:52 (`m9`) e Carlos um PDF v2 às 14:47 (`c3`). Abrir a conversa nesses quadros mostra a mensagem nova no fim. O separador de dia vem da fatia do quadro. Conversa aberta por clique usa o dia dela (`day: 'Ontem'` na Mãe), e trocar de conversa ou de conta zera `st.day`. | Linhas do quadro A2: “Marina Duarte 14:52 Foto 3”, “Carlos (Seller Veículos) 14:47 Proposta-Seller-nov26-v2.pdf 1”. A2 › Marina termina em “Prévia do carrossel 14:52” (`r3-interacao-alt-marina.png`). A0 › Pessoal › Mãe mostra “**Ontem** · Filho, chegou bem? 21:10…” (`r3-interacao-mae-ontem.png`). |
| 6 | menor | Faixa com `message-circle` e peça com balão e telefone | Um símbolo só (`i-wa`, que imita `phone.bubble.fill`) na faixa, no card de chegada, no vazio e no tile. O `message-circle` saiu do sprite. As legendas foram atualizadas. | `href` medido: faixa `#i-wa`, card `#i-wa`, tile `#i-wa`. |
| 7 | menor | Ícones da faixa em 11 px; no app são 9 pt | `.sb{font-size:9px}`, traço 2,4 para não sumir em 9 px. | `getComputedStyle(.sb).fontSize = 9px`. |
| 8 | menor | Conversa e card cerca de 2 pt acima das views atuais | **Igualado ao app**, para o plano não herdar duas escalas: bolha, nome no cabeçalho, nome e prévia da lista, campo, citação, documento, “mídia indisponível” e gravação em 10 px (`.footnote` / `.caption2`, `MessagesView.swift:56,75,106,132`). No card, nome 10 semibold e prévia 10 a 75% (`IncomingMessageView.swift:38,40,53`). Seletor de conta e “Marcar como lida” ficam em 11 (`.subheadline`, rótulo de controle no `DESIGN.md` §3). Os estados de conexão seguem o vazio da Agenda: mensagem 13, apoio 11. | Medido a 1440: `.bubble 10px 400`, `.ch-name 10px 600`, `.field input 10px`, `.row-name 10px 700` (não lida), `.row-prev 10px`, `.cm-name 10px`, `.cm-body 10px`. |
| 9 | menor | Não lidas em pílula branca cheia | A pílula agora usa Fill Strong (branco a 25%) com número branco bold, como os chips do `DESIGN.md`. O branco cheio ficou só no tique de lida, onde ele é a forma que distingue o estado. | `.count` computado: `rgba(255,255,255,.25)` / `rgb(255,255,255)`. Contraste no pior caso, a contagem sobre o seletor selecionado: **4,98:1**. |

Nenhuma das correções contrariou o `DESIGN.md`. A 8 foi para o lado do app, não para o lado da escala web.

## Como a verificação rodou (desvios do roteiro)

- **Playwright MCP indisponível de novo.** `browser_navigate` e `browser_close` falharam com `Browser is already in use for ~/.cache/claude-navegador`, porque outra sessão está com o perfil aberto. Os prints e as medições saíram do `playwright-core` (o do `@playwright/cli` global), num Chromium 156 headless e isolado. É o mesmo motor e são as mesmas larguras do VER-05. Os scripts ficam fora do repo, em `/tmp/wa-verif/` (`shots.mjs`, `extra.mjs`, `r3check.mjs`, `look.mjs`), e cada um fecha o seu navegador com `browser.close()`. O `browser_close` do MCP não tem navegador desta sessão para fechar.
- **Chrome DevTools MCP não está nesta sessão.** O CSS computado (VER-06/07) e o contraste (VER-12) foram lidos com `getComputedStyle` na página renderizada. O contraste compõe o `color` com alfa sobre cada `background-color` dos ancestrais até um fundo opaco, e o `.notch` conta como preto opaco. Com `shape()` o preto está mesmo no `.notch`, e o conteúdo fica dentro do corpo: 8 pt da borda medidos na B e na A, 6 no card e 10 na notificação.
- **Lighthouse, trace (VER-09) e rotação (VER-15):** não se aplicam a Operar.

## Escala e largura de 375 px

O notch é desenhado 1:1 em pontos (1 pt = 1 px CSS). Cada quadro fica num `.stage` com `overflow-x:auto`, e o topo da página tem dois modos:

- **Ajustar à largura** (o padrão): o JS aplica `zoom = min(1, largura do palco / largura do quadro)` no `.scaler`. Em 375, o quadro de 780 cai para cerca de 0,4 e o de 430 para cerca de 0,67. A página não rola de lado.
- **Tamanho real**: `zoom 1`. Quem rola de lado é o palco, dentro dele mesmo. Na rodada 3, em 375, a página deu `scrollWidth 375 = clientWidth 375` e o palco da B deu `scrollWidth 510` contra `clientWidth 343` (`r3-375-tamanho-real.png`).

`scrollWidth = clientWidth` foi medido nas 5 abas, em 375 e em 1440.

## Prints da rodada 3

- Obrigatórios: `r3-375.png` e `r3-1440.png`, a página inicial (aba Variante A) inteira.
- Por aba: `r3-375-aba-{a,b,c,e,v}.png` e `r3-1440-aba-{a,b,c,e,v}.png`.
- Estados provocados:
  - `r3-foco-teclado.png`: foco por Tab
  - `r3-interacao-abrir-rascunho.png`: abrir pela lista devolve o rascunho do Carlos
  - `r3-interacao-reagir-foco.png`: reação trocada pela barra e ações visíveis por foco
  - `r3-interacao-alt-marina.png`: a foto das 14:52 no fim da conversa
  - `r3-interacao-mae-ontem.png`: separador “Ontem” na Mãe
  - `r3-375-tamanho-real.png`
  - `r3-1440-reduced-motion-card.png`
- Detector: `r3-detector-375.json` e `r3-detector-1440.json`.
- Rodadas anteriores, mantidas: `r1-*` e `r2-*`.

## Piso, conferido por id (rodada 3)

| id | resultado | prova |
|---|---|---|
| SLOP-02 | passou | Nenhum texto em gradiente, nada de roxo→azul. Os únicos gradientes são o brilho de 16% no topo dos tiles, que reproduz o `Color.gradient` do `CardPeca`, e o recorte das abas no caminho sem `shape()`. |
| SLOP-37 | passou | Uma família só: SVG inline do Lucide com traço constante, imitando os SF Symbols. O WhatsApp tem um símbolo só em todo lugar (`i-wa`). Emoji só como conteúdo: as 6 reações e as figurinhas. |
| SLOP-10 | passou | Nenhuma grade de três cards iguais. A vitrine tem dois cards, como o `PluginsSettingsPane`. |
| SLOP-11 | passou | O notch é uma superfície só. A citação dentro da bolha é o padrão de conversa. Os cards da vitrine reproduzem a janela de Ajustes. |
| SLOP-22 | passou | Nenhum eyebrow. |
| SLOP-21 | passou | Nenhum rótulo em coluna ao lado de título. |
| SLOP-46 | passou | Nenhum nome real: o nome do dono saiu da mensagem da Marina (item 1). Contas, pessoas e números são fictícios. “Cerca de 160 s” do QR vem da spec. |
| SLOP-44 | passou | Sem vidro nem desfoque: preto absoluto. |
| SLOP-49 | passou | Verbos concretos: “Gerar outro”, “Tentar de novo”, “Marcar como lida”. |
| TIP-01 | passou | `-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui`, sem fonte importada. |
| TIP-12 | **refutado** | Dentro do notch o corpo é 10 px (`.footnote`) e os estados vão a 11 e 13, porque o `DESIGN.md` §3 manda (Body ~13px `.body` / ~10px `.footnote`, Label 9px) e porque a conversa LAN real usa `.footnote` (`MessagesView.swift:106`). A rodada 3 desceu a conversa de 12 para 10 justamente para casar com o app (item 8). A moldura da página, que é web, segue a regra: 15–16 px, entrelinha 1.5–1.55, 60ch. |
| TIP-20 | passou | h1 → h2 por aba → h3 por quadro. |
| TIP-21 | passou | Horas, contagens e durações com `tabular-nums`. Timer de gravação e duração de áudio em SF Mono (`--mono`). |
| TIP-22 | passou (n/a) | Nenhuma fonte web. |
| COR-02 | passou | Valores em tokens no `:root`, incluindo os novos `--tile-whatsapp`, `--tile-sheen`, `--ink-card` e `--shadow-float-filter`. Ficam de fora a largura de cada `.desk` (medida do quadro) e as cores das cenas SVG, que são conteúdo (Borrowed Color Rule). |
| COR-12 | passou (medido) | **0 textos abaixo de 4,5:1** em 1440, em todas as abas: A 135 textos, B 136, Card 43, Estados 49, Vitrine 24. O mínimo é **4,89:1**, a hora a 56% sobre a bolha enviada efetiva `rgb(56,56,56)`. Contagem sobre o seletor selecionado: 4,98:1. “desconectada”: 5,15:1. Placeholder “Responder…”: 5,22:1. ABRIR: 5,23:1. INSTALAR: 5,99:1. Moldura da página: 6,89:1. Ícones: ícone branco no tile índigo de 3,8:1 (topo do gradiente) a 5,1:1 (base), e no mínimo `.45` sobre preto, 4,4:1. |
| COR-13 | passou | No notch, anel `2px solid #fff` sobre preto (21:1). Na página, `2px solid #0a58ca` sobre `#ececef` (5,5:1). Print `r3-foco-teclado.png`. |
| COR-15 | passou | Só branco sobre os tiles e sobre a pílula INSTALAR. |
| COR-16 | passou | A entrega se lê pela forma: relógio, 1 tique, 2 tiques e 2 tiques numa cápsula branca, que agora é a única forma branca cheia do notch. Conta desconectada tem ícone e a palavra. Falha tem ícone e texto. Não lida tem negrito e número. A peça se distingue da LAN por ícone e por matiz. |
| COR-18 | passou | O notch é escuro por desenho e não tem modo claro. |
| LAY-03 | **refutado** | A escala é a nomeada do `DESIGN.md` (xs 6, sm 8, md 12, lg 14, xl 16), mais as medidas do código: 22 da borda da moldura (`NotchView.swift:169`, `width - 44`), que agora dá os 8 pt do corpo do app; 20 no card (`360 - 40`); 24 na notificação (`width - 48`); 5 de padding vertical na linha e na bolha (`MessagesView.swift:60,111`). |
| LAY-22 | passou (medido) | `scrollWidth = clientWidth` em 375 e 1440, nas 5 abas. |
| LAY-26 | **refutado** no notch, passou na página | O notch é app de mouse: o `iconeBotao` tem 28×22 pt (`NotchShell.swift:35`) e a faixa tem 22 pt. Os botões da moldura da página têm 44 px. |
| LAY-31 | passou | `--z-base`, `--z-raised` e `--z-pop`. O `.nbg` do caminho sem `shape()` usa `z-index:-1` dentro de `isolation:isolate`, local à moldura. |
| MOV-02 | passou | Quatro movimentos, todos de estado: a descida do card, o pulso do ponto de gravação, o spinner e a troca de aba. |
| MOV-03 | passou | Um momento autoral: a descida do card com overshoot. |
| MOV-05 | passou | Movimento só em `transform` e `opacity`. O `drop-shadow` do palco é estático. |
| MOV-09 | passou | Entrada em 240 ms e saída em 160 ms (67%). Abertura em 420 ms, contra o fecho de 0,30 do `DESIGN.md` (71%). |
| MOV-10 | **refutado** em parte | A UI comum entra com `cubic-bezier(0.16,1,0.3,1)`. A descida usa `--ease-open` (linha 28), porque o `DESIGN.md` §6 manda overshoot na abertura. |
| MOV-23 | passou (medido) | Com `reducedMotion: reduce`, o `.drop` vira `fadeOnly / ease-out` e o `.rec-dot` fica com `animation: none`. Print `r3-1440-reduced-motion-card.png`. |
| UX-01 | passou | Hover, `:active`, `:focus-visible` e `:disabled` declarados. Carregando, erro (envio, ponte, chave, QR expirado), sucesso (entregue, lida) e vazio. |
| UX-08 | passou | Ponte: o que falhou, que o app tenta sozinho e o comando com Copiar. Chave: o porquê e a saída. Envio: “não enviada · tentar de novo” embaixo da bolha. QR: “Gerar outro”. |
| UX-14 | **refutado** | Sem rótulo visível em “Mensagem” e “Responder…”, como no app (`MessagesView.swift:138`, `IncomingMessageView.swift:52`). O contexto é o cabeçalho da conversa e os ícones. O `aria-label` nomeia o destino. |
| UX-15 | passou | O erro de envio fica no lugar fixo, embaixo da bolha de origem. |
| UX-16 | passou (n/a) | Não há validação por tecla. |
| UX-26 | passou | Uma primária por estado. |
| UX-11 | passou | Cancelar citação, cancelar gravação e trocar reação executam na hora. |
| UX-12 | passou (n/a) | Nenhuma ação irreversível no escopo. |
| UX-20 | passou (medido) | Tab chega ao notch com anel visível. A seta para a direita troca de aba (medido: “Variante B”). As ações da bolha aparecem com `:focus-within`. Esc fecha a barra de reações e a citação. |

## Alarmes do detector (rodada 3) e refutações

Saída 2 nas duas larguras. Contagem:

| alarme | 375 | 1440 | o que foi feito |
|---|---|---|---|
| `undersized-ui-text` | 224 | 224 | refutado |
| `bounce-easing` | 7 | 7 | refutado |
| `monotonous-spacing` | 1 | 1 | refutado |
| `pulsing-dot` | 1 | 1 | refutado |
| `cramped-padding` | 2 | 0 | refutado |
| `low-contrast` | 0 | 0 | ver nota |

- **`low-contrast`, nota.** Na primeira passada da rodada 3, o preto estava só num irmão `.nbg`, atrás do conteúdo. O detector sobe pelos ancestrais, não achava o preto e deu 4 alarmes em 375 e 5 em 1440, comparando texto branco com o cinza do palco. Em vez de refutar, a forma passou a ser o `clip-path: shape()` com o preto no próprio `.notch`. Na passada final, `low-contrast` deu 0 nas duas larguras. As razões medidas estão no COR-12.
- **`undersized-ui-text`** (de 104 para 224). A alta é efeito direto do item 8: a conversa e o card desceram de 11–12 para 10 px, para casar com o app. Refutado pelo `DESIGN.md` §3, que vence: Body ~10px `.footnote`, Label 9px. O app real usa `.footnote` na conversa LAN (`MessagesView.swift:56,75,106,132`) e no card (`IncomingMessageView.swift:38,53`). São pontos de macOS desenhados em Retina 2×. Todos esses textos ficaram acima de 4,5:1 (mínimo 4,89).
- **`bounce-easing`** `cubic-bezier(0.34,1.36,0.64,1)` nos 7 `.drop` (linha 306, token `--ease-open` na linha 28). Refutado pelo `DESIGN.md` §6: “overshoot na abertura (`spring response 0.42, damping 0.76`)”. Em movimento reduzido vira fade (medido).
- **`pulsing-dot`** `.rec-dot` (linha 249). Refutado: é o “ponto pulsante de gravação de mic” do `DESIGN.md` §2 (Recording Red, 8 pt como `NotchView.swift:387`). Em movimento reduzido fica com `animation: none` (medido).
- **`monotonous-spacing`** (~4 px em 73%). Refutado: 4 pt é o espaçamento entre bolhas do app (`MessagesView.swift:82`, `VStack(spacing: 4)`). Os outros ritmos (6, 8, 12) estão no seletor, na lista e no compositor.
- **`cramped-padding` em `.recbox` e `.field`** (só em 375). Refutado pelo CSS: os dois têm `height:26px` com `align-items:center` (linhas 236 e 248). Com 10 px de texto sobram cerca de 8 px acima e abaixo. É o desenho do `TextField` com `.padding(.vertical, 5)` (`MessagesView.swift:140`). No print, o texto não encosta na borda (`r3-1440-aba-a.png`, quadros 3 e 5).
- Na rodada 2 havia também um `repeated-container-text`. Na rodada 3 ele não voltou.

## Console

Rodada 3: zero erros e zero avisos, nas duas larguras, nas 5 abas e nas interações: abrir conversa, trocar de conta, reagir, marcar como lida, tentar de novo, trocar de escala e movimento reduzido.

## Respostas deduzidas (modo direto)

- **Tipo de tela:** Operar, sem Lighthouse e sem rotação.
- **Direção:** a do `DESIGN.md`, sem catálogo.
- **Botões:** VARIACAO 2, MOVIMENTO 3, DENSIDADE 6.
- **Medidas:**
  - Variante A: moldura de 780 × 452 pt, corpo de 752, conteúdo de 736 (260 da lista + o resto).
  - Variante B: moldura de 430 × 364 pt, corpo de 402, conteúdo de 386 × 272 (`NotchMetrics.alturaDaSecao(.mensagens)`).
  - Card de chegada: moldura de 360, corpo de 332, conteúdo de 320.
  - Notificação comum: moldura de 380 × 88, corpo de 352, conteúdo de 332.
  - Topo de 32 pt e faixa de 22 pt.
- **Forma:** a `NotchShape` desenhada com as mesmas curvas quadráticas (`clip-path: shape()`). As abas ficam dentro da largura e o conteúdo é recortado pela forma.
- **Tipografia:** a das views atuais. Conversa e card em 10 pt (`.footnote` / `.caption2`), controles em 11 (`.subheadline`), estados em 13 e 11.
- **Bolhas:** recebida com branco a 10%, enviada com branco a 22%. Cantos de 8, mídia com cantos de 6.
- **Não lidas:** número branco bold numa cápsula Fill Strong (25%), no seletor e na lista. Na faixa, a `contagem()` de 7 pt do app, com a soma das duas contas.
- **Falha de envio:** laranja de estado, igual ao “não entregue” da LAN.
- **Lida:** dois tiques pretos numa cápsula branca. É a única forma branca cheia.
- **Ícone da seção:** `phone.bubble.fill` (balão redondo com telefone), o mesmo na faixa, no card de chegada, no vazio e no tile. A LAN fica com `bubble.left.and.bubble.right.fill`.
- **Cor da peça:** `.indigo` com `.gradient`. Todas as cores de sistema já estão em uso no `corDaPeca`. O índigo hoje é de Descanso, uma peça que não tem nada de conversa, e fica a cerca de 110° do verde de Mensagens. O verde-petróleo da marca WhatsApp foi descartado: ficava entre o `.mint` (Conversão) e o `.teal` (Espelho) e era lido como verde.
- **Fila atrás do card:** o app não tem indicador de fila, então nada foi inventado. O mockup mostra a sequência.
- **Placeholder “Mensagem”:** sem rótulo visível, como no app (UX-14).

## Pendências

- **`phone.bubble.fill` no target.** O símbolo existe no macOS 27 desta máquina. Falta confirmar que existe no macOS 14.2 antes de usar sem `if #available`, e decidir o glifo de reserva.
- **Contraste da pílula INSTALAR no app real.** O app usa `Color.accentColor`, e `#0A84FF` com branco 11 pt bold dá 3,6:1. O mockup usa `#0060c8` (5,99:1). É achado do app existente, fora desta feature.
- **Contraste do tile de Mensagens (LAN).** Ícone branco sobre `.green` dá cerca de 1,9:1. É cor de fábrica do app e o mockup reproduz como está.
- **`clip-path: shape()`** exige Chromium 135+ ou Safari 18.4+. Fora disso o mockup cai no `.nbg`, que tem o mesmo corpo de W − 28 com abas em gradiente radial. Vale só para o HTML. No app, a forma é a `NotchShape`.
