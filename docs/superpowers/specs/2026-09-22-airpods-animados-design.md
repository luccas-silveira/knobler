# AirPods animados no notch — design

Data: 2026-09-22 · Versão alvo: próxima MINOR

## Objetivo

Hoje o card de AirPods é um ícone genérico (`airpodspro`) parado com os
percentuais em texto. O pedido: que conectar os AirPods no Mac pareça conectar
no iPhone — a ilha que alarga com o fone animado e o anel de bateria, e o card
de proximidade com um anel por peça.

## Escopo (decidido com o usuário)

- **Referência:** as duas animações do iPhone. Ilha compacta ao conectar; card
  grande ao passar o mouse na ilha ou na bateria baixa.
- **Arte:** SF Symbols por modelo com `symbolEffect` nativo. Sem ilustração
  própria, sem render 3D, sem asset da Apple copiado.
- **Modelo:** detectado pelo `device_productID` que o `system_profiler` já
  devolve (a máquina de dev reporta `0x2024`, AirPods Pro 2 USB-C).

Fora de escopo: estado "carregando" (o `system_profiler` não informa de forma
confiável), estojo abrindo em 3D, múltiplos fones simultâneos (continua o
primeiro conectado, como hoje), AirPods Max (reportam bateria única que o
parser não lê; sem hardware pra confirmar o campo — o modelo fica mapeado só
pra ícone).

## Comportamento

**Conexão → ilha compacta (~3 s).** O notch alarga na largura das pílulas
(HUD/Pomodoro). À esquerda, o símbolo do fone do modelo entra com
`.bounce`. À direita, um anel de bateria enche de 0 até o menor nível entre
esquerdo e direito (estojo não entra: é o que o iPhone mostra), com o número ao
lado. Some sozinho e o notch volta ao estado anterior.

**Hover na ilha → card grande.** Enquanto a ilha está visível, hover a expande
para o card: nome dos fones no topo; três colunas (esquerdo, direito, estojo),
cada uma com o símbolo da peça e um anel que enche em cascata (atraso curto
entre colunas). Peça sem leitura: anel vazio e "—". O card fica aberto
enquanto o cursor estiver nele e some ao sair, como os outros cards
transitórios.

**Bateria baixa → card grande direto.** Sem passar pela ilha. Anel da peça
fraca em vermelho, mesmo limite de hoje (≤ 10 %).

**Reduzir movimento.** Sem `bounce`, sem enchimento: anéis aparecem no nível
final, transições viram opacidade (padrão já usado no `NotchView`).

## Modelos

`AirPodsBattery` ganha `model`, derivado de `device_productID`:

| Modelo | Product IDs | Par | Esq./dir. | Estojo |
|---|---|---|---|---|
| Pro, Pro 2, Pro 3 | 0x200E, 0x2014, 0x2024, 0x2027, 0x2028 | `airpodspro` | `airpodpro.left/right` | `airpodspro.chargingcase.wireless` |
| 3ª ger. | 0x2013 | `airpods.gen3` | `airpod.gen3.left/right` | `airpods.gen3.chargingcase.wireless` |
| 4 e 4 ANC | 0x2019, 0x201B | macOS 15.2+: `airpods.gen4`; antes: como 3ª ger. | macOS 15.2+: `airpods.gen4.left/right` | macOS 15.2+: `airpods.gen4.chargingcase.wireless` |
| 1ª/2ª ger. | 0x2002, 0x200F | `airpods` | `airpod.left/right` | `airpods.chargingcase` |
| Max | 0x200A, 0x201F | `airpodsmax` | — | — |
| Desconhecido | qualquer outro | `airpodspro` | `airpodpro.left/right` | `airpodspro.chargingcase.wireless` |

Nomes antigos (pré-macOS 15) de propósito: valem no target 14.2 e seguem como
alias nos sistemas novos. `device_productID` chega como string `"0x2024"`;
parse como inteiro hex. Fonte: `docs/superpowers/research/2026-09-22-airpods-animados-research.md`
(A7, A8).

