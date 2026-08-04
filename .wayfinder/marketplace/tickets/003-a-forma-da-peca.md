# A forma da peça

- map: ../map.md
- label: wayfinder:prototype
- status: closed
- assignee: claude (sessão 2026-08-04)
- blocked-by: —  (001 fechado)

## Question

O ticket central. O que uma feature precisa declarar pra ser peça, e quem lê
essa declaração.

Perguntas a fechar, com um stub em Swift que **compile** (`swiftc` solto, como
os harnesses) provando a forma:

- **O que a peça declara**: id estável (usado na preferência e no catálogo),
  nome e descrição pro usuário, ícone, e as superfícies que ela ocupa — seção do
  notch, painel de Ajustes, rotas da API, item de menu, permissão exigida.
- **Declaração é dado ou é código?** Um `struct` com campos (a peça é descrita) ou
  um `protocol` que cada feature implementa (a peça se comporta)? A diferença
  aparece na hora de ligar no meio do uso.
- **Quem monta a lista.** Um array literal num arquivo (`PluginRegistry.swift`,
  explícito e chato de esquecer) ou registro automático. Sem inventar
  descoberta mágica: Swift não tem reflexão barata e o gate de compilação é
  quem tem que gritar quando esquecerem.
- **Nascimento e morte.** Como o `AppDelegate` sai de "cria 15 serviços na mão"
  pra "cria os que estão ligados". O que a peça recebe (as dependências que hoje
  são injetadas na mão) e como ela devolve o serviço criado. E o que acontece
  no desligar: o serviço morre, e quem garante que o hook/timer/observer dele
  morreu junto (a promessa de custo zero depende disso).
- **Onde a superfície aparece**: a `NotchView` e o `SettingsView` passam a
  desenhar a partir da lista, ou continuam com o `switch` na mão? Custo zero
  exige que uma peça desligada nem apareça na iteração.

Não decidir aqui: onde a preferência é guardada (005), como se instala na tela
(006), qual feature é a cobaia (004).

O protótipo vira `.wayfinder/marketplace/prototypes/003-forma-da-peca.swift`.

## Restrições que 001 já entregou

- **Quatro features são `.shared`** (Espelho, Link, Nota, Anotação) e não nascem
  no `AppDelegate`. Um registro que só governe a criação lá não alcança elas.
- **Três padrões de toggle** convivem hoje, e dois deles não desligam nada (ver a
  tabela na resolução de 001). Dez das quinze features não têm como não nascer.
- **O tap do VolumeHUD é compartilhado**: o ditado consome o Right-Option dele
  (`KnoblerApp.swift:213`, `:230`). A forma da peça precisa de resposta pra
  "peça que depende de recurso de outra peça".
- **`publicar()` é o funil de sete features.** Provavelmente é serviço de base,
  não peça — mas então a declaração precisa distinguir "o que a peça usa" de
  "o que a peça oferece".

## Resolução (2026-08-04)

Protótipo: [`prototypes/003-forma-da-peca.swift`](../prototypes/003-forma-da-peca.swift).
Compila e roda sozinho, com seis asserções:

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  .wayfinder/marketplace/prototypes/003-forma-da-peca.swift \
  -o /tmp/formadapeca && /tmp/formadapeca
```

**A peça é dado, não protocolo.** Um `struct Plugin` com campos — `id`
(`PluginID`, string estável que vai pra preferência e pro catálogo), `nome`,
`descricao`, `simbolo`, e as superfícies `secao` / `painel` / `rotas` /
`permissao`, todas opcionais — mais **uma** função `nascer`. Protocolo foi
descartado: as quinze features já são classes distintas, e um `protocol` só
adicionaria uma camada de conformidade sem mudar nada no comportamento.

**A lista é um array literal** (`PluginRegistry.todos`), num arquivo só. Sem
descoberta automática: Swift não tem reflexão barata e o gate certo é de
compilação — `PluginRegistry.completo` compara os ids do registro com
`PluginID.allCases`, então esquecer de registrar uma peça quebra o check.

**Nascer é closure, e é isso que alcança os quatro `.shared`.** Feature que o
`AppDelegate` cria devolve o objeto novo; singleton (Espelho, Link, Nota,
Anotação) devolve um shim minúsculo que só chama `ligar()`/`desligar()`. Mesma
forma, dois modos de vida — resolve a restrição nº 1 de 001. `nascer` pode
devolver `nil` quando a peça decide não subir; não é erro.

**Morrer = `parar()` + soltar a referência.** `PluginHost.desinstalar` faz os
dois. É o único ponto de que a promessa de custo zero depende, e o check prova
os três casos: o timer parou, o singleton desligou, o serviço sumiu do host.

**Peça pergunta por peça** via `PluginDeps.instalado(_:)`, que devolve `false`
como caminho normal. Encarna a regra de 002 (Pomodoro→Descanso: a opção some,
sem avisar).

**Superfície de peça desligada nem é iterada.** `host.secoes` / `.paineis` /
`.rotas` filtram por instalado antes de mapear, então a `NotchView` e o
`SettingsView` passam a desenhar a partir da lista em vez do `switch` na mão —
mas sem custo nenhum pras peças ausentes.

**Quem manda na lista de seções do notch** (decidido com o dono nesta sessão):
o enum `NotchSection` **fica como está**, e a ficha da peça só cita o nome da
seção como texto. Um assert no check confere que todo nome citado existe no
enum. Descartado encolher o `NotchSection` pras seções de fábrica e deixar as
outras nascerem da lista de plugins: mexeria em `NotchSectionOrder`, no
ordenador, no `sectionordercheck` e na leitura da ordem salva do usuário — a
parte do app com mais regra sutil — antes mesmo de a cobaia estar escolhida. O
preço aceito é duas listas em sincronia, com o gate gritando se desalinharem.

Fora daqui de propósito: onde a preferência de instalado é guardada (005), a
tela de instalar (006), e qual é a cobaia (004).
