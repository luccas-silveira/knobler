---
name: Knobler
description: Dynamic Island nativa para o notch do Mac — preta, silenciosa, tingida pelo conteúdo.
colors:
  notch-black: "#000000"
  ink: "#FFFFFF"
  ink-secondary: "#FFFFFFD9"
  ink-tertiary: "#FFFFFF99"
  ink-muted: "#FFFFFF73"
  ink-faint: "#FFFFFF4D"
  fill-strong: "#FFFFFF40"
  fill: "#FFFFFF26"
  fill-subtle: "#FFFFFF14"
  fill-faint: "#FFFFFF0F"
  recording-red: "#FF3B30"
  charging-yellow: "#FFCC00"
  low-battery-orange: "#FF9500"
typography:
  display:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "22px"
    fontWeight: 400
    lineHeight: 1.1
  headline:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "13px"
    fontWeight: 700
    lineHeight: 1.2
  title:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "15px"
    fontWeight: 600
    lineHeight: 1.2
  body:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.3
  label:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "9px"
    fontWeight: 500
    lineHeight: 1
    letterSpacing: "0.02em"
rounded:
  notch-top-compact: "6px"
  notch-top-open: "14px"
  notch-bottom-compact: "12px"
  notch-bottom-open: "30px"
  inner-sm: "5px"
  inner-md: "7px"
  inner-lg: "8px"
  inner-preview: "12px"
spacing:
  xs: "6px"
  sm: "8px"
  md: "12px"
  lg: "14px"
  xl: "16px"
components:
  notch-surface:
    backgroundColor: "{colors.notch-black}"
    textColor: "{colors.ink}"
    rounded: "{rounded.notch-bottom-open}"
  hud-track:
    backgroundColor: "{colors.fill-strong}"
    height: "6px"
  option-chip:
    backgroundColor: "{colors.fill-subtle}"
    textColor: "{colors.ink}"
    rounded: "{rounded.inner-lg}"
    padding: "8px 12px"
  option-chip-hover:
    backgroundColor: "{colors.fill}"
  thumbnail:
    rounded: "{rounded.inner-md}"
---

# Design System: Knobler

## 1. Overview

**Creative North Star: "The Living Second Notch"**

O notch de software é uma continuação do notch físico — mesmo preto, mesma
curva, mesmo silêncio — mas ele respira. Reage à música, a gestos e a status,
e depois derrete de volta no bisel quando não tem nada a dizer. A ilusão de
que é uma peça só de hardware é o produto; a vida vem por dentro, nunca por
decoração. Você não deveria conseguir apontar onde o alumínio termina e o
pixel começa.

A densidade é mínima por design. Uma informação por vez, ancorada no topo,
crescendo de dentro do notch como a Dynamic Island do iPhone. A superfície é
preta absoluta (`#000000`) — não cinza-escuro, não translúcida — para casar com
o bisel real do MacBook. Sobre esse preto, toda a hierarquia é construída com
branco em camadas de opacidade (85% → 6%), nunca com uma segunda cor de fundo. A
única cor "de verdade" que entra é a extraída da capa do álbum, e mesmo assim
só tinge o visualizador — o conteúdo empresta a cor, o sistema não a impõe.

Este sistema rejeita explicitamente: o visual de widget/gadget de terceiro
(cantos errados, sombras pesadas, tipografia fora do sistema); o painel denso
de dev-tool (paredes de números e gráficos no notch); skeuomorfismo, neon e
glow "gamer"; e qualquer animação que peça atenção sem comunicar um estado.

**Key Characteristics:**
- Preto absoluto como superfície única, contínuo com o hardware.
- Hierarquia por opacidade do branco, não por cor nem por card empilhado.
- A cor pertence ao conteúdo (capa do álbum), nunca à marca.
- Forma assimétrica: cantos de cima flarejam pra dentro, os de baixo arredondam.
- Motion com overshoot na abertura (assinatura Dynamic Island), seco no fecho.

## 2. Colors

Uma superfície preta e uma tinta branca em camadas — a paleta inteira é a
distância entre `#000000` e `#FFFFFF`, com três cores semânticas de sistema
reservadas para estado e uma cor viva emprestada da capa.

### Primary
- **Notch Black** (`#000000`): a superfície. Preenche a `NotchShape` em todos os
  estados, compacto e aberto. É preto puro de propósito — casa com o bisel
  físico e faz o notch de software desaparecer nele quando fechado.
- **Signal White** (`#FFFFFF`): a tinta primária. Títulos, ícones ativos, o texto
  que precisa ser lido primeiro. Contraste máximo (21:1) sobre o preto.

