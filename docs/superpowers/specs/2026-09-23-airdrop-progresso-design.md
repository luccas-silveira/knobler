# AirDrop: progresso, módulo próprio e card novo — design

Data: 2026-09-23

## Objetivo

Barra de progresso real no notch para AirDrop nos dois sentidos (receber e
enviar), código de AirDrop reunido num módulo, e card com mais contexto e ações.

## Módulo `Knobler/AirDrop/`

- `AirDropEnvio.swift` — o que hoje é `Sharing.airdrop`, `airdropFromPanel` e
  `AirDropSession`. `Sharing.share` (picker genérico) fica em `Sharing.swift`.
- `AirDropRecebimento.swift` — detecção/espelho do alerta de recebimento. O
  `NotificationInterceptor` só delega ("alerta de AirDrop chegou"); a regra
  `isAirDrop` sai de `NotificationRules`.
- `AirDropProgresso.swift` — fontes de percentual:
  - recebimento: `Progress.addSubscriber(forFileURL:)` na pasta Downloads
    (o mesmo progresso publicado que o Finder desenha no ícone);
  - envio: leitura AX da janela de compartilhamento do sistema.
- `AirDropCoordenador.swift` — estado único `AirDropTransfer { direção, arquivo(s),
  par (pessoa/aparelho), fração?, fase }` e tradução pra `NotchActivity` +
  `NotchNotification`. `KnoblerApp` só instancia e liga.

## Card em andamento

Miniatura do arquivo e anel com % (recebimento); envio indeterminado com
"Enviando pra <aparelho>". Recebimento: "Recebendo por AirDrop" + nome do arquivo.
O alerta "Recebendo" do sistema fica intocado (ver A3).

## Card no fim

Miniatura, "Recebido: <arquivo>" / "Enviado pra <aparelho>", botões **Abrir**,
**Mostrar no Finder**, **Prateleira** (reusa `actionTitles`/`actionToken`). Duração
30 s (card acionável). O alerta "AirDrop Concluído" do sistema é fechado.
Histórico sem miniatura nem botões.

## Falhas

Sem percentual disponível: atividade indeterminada, como hoje, sem erro.
Cancelamento continua silencioso. Falha mantém o card de erro atual.

## Testes

`tools/airdropcheck.swift` (entrada em `tools/check.sh`): máquina de estados do
coordenador, texto do card, parser da árvore AX com árvores de exemplo. Visual
via `tools/snapshot.sh` com cenários novos (andamento com %, fim com ações).

## Fora do escopo

API local de AirDrop; notificação de app de terceiros com ações.

## Decisões do grill

- **A1** — recebimento via `Progress.addSubscriber(forFileURL: ~/Downloads)` confirmado
  ao vivo (30 atualizações de % num vídeo de ~5 s, com nome do arquivo). Mantido.
- **A3** — alerta "Recebendo" (transferência viva) nunca é tocado; o alerta
  "AirDrop Concluído" é fechado e substituído pelo card. Motivo: teste ao vivo mostrou
  que ele só nasce após o fim da transferência. Descartado "esconder fora da tela".
- **A4** — recebimento sem nome do par (o alerta não traz): card diz "Recebendo por
  AirDrop" + nome do arquivo.
- **A2** — envio sem %: atividade indeterminada com destino lido por AX da janela
  "AirDrop" do próprio processo (`AXButton desc="<aparelho>, Enviando|Enviado"`).
  Card: "Enviando pra <aparelho>" / "Enviado pra <aparelho>". Sem destino legível,
  cai no texto atual.
- **A8** — "barra" vira o anel com % já existente (`NotchActivity.progress`,
  `NotchView.swift:1157-1180`). Sem componente novo.
- **A6** — 10 s descartado: card com botões usa o `actionableDuration` (30 s) existente.
- **A5** — botões Abrir/Finder/Prateleira só no card vivo (ações não persistem por
  desenho, `NotchNotification.swift:59-67`); no histórico o clique segue revelando
  Downloads. Roteamento: ramo novo em `onNotificationAction` pro token de AirDrop.
- **A7** — miniatura via `ShelfPreview.thumbnail(of:)` (funciona no snapshot; QL não).
  Só no card vivo; histórico segue com 📥, sem imagem persistida.
- **A9/A10** — sem decisão: plano atualiza `tools/check.sh`, `tools/notchview-fontes.txt`,
  `docs/shelf.md`, `docs/notifications.md` e o comentário de `KnoblerApp.swift:157-159`.
