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

Miniatura do arquivo, barra com %, linha "Recebendo de <par>" /
"Enviando pra <par>". Alerta do sistema: esconder sem fechar (ex.: mover pra
fora da tela) **somente** se a pesquisa provar que não interrompe a transferência;
senão fica visível.

## Card no fim

Miniatura, "Recebido de X" / "Enviado pra X", botões **Abrir**, **Mostrar no
Finder**, **Prateleira** (reusa `actionTitles`/`actionToken`). Duração 10 s. O
histórico guarda a miniatura.

## Falhas

Sem percentual disponível: atividade indeterminada, como hoje, sem erro.
Cancelamento continua silencioso. Falha mantém o card de erro atual.

## Testes

`tools/airdropcheck.swift` (entrada em `tools/check.sh`): máquina de estados do
coordenador, texto do card, parser da árvore AX com árvores de exemplo. Visual
via `tools/snapshot.sh` com cenários novos (andamento com %, fim com ações).

## Fora do escopo

API local de AirDrop; notificação de app de terceiros com ações.