### Secondary
- **Artwork Tint** (dinâmico, extraído da capa via `vibrantTint`, fallback
  branco): a única cor "viva" do sistema. Tinge exclusivamente as barras do
  visualizador de áudio no modo música. Muda a cada faixa. Nunca é aplicada a
  texto — sua função é fazer o notch "vestir" a música que toca, não colorir a UI.

### Tertiary (estado, sistema)
- **Recording Red** (`#FF3B30`, system red): o ponto pulsante de gravação de mic.
- **Charging Yellow** (`#FFCC00`, system yellow): o raio de carregador no HUD de bateria.
- **Low Battery Orange** (`#FF9500`, system orange): alerta de 20% de bateria.

### Neutral (a escada de opacidade do branco sobre preto)
- **Ink Secondary** (`#FFFFFF` @ 85%): valores enfatizados (timer de gravação, título forte).
- **Ink Tertiary** (`#FFFFFF` @ 60%): legendas, artista, texto de apoio.
- **Ink Muted** (`#FFFFFF` @ 45%): controles inativos, ícones desligados.
- **Ink Faint** (`#FFFFFF` @ 30%): placeholders da shelf, texto desabilitado.
- **Fill Strong** (`#FFFFFF` @ 25%): trilhas de progresso/volume, chip selecionado.
- **Fill** (`#FFFFFF` @ 15–18%): cápsulas, estado hover dos chips.
- **Fill Subtle** (`#FFFFFF` @ 8–10%): fundo de chip inativo, item de lista.
- **Fill Faint** (`#FFFFFF` @ 6%): o fundo mais leve possível (linhas de opção).

### Named Rules
**The Borrowed Color Rule.** A única cor saturada da UI é emprestada da capa do
álbum, e só toca o visualizador. Marca nenhuma tinge o notch. Se você está
prestes a colorir um texto ou um ícone com a `Artwork Tint`, pare — a cor
pertence ao conteúdo, não à interface.

**The Pure Black Rule.** A superfície é `#000000`, nunca cinza, nunca vidro
translúcido no estado sólido. Qualquer coisa acima de preto puro cria uma borda
visível contra o bisel do MacBook e quebra a ilusão de continuidade.

## 3. Typography

**Display / Body Font:** SF Pro (com `-apple-system`, `system-ui`)
**Label / Numeric Font:** SF Mono (com `ui-monospace`) e `monospacedDigit()`

**Character:** Uma família só, o sistema inteiro. Nada de fonte importada — o
Knobler fala SF Pro porque é a voz do macOS, e qualquer outra fonte o
denunciaria como app de terceiro. A hierarquia vem de peso e tamanho semânticos
(os estilos nativos do SwiftUI: `.title`, `.headline`, `.subheadline`,
`.footnote`, `.caption2`), nunca de uma segunda família. Números que mudam ao
vivo (volume, timer, contagem) usam dígitos monoespaçados pra não "tremer".

### Hierarchy
- **Display** (SF Pro, regular, ~22px `.title`/`.title2`): título do estado
  expandido — a faixa tocando, a pergunta. Um por card, nunca dois.
- **Headline** (SF Pro, bold, ~13px `.headline`): título de notificação. Curto,
  forte, uma linha.
- **Title** (SF Pro, semibold, ~15px `.title3` / ~11px `.subheadline`): labels de
  controle, nome do app, botões de opção.
- **Body** (SF Pro, regular, ~13px `.body` / ~10px `.footnote`): corpo de
  notificação, artista, texto descritivo. Sempre secundário em opacidade.
- **Label** (SF Mono, medium, ~9px `.caption2`): metadados técnicos — endpoint da
  API local, timers, contadores. Monoespaçado por função, não por estilo.

### Named Rules
**The One System Voice Rule.** SF Pro para tudo que é humano, SF Mono só para o
que é máquina (números que correm, endpoints). Nunca importe uma terceira fonte:
a única maneira de parecer nativo é usar a fonte do sistema.

## 4. Elevation

O sistema é essencialmente plano, com uma única sombra funcional. Não há cards
empilhados nem profundidade decorativa: o notch é uma forma preta única. A
profundidade existe só em um eixo — o notch aberto **flutua** sobre o wallpaper
com uma sombra suave; fechado, ele **funde** no bisel sem sombra nenhuma. As
camadas internas (pills, chips, trilhas) são sugeridas por opacidade do branco,
jamais por `box-shadow`.

### Shadow Vocabulary
- **Float (aberto)** (`shadow: black @ 35%, radius 12, y 5`): aplicada só quando
  `mode != .closed`. Faz o card aberto pairar sobre o conteúdo da tela.
