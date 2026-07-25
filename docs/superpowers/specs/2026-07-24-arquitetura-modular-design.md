# Arquitetura modular e fluxo unidirecional — design

**Data:** 2026-07-24
**Status:** piloto Ask concluído; Fase 6 de limpeza/documentação concluída
**Escopo:** app macOS Knobler; o relay Node permanece fora da primeira migração

## Objetivo

Evoluir a arquitetura do Knobler para suportar novas features sem aumentar a
concentração de responsabilidades no `AppDelegate`, `NotchViewModel`,
`NotchView` e `AppSettings`.

A arquitetura deve manter:

- SwiftUI para a UI declarativa;
- AppKit para `NSPanel`, Accessibility, CoreAudio, AVFoundation e integração
  com o sistema;
- compatibilidade com macOS 14.2+;
- baixo consumo no estado ocioso;
- harnesses de self-check e snapshots;
- ausência de uma dependência arquitetural obrigatória como TCA na primeira
  etapa.

## Resultado real do piloto Ask (2026-07-24)

O primeiro piloto foi implementado nas Fases 1–5 e fechado com a Fase 6. Ele
validou o padrão unidirecional em uma feature completa sem mudança observável
de produto.

### Domínio

- `AskState` contém `active`, fila FIFO, `page`, seleção, respostas indexadas
  pela pergunta e texto livre.
- `AskAction` cobre entrada, seleção, texto (`setText`/`appendText`), submit,
  cancelamento, limpeza e dismiss externo; as ações de resolve/cancel também
  preservam a compatibilidade de composição.
- `AskEffect` representa somente `resolve` e `cancel`.
- `AskReducer` é síncrono, puro e determinístico: deduplica IDs, promove FIFO,
  reseta os inputs na promoção, valida submits e transforma ações inválidas em
  no-op. Não conhece SwiftUI, AppKit, Network ou `NotchAPIServer`.

### Runtime e composição

`AskStore` usa `@Observable` e `@MainActor`, aplica o reducer imediatamente e
executa as dependências assíncronas de resolve/cancel em `Task`. Há uma única
instância na composição do app. O `AppDelegate` configura essa instância com
closures fracas para o `NotchAPIServer`, registra os callbacks antes do
listener e usa guards de geração para descartar callbacks obsoletos durante o
ciclo de vida da API.

### UI e multi-monitor

`AskCardView` lê seleção, página, respostas e texto diretamente do store; hover
e foco continuam sendo estado local de apresentação. `NotchView` deriva o modo
de pergunta, tamanho, animações e elegibilidade do teclado do store. A mesma
instância é passada a todas as janelas, então seleção, paginação, texto,
resolve e cancelamento são compartilhados. O fan-out e o bridge de Ask pelo
`NotchViewModel` foram removidos na Fase 5; o view model continua responsável
somente pelos demais modos visuais e pelo nível de ditado usado no card.

### Compatibilidade HTTP

`NotchAPIServer` continua dono de parsing, `pendingAsks`, polling, TTL,
`GET /status`, endpoints e estados de resposta. `POST /ask`, `GET /ask/<id>` e
`POST /ask/<id>/cancel` mantiveram rotas, campos e status. A guarda no servidor
preserva a regra “primeira resposta vence”, inclusive contra resolve/cancel
repetidos. O hook `tools/claude-hook/knobler-ask.sh` não foi alterado.

### Fora do piloto e decisão de dependências

O piloto não criou Swift Package, não moveu o relay Node e não migrou
Notification, Activity, Music, Messaging, Dictation ou `AppSettings`. Também
não houve migração mecânica dos objetos `ObservableObject` existentes. TCA foi
avaliado como referência conceitual, mas não adotado: o reducer/store local
foi suficiente para o domínio Ask, mantém poucas dependências e deixa uma
eventual adoção futura baseada em evidência de escala.

## Diagnóstico

O código atual é funcional e tem boas fronteiras em vários serviços puros, mas
o fluxo de composição está centralizado demais:

