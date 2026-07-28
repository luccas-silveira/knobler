# Arquitetura modular e fluxo unidirecional — pesquisa

**Data:** 2026-07-24  
**Status:** pesquisa concluída  
**Spec relacionado:** `2026-07-24-arquitetura-modular-design.md`

## Pergunta

Qual é a evolução arquitetural mais adequada para o Knobler, considerando:

- app nativo macOS com SwiftUI + AppKit;
- alvo macOS 14.2+;
- integração intensa com APIs do sistema;
- múltiplos monitores e estado global distribuído;
- necessidade de preservar baixo consumo e comportamento atual;
- crescimento contínuo de features;
- desejo de melhorar testabilidade sem uma reescrita integral?

## Método

A análise combinou:

1. leitura integral dos arquivos-fonte do app, relay e ferramentas;
2. inspeção das fronteiras atuais entre UI, serviços e modelos;
3. consulta à documentação oficial da Apple sobre Observation, `MainActor` e
   Swift Packages locais;
4. consulta à documentação oficial do Composable Architecture sobre reducers,
   dependências e testes.

## Achados no código atual

### Pontos fortes

- O núcleo já usa Swift nativo e frameworks adequados ao sistema.
- Vários motores são puros e têm self-checks: `Pomodoro`, `Reminders`,
  `Descanso`, `Wire`, `MediaRemoteSource` e `TranscriptFormatter`.
- Integrações problemáticas são encapsuladas em serviços específicos, como
  `NotificationInterceptor`, `VolumeHUDController`, `LANMessaging` e
  `WebhookClient`.
- O harness de snapshot permite validar a UI sem depender sempre do app real.
- O relay possui separação razoável entre servidor, banco, hub, normalização,
  tokens e rate limiting.

### Gargalos arquiteturais

- `AppDelegate` concentra composição, ciclo de vida, regras de produto e
  fan-out para todos os monitores.
- `NotchViewModel` é um estado transversal de muitos domínios sem uma fronteira
  clara entre estado de negócio e estado de apresentação.
- `NotchView` é simultaneamente container, roteador visual e implementação de
  vários cards/features.
- `AppSettings.shared` combina persistência, defaults, identidade e mecanismo
  de observação global.
- Closures e `objectWillChange` formam uma malha implícita de eventos.
- Muitos serviços dependem diretamente de APIs concretas e de relógio/timers
  reais, o que dificulta testes determinísticos.
- O target único permite que qualquer arquivo conheça qualquer outro arquivo;
  as pastas ainda não são fronteiras verificadas pelo compilador.

Conclusão: a arquitetura atual não está errada; ela está em uma fase natural de
transição de app pequeno para produto com múltiplos domínios.

## Evidências externas

### Observation

A Apple disponibiliza Observation no macOS 14 e recomenda o macro `@Observable`
para tornar modelos observáveis, com rastreamento mais específico das
dependências da UI. Isso é compatível com o deployment target atual do Knobler.

Fontes:

- [Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [Observation](https://developer.apple.com/documentation/observation)
- [Migrating from ObservableObject to the Observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)

Implicação: novos stores devem preferir Observation, mas uma migração mecânica
de todos os `ObservableObject` não é necessária. Os pontos que ainda dependem de
`@EnvironmentObject` e compatibilidade com o harness podem migrar
incrementalmente.

### Isolamento de UI e concorrência

`MainActor` é o global actor cujo executor equivale à fila principal. Isso
fornece uma fronteira explícita para stores e coordenadores que mutam estado
observado pela UI.

Fonte:

- [MainActor](https://developer.apple.com/documentation/swift/mainactor)

Implicação: stores de feature e coordenação de janelas devem ser `@MainActor`;
rede, parsing pesado, persistência e engines de áudio devem permanecer fora da
Main Actor, usando `actor` ou isolamento próprio.

### Swift Packages locais

A Apple recomenda local Swift Packages para organizar código do mesmo
repositório, simplificar manutenção e criar modularidade. A documentação também
indica networking e utilities como bons candidatos iniciais.

Fonte:

- [Organizing your code with local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages)

Implicação: a modularização física é válida, mas deve acontecer depois de as
interfaces estabilizarem. Extrair código para packages antes de definir as
fronteiras apenas moveria o acoplamento de lugar.

### Composable Architecture

O TCA formaliza exatamente os conceitos desejados: `State`, `Action`, reducer,
effects, dependências substituíveis e `TestStore`. A documentação destaca que
reducers evoluem o estado a partir de ações e retornam efeitos, e que relógios
controláveis tornam timers testáveis.

Fontes:

- [TCA — Getting started](https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/gettingstarted/)
- [TCA — Reducer](https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/reducer/)
- [TCA — Testing](https://pointfreeco.github.io/swift-composable-architecture/main/documentation/composablearchitecture/testing/)

Benefícios relevantes para o Knobler:

- transições de Ask, notificações e mensagens ficam explicitamente testáveis;
- efeitos de timer, rede e persistência podem ser substituídos;
- features podem ser compostas sem ampliar o `AppDelegate`.

Custos relevantes:

- nova dependência externa e novo vocabulário para toda a equipe;
- migração mais invasiva da UI e dos objetos observáveis atuais;
- maior complexidade de integração com serviços AppKit de longa duração;
- risco de transformar uma refatoração incremental em reescrita arquitetural.

Conclusão: TCA é tecnicamente adequado, mas não é requisito imediato. O
Knobler deve adotar primeiro os contratos conceituais de TCA em uma camada
própria e reavaliar depois de um piloto real.

## Alternativas avaliadas

| Alternativa | Resultado | Motivo |
|---|---|---|
| Manter MVVM/closures atual | rejeitada como estratégia final | não resolve concentração nem rastreabilidade |
| Migrar tudo para `@Observable` | insuficiente sozinha | melhora observação, mas não define efeitos/composição |
| TCA imediato | adiado | forte, porém invasivo para o estágio atual |
| Reducer próprio + Observation | escolhida | ganho arquitetural com risco controlado |
| Modularizar primeiro em Packages | adiada | fronteiras ainda precisam amadurecer |
| Reescrever em framework multiplataforma | rejeitada | piora integração nativa do macOS |

## Decisão de pesquisa

Adotar uma arquitetura unidirecional própria, inspirada em TCA, com:

- `State`, `Action`, `Effect` e `Dependencies` por feature;
- stores `@MainActor`;
- Observation para stores novos;
- protocolos somente nas bordas de infraestrutura;
- composição central pequena;
- migração de uma feature por vez;
- possibilidade de adotar TCA posteriormente sem descartar o modelo mental.

## Piloto recomendado

O piloto deve ser `AskFeature`, porque contém quase todos os problemas que a
refatoração pretende resolver:

- fila e prioridade;
- estado paginado;
- timers/TTL no servidor;
- input de UI;
- efeitos externos;
- sincronização entre múltiplos monitores;
- contrato HTTP que precisa permanecer estável;
- comportamento fácil de cobrir com testes de transição.

`WebhookFeature` é o segundo melhor piloto, mas possui mais dependência de rede,
Keychain e relay. `MusicFeature` não deve ser o primeiro: mistura stream de
processo, artwork, CoreAudio e comportamento visual de alta frequência.

## Hipóteses a validar durante o piloto

1. Um store próprio consegue representar a fila de Ask sem duplicar estado
   entre monitores.
2. Os efeitos podem ser injetados sem abstrair o WindowServer inteiro.
3. `@Observable` não quebra o consumo pelo harness de snapshots.
4. O `AppDelegate` pode ficar apenas com composição e lifecycle.
5. O fan-out de múltiplas telas pode ser modelado como projeção de um estado
   global, sem cada monitor possuir regras próprias.
6. Timers de dismiss podem ser testados com um relógio injetável.

## Experimento mínimo

Antes de migrar toda a feature:

1. criar `AskState` e `AskAction` sem alterar a UI;
2. escrever testes para receber, enfileirar, paginar, responder e cancelar;
3. criar dependências fake para resolver/cancelar no `NotchAPIServer`;
4. conectar uma única tela ao novo store;
5. conectar o fan-out das demais telas;
6. rodar snapshots, self-checks e build Debug;
7. comparar diagnóstico `/status` antes/depois;
8. somente então remover o estado antigo do `NotchViewModel`.

## Critérios para decidir sobre TCA depois

Adotar TCA após o piloto somente se pelo menos dois destes sinais aparecerem:

- reducers próprios repetem boilerplate significativo;
- composição de features exige infraestrutura manual difícil de manter;
- testes de efeitos precisam de uma solução equivalente ao `TestStore`;
- novas features começam a duplicar mecanismos de dependência e clocks;
- a equipe pretende padronizar a arquitetura em outros apps Swift.

Não adotar TCA apenas por ser conhecido ou por estética de framework.

## Próxima fase

A pesquisa está encerrada. A próxima atividade é um plano de implementação para
o piloto `AskFeature`, contendo:

- arquivos a criar e alterar;
- ordem dos passos;
- estratégia de compatibilidade temporária;
- testes red/green;
- pontos de rollback;
- atualização do spec de design após os resultados.