- **Card (interno)** (`shadow: black @ 50%, radius 8, y 2`): reservada para peças
  destacadas dentro de um card aberto (ex.: preview de screenshot). Uso raro.
- **Closed (nenhuma)** (`opacity 0`): fechado, a sombra vai a zero. O notch tem
  que ser indistinguível do bisel.

### Named Rules
**The Melt-Into-Bezel Rule.** Fechado, sombra é zero e a forma é preto puro — o
notch de software desaparece no físico. A sombra só existe como resposta ao
estado aberto, nunca em repouso. Se o notch fechado projeta sombra, está errado.

## 5. Components

Cada peça interna é discreta e táctil: fills de branco translúcido, cantos de
8px, feedback por subida de opacidade no hover. Presença leve, resposta clara.

### The Notch (componente-assinatura)
- **Forma:** `NotchShape` — cantos de cima flarejam *pra dentro* (raio 6px
  compacto / 14px aberto), cantos de baixo arredondam de fora (12px compacto /
  30px aberto). A assimetria acompanha o notch físico e é a identidade do app.
- **Superfície:** preto puro (`#000000`), preenchendo a forma.
- **Máscara:** o conteúdo é recortado pela própria forma (`.mask(shape)`) —
  fechando, a informação some em sincronia com a moldura.
- **Estados:** `closed`, `hud`, `dictation` (compactos, cantos menores);
  `music`, `notification`, `question` (abertos, cantos maiores). Compacto e
  aberto compartilham a mesma forma, só mudam os raios e o tamanho.

### Pills (HUD de volume / brilho / bateria)
- **Trilha:** cápsula com `Fill Strong` (branco 25%); preenchimento sólido branco.
- **Altura:** 6px, largura 64px. Barra cresce da esquerda.
- **Ícone:** SF Symbol branco à esquerda; para bateria, raio `Charging Yellow`.

### Chips de opção (cards de pergunta / Ask)
- **Shape:** `RoundedRectangle(cornerRadius: 8)`.
- **Fundo:** `Fill Subtle` (branco 8%) inativo, subindo pra `Fill` (branco 18%) no hover.
- **Selecionado:** `Fill Strong` (branco 25%).
- **Texto:** `Signal White`; contadores em `Ink Tertiary`.

### Thumbnails (shelf de capturas)
- **Corner Style:** 5–7px (`inner-sm`/`inner-md`), recorte quadrado.
- **Fundo:** `Fill` (branco 15%) atrás de placeholders.
- **Arraste:** thumbnail é fonte de drag nativo (arrastar anexa a foto).

### Visualizer (barras de áudio)
- **Cor:** `Artwork Tint` — a única peça colorida da UI.
- **Movimento:** 5 bandas de FFT, atualização linear a 20Hz, render a 30fps.
- **Estado:** aparece nas "asinhas" do notch fechado quando há música tocando.

## 6. Do's and Don'ts

### Do:
- **Do** manter a superfície em `#000000` puro nos estados sólidos, pra casar com o bisel físico.
- **Do** construir hierarquia com a escada de opacidade do branco (85% → 6%), não com uma segunda cor.
- **Do** deixar a cor entrar só pela capa do álbum, e só no visualizador (a **Borrowed Color Rule**).
- **Do** usar overshoot na abertura (`spring response 0.42, damping 0.76`) e fecho seco (`0.30 / 0.95`) — a assinatura do Dynamic Island.
- **Do** dar a toda animação um fallback de `prefers-reduced-motion` (fade `easeOut 0.15`).
- **Do** usar SF Pro pra tudo humano e SF Mono só pra números que correm e endpoints.
- **Do** rodar `tools/snapshot.sh` e olhar os PNGs antes de qualquer mudança de UI.

### Don't:
- **Don't** dar ao notch cara de **widget/gadget de terceiro** — cantos errados, sombras pesadas, tipografia fora do sistema.
- **Don't** transformar o estado aberto num **painel denso de dev-tool**: nada de paredes de números ou gráficos. Uma informação por vez.
- **Don't** usar **skeuomorfismo, neon, glow ou gradiente "gamer"**. A cor vem do conteúdo, nunca de decoração.
- **Don't** fazer o **notch roubar atenção** — sem piscar ou animar sem comunicar um estado, sem abrir atoa.
- **Don't** projetar sombra no estado fechado (a **Melt-Into-Bezel Rule**).
- **Don't** tingir texto ou ícone com a `Artwork Tint`. Ela é só do visualizador.
- **Don't** importar uma terceira fonte. SF Pro + SF Mono é o sistema inteiro.
- **Don't** usar cinza-escuro ou vidro translúcido no lugar do preto puro no estado sólido.