## Arquitetura

- `AirPodsBattery` (modelo puro): `model` + mapeamento ID → modelo → símbolos.
  Parser continua coberto por `tools/airpods_selfcheck.swift`.
- `BluetoothMonitor.onAnnounce` passa a dizer o motivo (conexão ou bateria
  baixa), porque hoje os dois chamam o mesmo callback e o card precisa saber
  se abre como ilha ou como card.
- `NotchContentState`/`NotchMode`: a ilha e o card são estados distintos de
  AirPods; a ilha dimensiona como `.hud`/`.pomodoro`, o card como hoje ou
  maior. Coberto por `tools/presentationcheck.swift`.
- `NotchViewModel.showAirPodsCard` vira ilha ou card conforme o motivo; hover
  na ilha promove para card e segura o timer.
- `NotchView`: `airpodsIsland` e `airpodsConnectCard` redesenhado; anel de
  bateria como view pequena reutilizada nos dois.

## Testes

- `airpods_selfcheck`: `productID` → modelo, incluindo ID desconhecido.
- `presentationcheck`: ilha vs. card vs. prioridade com outros modos.
- `tools/snapshot.sh`: poses ilha, card, bateria baixa, modelo
  desconhecido, estojo sem leitura. Os cenários `airpods-*` existentes são
  atualizados.

## Decisões do grill

- **A1** — hover-out do card grande fecha o notch. O hover sobre a ilha/card de
  AirPods não liga `expanded` por baixo (senão o card de música assume quando os
  AirPods somem). Motivo: `NotchView.swift:234-243` + prioridade em
  `NotchPresentation.swift:31-35`.
- **A2** — hold do timer no molde de `holdNotification`
  (`NotchViewModel.swift:619-644`): cursor dentro cancela, saída reagenda curto.
- **A4** — ilha e card de AirPods ficam na posição atual de `airpods`
  (abaixo de `hud` e `update`, acima de `expanded`). Volume/brilho tomam o lugar;
  o timer dos AirPods segue correndo e a ilha reaparece se sobrar tempo.
- **A3** — conexão já com bateria ≤ 10 % vira um anúncio só, de bateria baixa
  (card direto, sem ilha). Motivo: `BluetoothMonitor.swift:100-110` hoje dispara
  os dois em sequência.
- **A6** — anel verde com carga normal, vermelho ≤ 10 %. Motivo: é a cor do
  iPhone (TechWiser, Apple Community 254336086).
- **A5** — caso novo `NotchMode.airpodsIsland`, exposto como tal no
  `GET /status` (`KnoblerApp.swift:674`). O campo `mode` não está documentado
  em `docs/local-api.md`, então não há doc a atualizar.
- **A7** — tabela de símbolos corrigida (seção Modelos): lados usam o
  singular, AirPods 4 exige macOS 15.2, Pro 3 cai em Pro, Max sem lados.
- **A8** — tabela de IDs adotada; parse de `device_productID` como inteiro hex.
- **A9** — `bounce` via `.symbolEffect(.bounce, value:)` com contador;
  `isActive:` e repetição contínua são macOS 15, fora.
- **A10** — `ActivityRingView` (`NotchView.swift:1532`) ganha cor/tamanho e
  respeita reduceMotion; anel vazio não desenha o ponto do `lineCap .round`.
- **A11** — cenários `airpods-strip-music` e `airpods-card-nomusic` apagados
  (UI removida em `12c765f`); viram as poses novas.
- **A12** — spec de 2026-07-19 recebe nota de "substituída por esta".
- **A13** — largura do card sai de um lugar só (`NotchPresentation`), sem
  duplicar em `NotchView.swift:196`.
- **Max** — fora do escopo. Motivo: `AirPodsBattery.parse` exige nível de
  esquerdo/direito/estojo e o Max reporta um só; sem hardware pra verificar.
