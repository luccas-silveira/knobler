# Como uma feature está grudada no app hoje

- map: ../map.md
- label: wayfinder:research
- status: closed
- assignee: —
- blocked-by: —
- resultado: ../research/001-amarras.md

## Question

Antes de inventar a forma da peça, é preciso saber a forma da cola. Levantar, com
`arquivo:linha`, todos os pontos onde uma feature toca o resto do app hoje.
Feito sobre o código, sem propor solução.

Para cada uma das ~15 features (Pomodoro, Lembretes, Descanso, Ditado, Mensagens,
Webhooks, Shelf, Espelho, Anotação, Link, Nota rápida, AirPods, Conversão de
arquivo, Notificações, Música), levantar:

- **Nascimento**: onde o serviço é criado e configurado (`KnoblerApp.swift` /
  `AppDelegate`), o que é injetado nele e quem guarda a referência.
- **Notch**: como a seção entra na `NotchView` e em `NotchSectionOrder`.
- **Ajustes**: se tem painel em `SettingsView` e como ele é listado.
- **Preferência**: quais chaves de `AppSettings` / `UserDefaults` são só dela, e
  se já existe toggle de liga/desliga (e se ele desliga de verdade ou só esconde).
- **API local**: quais rotas de `NotchAPIServer` são dela, e o que ela adiciona
  a `GET /status`.
- **Sistema**: permissão exigida, hook/tap global, timer, observer — o que ela
  acende no mundo mesmo parada.
- **Amarras cruzadas**: quem mais lê o estado dela (ex.: o Pomodoro lê o
  calendário; o gate de silêncio lê o microfone).

Entregar como tabela por feature, mais uma nota final: **quais features hoje já
estão quase soltas** (poucas amarras, toggle que desliga de verdade) e **quais
estão mais grudadas**. Essa nota é o insumo da escolha da cobaia.

## Resolução (2026-08-04)

Levantamento completo em [`../research/001-amarras.md`](../research/001-amarras.md)
— tabela por feature (nascimento, notch, Ajustes, preferências, API, sistema,
amarras cruzadas) com `arquivo:linha`.

### O que o levantamento mudou de entendimento

**1. "Toggle" não quer dizer desligado.** Três padrões diferentes convivem hoje:

| Padrão | Exemplos | O que acontece |
|---|---|---|
| Toggle desliga de verdade | Ditado, Webhooks, AirPods, Shelf/screenshots | `start()` é guardado pelo toggle; nada acende |
| Toggle só esconde | Notificações (`notchNotifications`), HUDs (`volumeHUD`/`brightnessHUD`) | O tap global sobe sempre; o toggle filtra na hora de exibir |
| Não tem toggle | Pomodoro, Mensagens LAN, Anotação, Nota, Link, Conversão, Espelho | Nasce sempre |

A promessa de custo zero (decidida no charting) não é ajuste de um `if` — para
**dez das quinze** features ela não existe hoje em nenhuma forma.

**2. Quatro features não nascem no `AppDelegate`**: Espelho, Link, Nota e
Anotação são `.shared` (singleton). Um registro que só governe o que o
`AppDelegate` cria não alcança essas quatro. É restrição direta para a forma da
peça (003).

**3. Duas features estão presas ao mesmo tap global.** O `VolumeHUDController`
sobe incondicionalmente porque **o ditado depende dele** para o Right-Option
(`KnoblerApp.swift:213`, `:230`). Desligar HUDs mataria o gatilho do ditado. Isso
é dependência entre peças que não aparece em nenhuma preferência.

**4. As notificações são o funil.** Pomodoro, Lembretes, avisos do dev, Webhook,
API, ColorPicker e Updater publicam todos por `publicar()`. Se "Notificações"
virar plugin desinstalável, sete features perdem a saída. Cheira a "de fábrica"
— insumo para 002.

### Candidatas a cobaia, do levantamento

Quase soltas: **Conversão de arquivo**, **Preview de Link**, **AirPods**,
**Webhooks**, **Descanso**, **Ditado**, **Lembretes**.
Mais grudadas: Notificações, Música/HUDs, Anotação, Espelho, Mensagens LAN,
Shelf, Pomodoro.

Ressalva para 004: das quase soltas, só **Webhooks** e **Ditado** ocupam mais de
uma superfície com painel próprio; Conversão e Link não têm painel nem
preferência nenhuma — soltas demais para provar a forma.

⚠️ As linhas são do código na v0.22.0. Conferir antes de confiar num número.
