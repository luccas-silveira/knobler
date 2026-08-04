# Quem é de fábrica e quem é plugin

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: claude (sessão 2026-08-04)
- blocked-by: —

## Question

Decisão de produto, não de código. O critério dado no charting foi "o que
interage mais com o sistema vanilla da Apple vem por padrão" — falta afiar esse
critério e aplicar à lista.

- **O critério, dito com precisão.** "Interage com o sistema" pega quase tudo
  (o ditado usa o microfone, o shelf usa o Finder). O critério mais provável de
  sobreviver é outro: **vem de fábrica o que substitui algo que o macOS já
  fazia** (HUDs de volume/brilho, notificações, música tocando) — porque tirar
  isso deixa o app com um buraco visível. É plugin o que **acrescenta** algo que
  o macOS não tem (Pomodoro, Lembretes, Descanso, Mensagens LAN, Webhooks).
  Confirmar, refutar ou trocar.
- **A lista, feature por feature**, nas três colunas: de fábrica, plugin, ou não
  decidido ainda.
- **Existe plugin que depende de outro?** (Webhooks e Notificações; Descanso e
  Pomodoro.) Se sim, o que acontece ao desinstalar o de baixo — some junto,
  bloqueia, ou avisa.
- **Features sem painel e sem preferência** (Preview de Link, Nota rápida,
  Conversão de arquivo): elas sequer são "features" separadas na cabeça do
  usuário, ou são pedaços de outra (a conversão só existe dentro do Shelf)? Peça
  que ninguém sabe nomear não vira item de catálogo.
- **Notificações provavelmente é de fábrica por obrigação**: 001 mostrou que sete
  features publicam por `publicar()`. Confirmar.
- **Quantos plugins o catálogo vai ter no fim?** Se der 3, não vale loja. Se der
  10, vale.

Não depende de nenhum ticket: é decisão do dono, e é o que diz quais features
sequer são candidatas a cobaia.

## Resolução (2026-08-04)

### O critério

**De fábrica é o que substitui algo que o macOS já fazia. Plugin é o que
acrescenta algo que o macOS não tem.** O critério do charting ("interage com o
sistema") foi trocado: pegava quase tudo. Descartados também "todo mundo usa"
(sem dados de uso, vira palpite) e "difícil de arrancar" (deixaria a
arquitetura decidir o produto).

### A lista

**De fábrica (4)** — Música/HUDs, Notificações, Shelf, AirPods.

- Música/HUDs e Notificações caem direto do critério (HUD nativo, Central de
  Notificações), e Notificações ainda é obrigação técnica: `publicar()` é o
  funil de sete features (001).
- **Shelf**: substitui a miniatura de captura do macOS — o app até suprime a
  nativa (`OSDSuppressor`). Tirar deixa buraco que a pessoa não sabe explicar.
- **AirPods**: o macOS já mostra a bateria ao conectar; o Knobler só mostra mais
  bonito. Ressalva registrada: é a feature mais barata de virar plugin (o toggle
  `airpodsNotch` já desliga o serviço de verdade) — se algum dia o catálogo
  precisar de item, ela é a primeira a mudar de lado.

**Plugin (11)** — Pomodoro, Lembretes, Descanso, Mensagens LAN, Webhooks,
Ditado, Espelho, Anotação, Nota rápida, Preview de Link, Conversão de arquivo.

- **Ditado é plugin** apesar do macOS ter ditado nativo: o do Knobler faz outra
  coisa (nuvem, formatação por IA, destino no Ask). Quem não instala continua
  com o ditado da Apple.
- **Anotação é plugin** pelo critério (o macOS não desenha na tela), mesmo sendo
  das mais grudadas hoje (tap global e timer incondicionais, `hasContent`
  hardcoded).
- **Preview de Link, Nota rápida e Conversão de arquivo entram no catálogo**,
  contra a recomendação de deixá-las como comportamento invisível. Decisão do
  dono. Duas ressalvas que viram trabalho:
  1. Preview de Link e Conversão só têm um ponto de entrada, dentro do Shelf.
     Desinstaladas, o botão correspondente precisa **sumir** do card do Shelf —
     não ficar cinza nem dar erro.
  2. As três precisam ganhar nome e ícone de catálogo, que hoje não têm.

**Não decidido: nenhum.** As 15 features estão distribuídas.

### Dependências entre peças

Quase todas se dissolvem: Webhooks→Notificações, Ditado→tap do VolumeHUD,
Espelho→calendário — o de baixo é sempre de fábrica, logo sempre está lá. O
único par plugin→plugin é **Pomodoro→Descanso** (o Pomodoro chama
`descanso.begin` pra travar a tela nas pausas, `KnoblerApp.swift:441`).

**Regra: a opção some, sem avisar.** Sem o Descanso instalado, o toggle "travar
a tela na pausa" não aparece nos Ajustes do Pomodoro e o Pomodoro segue inteiro.
Descartados "instalar junto" (cria conceito de pacote na loja) e "avisar e
oferecer" (tela a mais num piloto de um plugin só).

Isso vira uma restrição pra 003 — **a peça precisa saber perguntar se outra peça
está instalada**, e a resposta "não" tem que ser um caminho normal, não um erro.

### Tamanho do catálogo

**11 plugins.** Passa folgado do limiar de "vale loja" levantado no ticket.
