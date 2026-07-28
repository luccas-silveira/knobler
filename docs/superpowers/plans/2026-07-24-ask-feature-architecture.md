# AskFeature — plano de implementação

> Plano do piloto da arquitetura modular e unidirecional do Knobler. Executar
> em fases consecutivas; cada fase deve compilar e ser verificável antes da
> próxima.

**Objetivo:** retirar o domínio de perguntas do `NotchViewModel` e do wiring
direto do `AppDelegate`, introduzindo um store/reducer próprio, dependências
explícitas e uma única fonte de verdade compartilhada pelos monitores.

**Resultado esperado:** o fluxo `AskUserQuestion` mantém exatamente o contrato
HTTP, o hook, a UX, a prioridade e o comportamento multi-monitor atuais, mas
passa a ter estado e efeitos testáveis sem abrir o app.

**Arquitetura:** `AskState` + `AskAction` + `AskReducer` puros; `AskStore`
`@MainActor` como runtime observável; `NotchAPIServer` continua dono do
protocolo HTTP/polling; `AppDelegate` apenas compõe os serviços e entrega o
store às janelas.

**Spec:** `docs/superpowers/specs/2026-07-24-arquitetura-modular-design.md`  
**Pesquisa:** `docs/superpowers/specs/2026-07-24-arquitetura-modular-research.md`

## Restrições globais

- Deployment target macOS 14.2 em `project.yml`.
- SwiftUI continua responsável pela UI; AppKit continua responsável por janela,
  teclado e integrações do sistema.
- Não adicionar TCA nesta fase.
- Não alterar o contrato de `POST /ask`, `GET /ask/<id>` ou
  `POST /ask/<id>/cancel`.
- Não alterar o formato que `tools/claude-hook/knobler-ask.sh` devolve ao
  Claude Code.
- Não alterar a prioridade visual: pergunta continua acima de mensagem,
  ditado, notificação, HUD, AirPods, música e Pomodoro.
- Uma resposta/cancelamento continua vencendo nos múltiplos monitores.
- Stores e coordenadores de UI devem ser `@MainActor`.
- Comentários e strings de UI em pt-BR; simplificações deliberadas recebem
  `// ponytail:`.
- Arquivos novos sob `Knobler/` exigem `xcodegen generate` antes do build.
- O projeto não possui test target; self-check standalone, snapshot, build e
  E2E continuam sendo a validação oficial.

---

## Fase 0 — descoberta de documentação e contratos

**Objetivo:** fixar as APIs permitidas e os contratos locais antes de escrever
código.

### Fontes oficiais consultadas