| Área | Situação atual | Problema resultante |
|---|---|---|
| `AppDelegate` | Inicializa e conecta praticamente todos os serviços | alto acoplamento e testes difíceis |
| `NotchViewModel` | Estado de música, HUD, mensagens, perguntas, AirPods e Pomodoro | mudanças locais causam risco entre features |
| `NotchView` | Layout de todos os modos do notch e regras de prioridade | arquivo grande, difícil de evoluir visualmente |
| `AppSettings.shared` | Persistência, defaults, identidade e eventos globais | dependência implícita em quase todo o app |
| Closures/Combine | Comunicação direta entre serviços | fluxo de eventos difícil de rastrear |
| Target único | Todos os arquivos compilam no mesmo módulo | fronteiras arquiteturais não são verificadas pelo compilador |
| Integrações do sistema | Chamadas concretas espalhadas nos serviços | pouca substituibilidade em testes |

Os modelos puros e alguns serviços já são uma base boa para a migração:
`Pomodoro`, `Reminders`, `Descanso`, `Wire`, `MediaRemoteSource`,
`TranscriptFormatter` e os parsers de bateria/template.

## Decisões

### 1. Arquitetura unidirecional própria

Cada feature nova deverá seguir o fluxo:

```text
View → Action → FeatureStore/Reducer → Effect/Dependency → Action → State → View
```

Não será introduzido TCA no primeiro ciclo. A implementação usará tipos Swift
locais (`State`, `Action`, `Reducer` e `Dependencies`) e poderá migrar para
TCA no futuro se o benefício superar o custo.

### 2. O `AppDelegate` vira compositor

O `AppDelegate` continuará dono do ciclo de vida do processo e das janelas,
mas deixará de conter regras de domínio. Ele deverá:

- criar dependências;
- iniciar/parar serviços;
- conectar outputs de features;
- distribuir eventos de sistema;
- criar e registrar os view models das telas.

Não deverá decidir detalhes de notificação, mensagem, pergunta, ditado ou
Pomodoro.

### 3. AppKit permanece na borda

`NSPanel`, `CGEventTap`, AXObserver, CoreAudio, AVFoundation, Network e
`Process` ficam em adaptadores/serviços de infraestrutura. Features recebem
protocolos ou eventos tipados e não acessam diretamente essas APIs quando não
for necessário.

### 4. Observation será adotado gradualmente

Novos stores usarão `@Observable`/Observation, disponível no alvo macOS 14.2.
Os objetos existentes com `ObservableObject` serão migrados somente quando
forem tocados por uma refatoração funcional. Não haverá migração mecânica de
toda a UI em uma única etapa.

### 5. Concorrência explícita

- Stores e coordenadores de UI: `@MainActor`.
- Rede, parsing pesado, persistência e processamento de mídia: `actor` ou
  filas dedicadas.
- Callbacks de APIs do sistema devem voltar explicitamente para a Main Actor.
- Nenhum estado mutável será compartilhado entre filas sem isolamento claro.

## Arquitetura-alvo

```text
KnoblerApp / AppDelegate
        │
        ├── AppComposition
        │     ├── SystemDependencies
        │     ├── PersistenceDependencies
        │     └── FeatureStores
        │
        ├── NotchCoordinator
        │     ├── NotchWindow(s)
        │     └── NotchRootStore
        │           ├── AskFeature
        │           ├── NotificationFeature
        │           ├── MusicFeature
        │           ├── MessagingFeature
        │           ├── DictationFeature
        │           ├── HUDFeature
        │           ├── PomodoroFeature
        │           └── ActivityFeature
        │
        └── Infrastructure
              ├── MediaRemote
              ├── Audio
              ├── Accessibility
              ├── Camera
              ├── LAN/Webhook
              ├── Calendar
              └── Persistence
```

A estrutura física inicial pode continuar em um target, mas os diretórios
deverão refletir as fronteiras. A extração para Swift Packages/modules fica
para depois que as interfaces estabilizarem.

## Modelo de uma feature

Exemplo conceitual para o fluxo de perguntas:

```swift
struct AskState: Equatable {
    var active: AskRequest?
    var page = 0
    var text = ""
    var answers: [String: AskAnswer] = [:]
}

enum AskAction {
    case received(AskRequest)
    case select(label: String)
    case submitPage
    case submitText(String)
    case cancel
    case responseDelivered
}

struct AskDependencies {
    var resolve: @Sendable (String, [String: AskAnswer]) async -> Void
    var cancel: @Sendable (String) async -> Void
}

@MainActor
final class AskStore: ObservableObject {
    @Published private(set) var state = AskState()
    // reduce(action) + efeitos assíncronos
}
```

O código concreto pode variar, mas cada feature precisa tornar explícitos:

- quais estados possui;
- quais ações podem alterá-los;
- quais efeitos externos executa;
- quais dependências são necessárias;
- quais invariantes são garantidas.

## Fronteiras das features

### `NotchRootFeature`

Responsável somente por estado de apresentação global do notch:

- display/monitor;
- modo visível;
- expansão/colapso;
- prioridade entre cards;
- hover, peek e timers visuais;
- fan-out para múltiplas telas.

Não deve implementar a lógica de webhook, transcrição ou mensagens.

### `AskFeature`

Move de `NotchViewModel` e `NotchAPIServer`:

- fila de perguntas;
- paginação;
- respostas e cancelamento;
- integração com o hook do Claude Code;
- texto alimentado por ditado.

### `NotificationFeature`

Move:

- fila e deduplicação;
- duração e hold do card;
- abertura de URL/app/Supacode;
- ícone local/remoto.

### `MusicFeature`

Move:

- estado de now playing;
- posição extrapolada;
- artwork e tint;
- comandos play/pause/next/previous/shuffle;
- visualizador e seleção da fonte de áudio.

`MediaRemoteSource` e `SystemAudioLevels` continuam infraestrutura.

### `MessagingFeature`

Move:

- peer selecionado;
- conversa e rascunho;
- anexos pendentes;
- mensagens recebidas e respostas rápidas.

`LANMessaging`, `MessageStore`, `Wire` e `MessageMedia` ficam atrás de
protocolos de dependência.

### `DictationFeature`

Move:

- fases `preparing`, `recording`, `transcribing` e `error`;
- escolha local/cloud;
- sink para Ask;
- inserção no cursor.

`MicRecorder`, `ParakeetEngine`, `DeepgramEngine` e `TranscriptFormatter`
ficam como engines/adaptadores substituíveis.

### Features de estado simples

HUD, Activity, AirPods e Pomodoro deverão ser extraídos depois do piloto,
seguindo o mesmo formato. `Pomodoro` já possui um motor puro e deve apenas
ganhar uma camada de store/efeitos.

## Dependências e composição

Criar um objeto de composição, inicialmente no mesmo target:

```swift
@MainActor
final class AppComposition {
    let settings: SettingsStore
    let media: MusicStore
    let ask: AskStore
    let notifications: NotificationStore
    let messaging: MessagingStore

    init(environment: AppEnvironment = .live) { ... }
}
```

`AppEnvironment` deverá conter implementações reais e de teste para:

- relógio;
- timers;
- UserDefaults/Keychain;
- HTTP/WebSocket;
- media remote;
- clipboard e inserção de teclado;
- notificações do sistema;
- áudio e câmera.

O ambiente de teste não precisa simular o WindowServer inteiro. Ele deve
permitir testar decisões, transições e efeitos sem abrir janelas reais.

## Configurações

`AppSettings.shared` será dividido em:

- `SettingsStore`: estado observável e API de leitura/escrita;
- `SettingsPersistence`: UserDefaults/Keychain;
- modelos por domínio, quando necessário (`DictationSettings`,
  `PomodoroSettings`, `WebhookSettings`, etc.).

Durante a migração, `AppSettings.shared` poderá continuar como fachada de
compatibilidade. Nenhuma feature nova deverá adicionar dependência direta ao
singleton.

## Plano de migração

### Fase 0 — contrato e proteção

- Registrar a arquitetura atual e os invariantes dos modos do notch.
- Manter snapshots existentes.
- Adicionar testes de transição para fila, prioridade, dismiss e multi-monitor.
- Não alterar comportamento visual ou de produto.

### Fase 1 — piloto `AskFeature`