- [Apple — Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app): Observation está disponível no macOS 14; `@Observable` é a API de modelo observável.
- [Apple — Observation](https://developer.apple.com/documentation/observation): `@Observable` gera o suporte de observação; não aplicar apenas o protocolo `Observable`.
- [Apple — MainActor](https://developer.apple.com/documentation/swift/mainactor): isolamento do estado de UI no executor principal.
- [Apple — Organizing your code with local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages): packages locais são uma opção de modularização no mesmo repositório; não são necessários para este piloto.
- [TCA — Getting started](https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/gettingstarted/): referência conceitual para State/Action/Reducer/Store/Effect; TCA não será dependência nesta fase.

### Padrões locais a seguir

- `Knobler/Ask.swift:13-42`: modelos atuais `AskOption`, `AskQuestion`,
  `AskRequest` e `AskAnswer`.
- `Knobler/Ask.swift:48-232`: layout, semântica de seleção, paginação e
  submissão do card atual.
- `Knobler/NotchViewModel.swift:99-114`: prioridade atual dos modos.
- `Knobler/NotchViewModel.swift:318-374`: fila e lifecycle atuais do Ask.
- `Knobler/NotchAPIServer.swift:29-45`: callbacks e estado pending atuais.
- `Knobler/NotchAPIServer.swift:95-105`: regra de primeira resposta vence.
- `Knobler/NotchAPIServer.swift:184-255`: parsing e endpoints HTTP do Ask.
- `Knobler/KnoblerApp.swift:335-342`: fan-out atual da API para os monitores.
- `Knobler/KnoblerApp.swift:551-560`: retorno de resposta/cancelamento ao
  servidor e limpeza entre monitores.
- `Knobler/KnoblerApp.swift:591-607`: regra de `allowsKeyboard` da janela.
- `tools/snapshot.sh:6-39`: lista manual de fontes do harness.
- `tools/main.swift`: cenários `ask-simple`, `ask-multiselect`, `ask-preview` e
  `ask-paged`.

### APIs permitidas

- `@Observable` e `@Bindable` do módulo `Observation`, com disponibilidade
  macOS 14+.
- `@MainActor` para `AskStore` e métodos que mutam estado observado.
- `Task`/`async` apenas para executar efeitos de resolve/cancel; o reducer
  permanece síncrono e puro.
- `@Environment`/`@Bindable` de SwiftUI para passar o store às views.
- `DispatchQueue.main` somente nos adaptadores legados que ainda exigirem
  callback; o store não deve depender diretamente de `DispatchQueue`.

### Anti-padrões guardados

- Não usar `@ObservedObject` em um tipo que foi convertido para `@Observable`.
- Não criar um `AskStore` por monitor; o estado do Ask deve ser único no app.
- Não fazer o reducer chamar `NotchAPIServer`, `NSSound`, `NSEvent` ou
  `DispatchQueue` diretamente.
- Não duplicar `selected`, `answers`, `askPage` ou `askText` entre as views.
- Não inventar `@Reducer`, `TestStore`, `Effect` ou APIs TCA sem adicionar TCA.
- Não mover o estado HTTP pending para a UI: polling e TTL continuam no servidor
  até uma fase posterior de separação de infraestrutura.

**Verificação da fase:** confirmar que os arquivos e linhas acima ainda existem
antes de iniciar a Fase 1. Se uma API divergir, atualizar este plano antes de
implementar.

---

## Fase 1 — caracterização e testes do comportamento atual

**Objetivo:** criar uma rede de segurança antes de remover o estado antigo.

### O que implementar

Criar `tools/askcheck.swift` e testes puros para documentar as invariantes:

- primeira pergunta recebida vira ativa;
- pergunta seguinte entra em FIFO;
- mesma ID não duplica ativa nem fila;
- página começa em zero para uma pergunta nova;
- seleção multi-select alterna labels;
- resposta textual substitui/vence labels quando o card envia texto;
- submissão de página intermediária preserva respostas anteriores;
- submissão da última página produz todas as respostas;
- cancelamento limpa a pergunta ativa e não emite resposta;
- resposta/cancelamento repetido são no-op;
- `clear(id:)` remove a ativa ou uma pergunta enfileirada;
- a próxima pergunta é promovida após concluir a atual.

Não testar ainda a UI ou `NWListener`; esses comportamentos serão cobertos nas
fases de integração.

### Arquivos

- Create: `tools/askcheck.swift`
- Nenhuma mudança comportamental em `Knobler/` nesta fase.

### Referências

- Copiar o formato de self-check de `tools/wirecheck/main.swift`.
- Copiar o formato de `#if ..._SELFCHECK` de `Knobler/Reminders.swift` apenas
  como convenção; o novo check deve ser um executável separado para não
  introduzir `@main` no target do app.

### Verificação

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/AskModels.swift Knobler/AskFeature.swift \
  tools/askcheck.swift -o /tmp/askcheck
/tmp/askcheck
```

Esperado: `ask feature self-check ok`.

Também executar o build atual e os snapshots antes de qualquer alteração
estrutural, registrando o resultado no handoff da sessão.

### Anti-padrões

- Não importar SwiftUI no reducer/check puro.
- Não testar com `sleep` real ou `Date()` não controlada.
- Não alterar o protocolo HTTP nem a UI para fazer o check passar.

---

## Fase 2 — modelos, estado e reducer puro

**Objetivo:** criar a lógica de domínio sem efeitos e sem dependência de UI.

### O que implementar

#### 2.1 Extrair modelos

Criar `Knobler/AskModels.swift` movendo, sem mudança semântica, os quatro
modelos de `Knobler/Ask.swift:13-42`:

- `AskOption`
- `AskQuestion`
- `AskRequest`
- `AskAnswer`

Remover as definições duplicadas de `Ask.swift`, mantendo nele somente a view.

#### 2.2 Criar estado e ações

Criar `Knobler/AskFeature.swift` com Foundation בלבד:

```swift
struct AskState: Equatable {
    var active: AskRequest?
    var queue: [AskRequest] = []
    var page = 0
    var selected: Set<String> = []
    var answers: [String: AskAnswer] = [:]
    var text = ""
}

enum AskAction: Equatable {
    case enqueue(AskRequest)
    case toggle(label: String)
    case submit(labels: [String], text: String?)
    case appendText(String)
    case cancelActive
    case clear(id: String)
    case externalDismiss(id: String)
}

enum AskEffect: Equatable {
    case resolve(id: String, answers: [String: AskAnswer])
    case cancel(id: String)
}
```

Os nomes podem ser ajustados durante a implementação, mas o estado precisa ser
único e conter toda a seleção/paginação hoje espalhada entre `NotchViewModel` e
`AskCardView`.

#### 2.3 Implementar reducer puro

Criar `AskReducer.reduce(state:action:) -> [AskEffect]` ou equivalente
documentado, seguindo as regras:

- `enqueue` deduplica por `id` e promove quando não há ativa;
- promoção reseta `page`, `selected`, `answers` e `text`;
- `toggle` só altera seleção em pergunta multi-select;
- `submit` grava a resposta pela chave `question.question`;
- em página intermediária, incrementa `page` e limpa input corrente;
- na última página, produz `.resolve` e limpa a ativa;
- `cancelActive` produz `.cancel` e limpa a ativa;
- `clear` pode remover ativa ou item pendente sem emitir efeito;
- ações inválidas são no-op.

O reducer não deve saber que a resposta será enviada por HTTP nem que a view
está no notch.

### Arquivos

- Create: `Knobler/AskModels.swift`
- Create: `Knobler/AskFeature.swift`
- Modify: `Knobler/Ask.swift` (somente remover modelos duplicados)
- Modify: `tools/askcheck.swift` (usar os novos tipos)

### Referências

- Copiar os modelos existentes de `Knobler/Ask.swift:13-42`, preservando
  comentários e compatibilidade.
- Copiar as transições existentes de `Knobler/NotchViewModel.swift:333-372`,
  mas expressá-las como ações/estado/efeitos.
- Usar `Pomodoro.advance` em `Knobler/Pomodoro.swift` como exemplo local de
  lógica de domínio pura.

### Verificação

- `/tmp/askcheck` passa.
- `rg` confirma que `AskFeature.swift` não importa SwiftUI, AppKit ou Network.
- `rg 'NotchViewModel|NotchAPIServer|DispatchQueue|NSSound' Knobler/AskFeature.swift`
  não retorna referências.
- Os quatro modelos têm os mesmos campos e inicializadores usados pelo hook,
  snapshots e servidor.

### Anti-padrões

- Não guardar `NSFocusState`, hover ou `TextField` no domínio.
- Não usar `Date()` no reducer.
- Não criar efeitos assíncronos dentro de `AskReducer`.
- Não adicionar lógica de prioridade visual aqui; isso pertence ao root do
  notch.

---

## Fase 3 — `AskStore` observável e dependências

**Objetivo:** criar o runtime `@MainActor` que aplica ações e executa efeitos,
sem ainda trocar toda a UI.

### O que implementar

Criar `Knobler/AskStore.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class AskStore {
    private(set) var state = AskState()

    struct Dependencies {
        var resolve: @Sendable (String, [String: AskAnswer]) async -> Void
        var cancel: @Sendable (String) async -> Void
    }

    let dependencies: Dependencies

    init(dependencies: Dependencies) { self.dependencies = dependencies }

    func send(_ action: AskAction) { ... }
}
```

Detalhes obrigatórios:

- `send` chama o reducer de forma síncrona na Main Actor;
- efeitos são disparados em `Task` e não bloqueiam a UI;
- closures de dependência não capturam `NotchViewModel`;
- efeitos de resolve/cancel são idempotentes no servidor, mas o store também
  deve limpar a UI apenas uma vez;
- adicionar `injectPreview`/inicializador de preview somente se o harness
  precisar, sem expor mutação livre em produção.

### Arquivos

- Create: `Knobler/AskStore.swift`
- Modify: `Knobler/KnoblerApp.swift` (instanciar uma única vez, provisoriamente)

### Referências

- Seguir a documentação da Apple para `@Observable` e `@Bindable`.
- Seguir `MainActor` para isolamento do store.
- O conceito de dependências/efeitos é inspirado na documentação do TCA, mas
  implementar somente closures locais; não copiar APIs TCA inexistentes no
  projeto.

### Verificação

- O projeto compila com `xcodegen generate` e build Debug.
- `AskStore` existe uma vez no processo, não por monitor.
- O check puro continua compilando sem `AskStore`.
- Teste manual temporário: enviar duas perguntas, verificar FIFO e duplicação.

### Anti-padrões

- Não usar `@Published` dentro de uma classe `@Observable`.
- Não usar `@ObservedObject` para observar `AskStore`.
- Não transformar `AskStore` em singleton.
- Não deixar `AskStore` chamar `apiServer` diretamente; usar `Dependencies`.

---

## Fase 4 — integração com `NotchAPIServer` e composição

**Objetivo:** conectar a fonte HTTP e os efeitos do store, preservando o
contrato existente.

### O que implementar

#### 4.1 Manter o servidor como gateway HTTP

Não mover `pendingAsks` nesta fase. `NotchAPIServer` continua responsável por:

- parsear `POST /ask`;
- armazenar pending/answered/cancelled;
- responder polling;
- aplicar TTL;
- emitir `onAsk` e `onAskDismiss`.

Adicionar uma API tipada ou manter closures temporariamente, mas remover a
regra de negócio do fan-out do AppDelegate. A direção recomendada é:

```swift
apiServer.onAsk = { [weak askStore] request in
    askStore?.send(.enqueue(request))
}
apiServer.onAskDismiss = { [weak askStore] id in
    askStore?.send(.externalDismiss(id: id))
}
```

#### 4.2 Injetar efeitos

Na composição do app, configurar:

```swift
AskStore.Dependencies(
    resolve: { [weak apiServer] id, answers in
        apiServer?.resolveAsk(id: id, answers: answers)
    },
    cancel: { [weak apiServer] id in
        apiServer?.cancelAsk(id: id)
    }
)
```

Se a assinatura do servidor não for `async`, encapsular a chamada síncrona no
adaptador e retornar imediatamente; não inventar async no `NotchAPIServer`.

#### 4.3 Som de chegada

O som `Pop` deve permanecer no boundary de composição/API, como hoje em
`KnoblerApp.swift:336-338`, ou ser uma dependência `playArrivalSound`. Não deve
ficar no reducer.

#### 4.4 Diagnóstico

`GET /status` deve continuar reportando `ask.pending`. A fonte pode passar a ser
`askStore` se isso não duplicar estado HTTP; durante o piloto, manter
`apiServer.askDiagnostics` para representar pending do polling.

### Arquivos

- Modify: `Knobler/KnoblerApp.swift`
- Modify: `Knobler/NotchAPIServer.swift` somente se a interface tipada for
  necessária
- Create/Modify: composição do `AskStore` conforme a implementação da Fase 3

### Referências

- `Knobler/NotchAPIServer.swift:95-105` para primeira resposta vencer.
- `Knobler/NotchAPIServer.swift:184-255` para não alterar endpoints.
- `Knobler/KnoblerApp.swift:335-342` para chegada e dismiss.
- `tools/claude-hook/knobler-ask.sh` para o contrato externo que deve permanecer.

### Verificação

- `curl -X POST localhost:4477/ask` ainda retorna `200`.
- Polling retorna `answered:false` enquanto pendente.
- Resolver pelo store faz `GET /ask/<id>` retornar a mesma estrutura anterior.
- Cancelar pelo store faz `GET /ask/<id>` retornar `cancelled:true`.
- Resolver duas vezes não altera a resposta já registrada.
- O hook continua funcionando sem alterações.

### Anti-padrões

- Não mudar status HTTP, nomes de campos ou TTL nesta refatoração.
- Não fazer o `NotchAPIServer` conhecer SwiftUI/store.
- Não duplicar `pendingAsks` dentro do `AskStore`.
- Não fazer a API distribuir diretamente para cada monitor.

---

## Fase 5 — migração da UI e fan-out multi-monitor

**Objetivo:** fazer todas as janelas consumirem a mesma fonte de verdade do
`AskStore`, removendo o estado Ask do `NotchViewModel`.

### O que implementar

#### 5.1 Migrar `AskCardView`

Em `Knobler/Ask.swift`:

- trocar `@ObservedObject var vm` por uma referência ao `AskStore` e manter
  `NotchViewModel` apenas para fases de ditado necessárias à UI;
- remover `@State selected` e `@State answers`;
- ler página, seleção, respostas e texto do store;
- enviar `AskAction` para seleção, submissão, texto e cancelamento;
- preservar hover local, foco local e preview local;
- usar `@Bindable` somente para bindings necessários ao campo de texto, conforme
  a documentação de Observation.

O campo de texto deve continuar recebendo texto por ditado. O valor agora será
  alterado por `askStore.send(.appendText(text))`.

#### 5.2 Migrar `NotchView`

Em `Knobler/NotchView.swift`:

- receber o `AskStore` compartilhado;
- derivar `question` quando `askStore.state.active != nil`;
- substituir referências de Ask em `vm.mode`, `vm.ask`, `vm.askPage` e
  `vm.askText` por uma propriedade de apresentação local que combine o estado
  do root com o store;
- manter a forma, animações, tamanho e transições existentes;
- não alterar os demais modos.

Durante a migração é aceitável manter `Mode.question` como enum de
apresentação, mas sua decisão deve vir do store, não de estado duplicado no VM.

#### 5.3 Migrar AppDelegate e teclado

Em `Knobler/KnoblerApp.swift`:

- passar o mesmo `AskStore` ao `NotchView` de cada monitor;
- remover `onAskAnswered` e `onAskCancelled` por monitor;
- alterar `dictation.transcriptSink` para escrever no store uma vez, não fazer
  fan-out de `askText` em cada VM;
- derivar `allowsKeyboard` de `askStore.state.active` junto dos estados de
  mensagem/tab/expanded;
- atualizar `peekShelf` e diagnósticos para consultar o store quando necessário.

#### 5.4 Remover estado legado

Somente depois de todos os consumidores compilarem e os testes passarem,
remover de `NotchViewModel`:

- `ask`;
- `askPage`;
- `askText`;
- `askQueue`;
- `onAskAnswered`;
- `onAskCancelled`;
- `enqueueAsk`, `clearAsk`, `answerAsk`, `cancelActiveAsk`.

### Arquivos

- Modify: `Knobler/Ask.swift`
- Modify: `Knobler/NotchView.swift`
- Modify: `Knobler/NotchViewModel.swift`
- Modify: `Knobler/KnoblerApp.swift`
- Modify: `Knobler/IncomingMessageView.swift` somente se a assinatura de
  dependência compartilhada exigir ajuste; evitar tocar sem necessidade

### Referências

- `Knobler/Ask.swift:48-232` para preservar o layout.
- `Knobler/NotchView.swift:52-128` para shape/mask/transitions.
- `Knobler/NotchView.swift:142-151` para não reabrir música ao interagir com
  pergunta.
- `Knobler/KnoblerApp.swift:551-607` para substituir wiring por store único.
- Cenários Ask em `tools/main.swift`.

### Verificação

- Todos os monitores mostram a mesma pergunta, página, seleção e texto.
- Clique em uma opção em qualquer monitor fecha o card em todos.
- Cancelamento por X/Esc preserva o fallback para o terminal.
- Ditado durante Ask preenche o campo uma única vez.
- O notch não reabre música depois de responder/cancelar.
- `NotchWindow.allowsKeyboard` continua falso sem Ask, resposta ou mensagens.
- Snapshots `ask-simple`, `ask-multiselect`, `ask-preview` e `ask-paged` continuam
  renderizando; se o `AskStore` for fonte nova, incluí-lo na lista manual do
  `tools/snapshot.sh` e criar estado preview determinístico.

### Anti-padrões

- Não deixar `AskCardView` manter uma cópia local de seleção/respostas.
- Não criar um store por `ScreenNotch`.
- Não usar `@EnvironmentObject` para um tipo `@Observable` sem seguir o padrão
  de Observation documentado.
- Não alterar layout para compensar uma falha de estado.
- Não remover o suporte a `TextField`/teclado durante a migração.

---

## Fase 6 — limpeza, documentação e rollback

**Objetivo:** fechar o piloto como uma unidade reversível e deixar evidência
para decidir sobre as próximas features.

### O que implementar

- Remover imports e Combine subscriptions que só existiam para Ask.
- Atualizar comentários em `NotchViewModel`, `NotchView` e `KnoblerApp`.
- Atualizar o spec de arquitetura com o resultado real do piloto.
- Registrar no `HANDOFF.md` decisões, limitações e qualquer workaround.
- Não extrair Swift Package ainda.
- Não migrar `NotificationFeature`, `MusicFeature` ou `AppSettings` nesta fase.

### Verificação final

```bash
xcodegen generate
xcodebuild -project Knobler.xcodeproj \
  -scheme Knobler -configuration Debug build
./tools/snapshot.sh
cd relay && npm test
```

Executar também:

- `/tmp/askcheck`;
- `Knobler --selfcheck` quando o binário estiver disponível;
- E2E real com o hook Ask;
- `GET /status` antes/durante/depois de uma pergunta;
- teste de dois monitores;
- teste de timeout do hook;
- teste de encerramento/reabertura do app com pergunta pendente.

### Guardas finais

```bash
rg 'askQueue|onAskAnswered|onAskCancelled|enqueueAsk|answerAsk|cancelActiveAsk' Knobler
```

Esperado: nenhuma ocorrência após a remoção definitiva, exceto referências
documentais explicitamente justificadas.

```bash
rg 'AskStore' Knobler tools
```

Esperado: uma composição live, referências de UI e referências de preview/check
controladas; nunca uma instância por monitor.

### Rollback

Cada fase deve ser um commit independente. Se o piloto falhar:

1. reverter a Fase 5 para restaurar o estado legado do `NotchViewModel`;
2. manter Fases 1–4 somente se os contratos e checks continuarem verdes;
3. se a composição do store for a causa, retornar temporariamente aos callbacks
   existentes sem alterar o protocolo HTTP;
4. registrar a causa no handoff antes de tentar novamente.

### Critério de conclusão

O piloto está completo quando:

- o estado Ask existe apenas no `AskStore`;
- o servidor segue responsável apenas pelo protocolo/polling;
- todas as janelas compartilham o mesmo store;
- os testes de domínio e E2E passam;
- o comportamento visual e de teclado não regrediu;
- o `AppDelegate` não contém regras específicas de Ask;
- a decisão de continuar com reducer próprio ou adotar TCA pode ser tomada com
  evidência do piloto.

## Próximo plano após o piloto

Se o piloto passar, repetir o padrão nesta ordem:

1. `NotificationFeature`;
2. `ActivityFeature`;
3. `MessagingFeature`;
4. `DictationFeature`;
5. `MusicFeature`;
6. settings e extração para Swift Packages.

Cada feature deve ter seu próprio plano e não aproveitar a migração para
alterar UX sem um spec separado.