- Criar `AskState`, `AskAction`, `AskStore` e dependências.
- Remover gradualmente estado de Ask do `NotchViewModel`.
- Fazer `NotchView` consumir o estado do novo store.
- Conectar `NotchAPIServer` ao store por uma interface tipada.
- Preservar o contrato HTTP existente.

### Fase 2 — `NotificationFeature` e `ActivityFeature`

- Extrair fila/dedupe/dismiss das notificações.
- Separar atividades API/calendário da apresentação.
- Substituir closures diretas por eventos/ações tipados.

### Fase 3 — `MusicFeature` e HUD

- Separar estado de mídia do estado visual do notch.
- Manter `MediaRemoteSource` e `SystemAudioLevels` como infraestrutura.
- Validar consumo e comportamento multi-monitor.

### Fase 4 — `MessagingFeature`, `DictationFeature` e settings

- Extrair mensagens e ditado.
- Introduzir protocolos de dependência e ambientes de teste.
- Migrar configurações tocadas para stores específicos.

### Fase 5 — modularização física

Somente após as interfaces estabilizarem, avaliar:

- `KnoblerCore` Swift Package para modelos puros;
- `KnoblerFeatures` para stores/reducers;
- `KnoblerSystem` para adaptadores AppKit/CoreAudio/AVFoundation;
- target de self-checks separado.

Não criar módulos apenas para refletir pastas; a extração deve reduzir
dependências verificáveis pelo compilador.

## Critérios de aceitação

### Arquitetura

- `AppDelegate` não contém regras específicas de Ask, notificações, mensagens,
  ditado ou Pomodoro.
- Cada feature piloto possui estado, ações, efeitos e dependências explícitos.
- Features não acessam `AppSettings.shared` diretamente.
- Serviços de sistema não conhecem views SwiftUI.
- Código de UI não cria `Process`, `NWConnection`, `Timer` de domínio ou
  chamadas de persistência diretamente.

### Comportamento

- Todos os snapshots atuais continuam iguais ou têm mudanças visuais
  intencionais documentadas.
- API local e hook Ask mantêm compatibilidade.
- Primeira resposta do Ask continua vencendo nos múltiplos monitores.
- Notificações continuam deduplicando e respeitando hold/dismiss.
- Música, ditado, mensagens e HUD continuam funcionando em todos os monitores.

### Qualidade

- Testes unitários cobrem reducers/stores e invariantes de fila.
- Self-checks puros continuam executáveis sem UI.
- O build Debug e Release continuam passando.
- O consumo ocioso não aumenta de forma mensurável.
- Cada fase pode ser revertida sem reescrever a feature anterior.

## Fora de escopo

- Trocar SwiftUI por React, Flutter, Electron ou outra UI multiplataforma.
- Reescrever o app inteiro em TCA imediatamente.
- Substituir AppKit por APIs somente SwiftUI.
- Alterar UX, layout ou contratos HTTP como parte da refatoração.
- Migrar o relay Node para Swift.
- Criar microserviços ou múltiplos processos para resolver acoplamento interno.

## Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Migração introduz regressão em timers/hover | snapshots + testes de transição + uma feature por vez |
| Observation muda comportamento de atualização | migrar apenas stores novos/tocados |
| Abstrações excessivas atrasam features | protocolos somente nas bordas externas |
| Store global vira novo `AppDelegate` | limitar cada store a um domínio explícito |
| TCA ser necessário mais tarde | manter reducers/actions compatíveis conceitualmente |
| Custo de concorrência mal isolada | `@MainActor`, actors e testes de thread-safety |

## Resultado esperado

Ao final, o Knobler continuará sendo um app nativo AppKit/SwiftUI, mas com:

- composição central pequena;
- features independentes e testáveis;
- fluxo de estado previsível;
- dependências externas isoladas;
- evolução visual sem tocar em integrações de sistema;
- caminho aberto para TCA ou Swift Packages caso a escala justifique.

## Versionamento

Refatoração interna. Não exige bump de produto enquanto não alterar contrato ou
UX. Registrar progresso em `CHANGELOG.md` apenas quando houver impacto
observável, mudança de compatibilidade ou uma fase concluída.
