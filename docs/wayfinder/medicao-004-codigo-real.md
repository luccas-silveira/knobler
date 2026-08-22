# Medição 004 — Os eventos no código real

Método: o mesmo harness das medições [001](medicao-001-repro.md) e
[003.1](medicao-003-1-ambiente.md) — a `NotchView` de verdade numa `NSHostingView`
dentro de uma janela fora de qualquer tela, fotografada a cada giro de runloop e
classificada pixel a pixel em fundo, moldura e conteúdo, com a **lacuna de topo** como
métrica —, agora dirigido contra o código que o usuário de fato executa. A 003.1 mediu num
worktree onde `applyVisibility` não existia e dirigiu a *forma* do evento (esconder,
esperar, devolver); o commit `f8684aa` trouxe o código real, e esta medição dirige a
*decisão* e os *chamadores*: uma réplica literal de `fullscreenDisplays()`
(`Knobler/KnoblerApp.swift:1040`) e de `applyVisibility()` (`:1073`), acionadas pelos três
lugares que as chamam com as cadências deles — o fim do `placeWindows` (`:1269`), 0,35 s
depois de cada troca de Space (`:371`-`374`) e **cada** mudança em `AppSettings`
(`:377`-`378`, com a assinatura de `objectWillChange` de verdade e o mesmo hop de
`DispatchQueue.main.async`). A janela do harness deixou de ser uma `NSWindow` comum e passou
a ser a `NotchWindow` de verdade. Nada em `Knobler/*.swift` foi tocado: a réplica e a
instrumentação vivem no envelope (`tools/cortecheck/main.swift`).

> **Nota de validade.** O código que esta medição dirige — `applyVisibility`,
> `fullscreenDisplays` e o observador de troca de Space — existe **só no intervalo entre o
> commit `f8684aa` e o merge deste branch**. Ele é trabalho local do usuário, trazido pro
> worktree para ser medido, e sai do branch no revert do `f8684aa`. No `master`,
> `grep -n 'applyVisibility' Knobler/KnoblerApp.swift` volta a devolver **vazio** até o
> usuário commitar o trabalho dele, e com ele todas as linhas de `KnoblerApp.swift` citadas
> aqui. O que a medição afirma continua valendo sobre o código que o usuário **roda**; o que
> envelhece é onde achá-lo.

## O número

**8 transições novas, 68 chamadas de `applyVisibility` dirigidas, 106 varreduras de
`fullscreenDisplays()` na main thread, 87 eventos de janela dirigidos. 0 produziram lacuna
de topo: `lacuna_topo_max = 0,0 pt` nas oito — e desta vez as oito têm sensibilidade
demonstrada.** O `corte` também é 0 nas oito, e a varredura inteira — 35 da 001, 8 da 003.1
e estas 8 — fecha em **51 combinações, 0 corte**.

| Transição | O que dirige | Quadros | Cadência | Lacuna de topo |
|---|---|---|---|---|
| `real-ajustes-parado` | pilulinha parada, 12 mudanças em `AppSettings` a 20 Hz → 12 `applyVisibility` | 145 | 67 Hz | 0,0 pt |
| `real-ajustes-durante-morph` | o mesmo com a mola correndo: 16 mudanças a 50 Hz no meio do card fechando | 29 | 12 Hz | 0,0 pt |
| `real-ajustes-rajada` | 30 mudanças no **mesmo giro** (o que um campo de texto dos Ajustes faz) → 30 `applyVisibility` de uma vez, no morph | 29 | 11 Hz | 0,0 pt |
| `real-espaco-entra-telacheia` | a troca de Space de verdade: 0,35 s → `applyVisibility` → `orderOut`; 0,35 s → `applyVisibility` → `orderFrontRegardless` | 196 | 68 Hz | 0,0 pt |
| `real-espaco-durante-morph` | o `applyVisibility` atrasado caindo **dentro** da mola (troca a 0,05 s, efeito a 0,40 s) | 36 | 12 Hz | 0,0 pt |
| `real-placewindows-applyvisibility` | o fim do `placeWindows`: `setFrame(igual, display: true)` + `applyVisibility` — **um** `orderFrontRegardless`, vindo de dentro do `applyVisibility` (a réplica dirige um a mais, herdado da 003.1 — ver limites) | 22 | 10 Hz | 0,0 pt |
| `real-telacheia-liga-desliga` | o interruptor "ocultar em tela cheia": muda `AppSettings` **e** vira o ramo da decisão, 4 vezes | 189 | 67 Hz | 0,0 pt |
| `real-fullscreendisplays-varredura` | só o syscall: `CGWindowListCopyWindowInfo` na main thread a 33 Hz durante a mola, sem tocar na janela | 67 | 23 Hz | 0,0 pt |

Contagem de quadros e cadência são de uma corrida específica e dependem da máquina; a
lacuna de topo e o veredicto, não.

## Sensibilidade: 8 de 8, nas duas formas

Este é o ponto em que a 004 passa da 003.1, que fechou com **5 das 8 sem sensibilidade
demonstrada**. A injeção da 003.1 era gateada em `!janela.isVisible` — só existia com a
janela fora de ordem —, então as transições que nunca escondem a janela nunca a viam. Aqui
o gate é o **ponto de acionamento do código real**: o defeito de 40 pt liga no fim de
`applyVisibility` e no fim de `fullscreenDisplays()`, ou seja, exatamente onde o código sob
suspeita roda. Duas formas, cada uma respondendo uma pergunta diferente:

- **Persistente no acionamento** (liga e fica): responde *"esta transição chega a fotografar
  depois de dirigir o código?"*. **8 de 8 acusaram 40,0 pt**, em 2 de 2 corridas — de
  11/29 quadros na mais lenta a 101/102 na mais rápida.
- **Transiente de 150 ms** (o mesmo tamanho de defeito que passou inteiro pela
  `ambiente-orderout-durante-morph` da 003.1): responde *"a cadência desta transição pega um
  defeito curto?"*. **8 de 8 acusaram 40,0 pt**, em 2 de 2 corridas — de 1/24 quadros a
  24/171.

O transiente passa aqui e falhou na 003.1 pelo motivo simples: lá havia **um** ponto de
acionamento por transição, aqui há de 2 a 30. Um defeito de 150 ms ligado 30 vezes é fácil
de pegar; ligado uma vez, a 10 Hz, não é. Isso não conserta o buraco de cadência — só diz
que estas oito transições não estão dentro dele.

## Os controles

Os quatro da 001 e os dois da 003.1 continuam valendo, continuam abortando com código 1, e
continuam passando com a janela trocada:

- detector sintético: excedente **100,0 pt**;
- desvio de 60 pt na `NotchView` real: lacuna **60,0 pt**;
- 2ª câmera aferida: `cacheDisplay = 32,0 pt`, camada = **32,0 pt**, concordam;
- janela fora de ordem não cega a foto: alturas **todas 32**;
- desvio de 60 pt **atravessando** o `orderOut`: **60,0 pt** e corte em todos os quadros;
- controle positivo: 5–8 alturas distintas, a animação corre.

## O que o código real fez de fato, chamada por chamada

```
applyVisibility→orderFrontRegardless:  67 dirigidos,  1 com mudança observável
applyVisibility→orderOut:               1 dirigido,   1 com mudança observável
chamadas de applyVisibility:           68  (mudanças em AppSettings: 58)
fullscreenDisplays():                 106 varreduras na main thread
```

Os **66 `orderFrontRegardless` sem mudança observável não são eventos que não aconteceram**
— são o achado. `applyVisibility` ordena a janela pra frente toda vez que roda, mesmo com a
janela já visível, e é esse o ramo que roda a cada mudança de Ajuste. Não há estado de
`NSWindow` que flipe nesse caso; a chamada **é** o evento, e ela está registrada com o antes
e o depois como todas as outras. O par com mudança observável é o ciclo esconder/devolver da
`real-espaco-entra-telacheia`.

## O custo de `fullscreenDisplays()` — o número novo desta medição

`applyVisibility` chama `fullscreenDisplays()` sempre que `ocultarEmTelaCheia` está ligado, e
essa chave **vem ligada por padrão** (`AppSettings.swift:260`, `flag()` devolve `true` quando
a chave não existe) e **não está gravada** no `com.zoi.knobler.plist` do usuário — ou seja, a
varredura roda na máquina dele.

**106 varreduras: mediana ~0,3–0,8 ms, máximo ~14–21 ms, total ~73–188 ms** — oito corridas,
minhas e da revisão. São **ordens de grandeza, não valores a bater**: o custo do
`CGWindowListCopyWindowInfo` depende de quantas janelas o sistema tem abertas na hora. O que
sobrevive à variação é a forma: submilissegundo na mediana, **mais de um quadro a 60 Hz no
pior caso**. Ele é síncrono, roda na main thread, e cai no mesmo giro de runloop que a
animação da `NotchView` precisa para desenhar. Numa rajada de Ajustes são 30 dessas
varreduras no mesmo giro.

Isso é um custo medido, **não uma causa**: `real-fullscreendisplays-varredura` roda 40
varreduras a 33 Hz durante a mola, sem tocar na janela, e a lacuna de topo continua 0,0 pt.
O que está medido é que o caminho existe e é caro; que ele produza o corte, não.

Nesta máquina, agora, o `CGWindowListCopyWindowInfo` apontou **nenhum** display em tela
cheia. Por isso o ramo do `orderOut` foi alcançado por uma **costura** declarada
(`telaCheiaForcada`), e não por uma tela cheia de verdade — ver os limites.

## Mudanças no instrumento, e por que

- **A janela do harness virou a `NotchWindow` de verdade** (nível `.mainMenu + 3`,
  `isOpaque = false`, `backgroundColor = .clear`, `.canJoinAllSpaces`, `.stationary`,
  `.fullScreenAuxiliary`), no lugar de uma `NSWindow` com `[.borderless]`. A 003.1 deixou
  isso escrito como "onde eu olharia se um dia um desses eventos virar suspeito outra vez";
  virou. `Knobler/NotchWindow.swift` entra **só** na linha de compilação do
  `tools/cortecheck.sh` e **não** em `tools/notchview-fontes.txt`, que o `snapshot.sh`
  também lê: ela não é fonte da `NotchView`. As 43 combinações da 001 e da 003.1 seguem em
  **0 corte** com a janela trocada, e os seis controles passam.
- **Réplica, não chamada.** `applyVisibility` e `fullscreenDisplays` são `private` de um
  `AppDelegate` que não entra nesta compilação (o `@main` brigaria com o código top-level do
  harness). O que roda é uma cópia — ver a seção de limites para o que é real e o que é
  réplica.
- **`AppSettings` de verdade, mexida de verdade.** O harness não tem bundle id, então o
  `UserDefaults.standard` dele mora em `~/Library/Preferences/cortecheck.plist` e não encosta
  no `com.zoi.knobler.plist` do usuário — verificado, e os valores mexidos são devolvidos no
  fim da corrida de qualquer jeito. A `NotchView` observa `AppSettings.shared` direto
  (`NotchView.swift:17`), então cada mudança reavalia o corpo dela no harness igual ao app.

## Limites — o que este "0 de 8" não cobre

- **É réplica da decisão, não a função do app.** São reais: a assinatura de
  `AppSettings.objectWillChange` com o hop de `main.async`, o `CGWindowListCopyWindowInfo`,
  as chamadas de `NSWindow` e a `NotchWindow`. São réplica: o corpo das duas funções (copiado
  literalmente) e a cadência dos chamadores. Se o defeito estiver numa linha que a cópia não
  reproduz, esta medição não o vê.
- **A réplica do `placeWindows` é a forma PRÉ-`f8684aa`, e dirige um evento a mais que o
  app.** `placeWindowsFalso` foi herdado da 003.1 e faz `setFrame(igual, display: true)`
  **seguido de `orderFrontRegardless()`**, que era o que o `placeWindows` fazia nas linhas
  1195-1196 do worktree antigo. No código medido esse `orderFrontRegardless` **não existe
  ali**: `placeWindows` faz `setFrame(frame, display: true)` (`:1256`) e, no fim,
  `applyVisibility()` (`:1269`) — e o **único** `orderFrontRegardless` do arquivo está
  dentro do `applyVisibility` (`:1077`), que o comentário de `:1071` chama de "único lugar
  que ordena a janela pra frente". Ou seja: `real-placewindows-applyvisibility` dirige
  **dois** ordenamentos onde o app dirige **um**. Isso não derruba o negativo — o harness
  dirige um superconjunto do que o app faz, e o subconjunto puro (`setFrame` sozinho) já
  está coberto em 0,0 pt pelas duas `ambiente-setframe-*` da 003.1. O `placeWindowsFalso`
  ficou como está de propósito: corrigi-lo mudaria os 68/106/87 e o MD5 do determinismo,
  forçando uma remedição inteira para trocar um superconjunto por um subconjunto já medido.
- **Uma janela, não N.** `applyVisibility` percorre `notches` e ordena **todas** as janelas
  numa varredura só. O harness tem uma. Se o corte nascer da interação entre duas janelas
  sendo ordenadas no mesmo giro — o caso multi-monitor —, ele está fora daqui.
- **O ramo do `orderOut` vem de uma costura.** Nenhum display estava em tela cheia durante a
  medição, e entrar em tela cheia de verdade mexeria na sessão gráfica do usuário. A costura
  força a decisão; o que ela **não** encena é o que o WindowServer faz de verdade numa
  troca de Space (o Space mudando, a composição, a janela `.canJoinAllSpaces` migrando).
- **A costura de tela cheia é fiel por sorte, não por construção.** `displayDaCena` é fixo
  em 1 (`tools/cortecheck/main.swift`), e nesta máquina o `CGDirectDisplayID` da tela
  principal é 1 — então o ramo real de `applyVisibility` bateria. Numa máquina onde não for,
  só a costura `telaCheiaForcada` alcança o `orderOut`, e o ramo real nunca dispararia.
- **Sono, troca de resolução e Space real continuam fora**, pelo mesmo motivo da 003.1: são
  eventos de sistema que atingem a máquina do usuário, não só o harness.
- **Cadência.** Continua o limite que morde: 10–23 Hz nas transições durante morph. As oito
  acusaram um defeito de 150 ms, mas porque cada uma dirige o código de 2 a 30 vezes. Um
  corte de um quadro a 60 Hz, num acionamento só, continua podendo passar.
- **O `orderFrontRegardless` numa janela já visível não tem estado que flipe.** Ele está
  contado como dirigido e não como mudança observável, de propósito.
- **Duas razões para rodar pelo `tools/cortecheck.sh` e nunca pelo binário direto.**
  1. *Intermitente:* rodando `./build/cortecheck` várias vezes seguidas, o controle do
     detector passou a medir 540,0 pt em vez de 100,0 e o harness abortou com código 1 —
     6 vezes seguidas numa sessão, e recuperou depois de uma pausa. **Não é
     determinístico:** a revisão desta medição rodou 10 corridas seguidas sem pausa e o
     controle saiu 100,0 pt em todas. O medido é isso; "a primeira foto sai antes do
     primeiro desenho" é a leitura compatível, não medida. Ao bater nela: deixe a máquina
     respirar e rode de novo pelo `.sh`. Ela não produz zero falso, produz aborto — o
     controle fazendo o trabalho dele.
  2. *Falso positivo silencioso, e este é o pior:* o binário **não recompila**. A revisão
     reverteu a injeção de sensibilidade no fonte, rodou `./build/cortecheck` e executou o
     binário **ainda injetado** — código 0 e "com moldura menor que o conteúdo: 8". Um
     resultado que parece medição e é o patch de revisão. O `.sh` recompila sempre.

## Determinismo

A família `real` rodou **3 vezes** pelo `tools/cortecheck.sh`, todas com código 0: a coluna
de veredicto (`corte=N`) saiu com o **mesmo MD5 nas três**
(`c0c4bef1223da3d33361af1a4a4640aa`) — e o mesmo hash saiu nas duas corridas diretas do
binário que completaram antes disso. O que varia é contagem de
quadros, cadência, o custo do `CGWindowListCopyWindowInfo` e quantos quadros vazios a corrida
calha de pegar — não o veredicto.

## O que isso responde, e o que devolve ao mapa

A pergunta da 004 era se os eventos produzem o corte quando dirigidos contra o código que o
usuário roda. **Não produzem.** 68 chamadas de `applyVisibility`, os três chamadores nas
cadências deles, o syscall que ela varre, a janela de verdade — 0,0 pt de lacuna de topo,
com as oito transições provando que enxergariam.

A essa altura o mapa varreu **estado da interface** (001, 35 combinações),
**ambiente simulado** (003.1, 8) e **o código real** (004, 8): 51 combinações, 0 corte. A
pergunta volta ao mapa, e agora sem a saída "foi medido contra o código errado".

O único material novo para a próxima rota é o custo: um syscall síncrono de até 21 ms na
main thread, disparado por *cada* mudança de Ajuste e por cada troca de Space, com a chave
ligada por padrão. Ele não pintou o corte neste harness — mas é o caminho mais barato de
tornar mais barato, e é onde um autodiagnóstico embarcado teria o que observar.

## Verificação

> **Antes de rodar qualquer coisa daqui:** todos os `grep` contra
> `Knobler/KnoblerApp.swift` deste bloco só devolvem alguma coisa entre o commit `f8684aa` e
> o merge deste branch — ver a nota de validade no `## Método`. No `master` eles saem vazios
> até o usuário commitar o trabalho local. Os comandos de `./tools/cortecheck.sh` seguem
> valendo: o harness dirige uma **réplica**, que mora no envelope e não no app.

```bash
# só a família nova, com todos os controles (~1 min de corrida + a compilação)
CORTECHECK_FAMILIA=real ./tools/cortecheck.sh

# Os valores EXATOS (refazem a conta): 8 combinações, 0 corte, lacuna_topo_max 0,0 pt
# nas oito, 68 chamadas de applyVisibility, 58 mudanças em AppSettings, 106 varreduras
# de fullscreenDisplays, 67+1 eventos de applyVisibility registrados (1+1 com mudança
# observável), controle do desvio atravessando o orderOut = 60,0 pt, controle da camada
# = 32,0 pt nos dois caminhos.
# Dependem da máquina: contagem de quadros, Hz, o custo do CGWindowListCopyWindowInfo
# (mediana ~0,3–0,8 ms, máx ~14–21 ms, total ~73–188 ms em oito corridas — ordem de
# grandeza, não valor a bater: depende de quantas janelas o sistema tem abertas), quantos
# quadros vazios a corrida produz, o contorno deles e quantas transições terminam vazias.
# Dependem do estado da máquina AGORA: quais displays estão em tela cheia (foi "nenhum").

# as linhas que fecham a conta
CORTECHECK_FAMILIA=real ./tools/cortecheck.sh \
  | grep -E 'controle|real-|dirigid|fullscreenDisplays|tela cheia AGORA|ocultarEmTelaCheia'
# → as 8 linhas real-*: corte= 0 e lacuna_topo_max=  0.0 pt
#   chamadas de applyVisibility dirigidas: 68 — mudanças em AppSettings: 58
#   fullscreenDisplays(): 106 varreduras na main thread — min/mediana/máx/total
#   ocultarEmTelaCheia no início da corrida: ligado

# a varredura inteira, 35 da 001 + 8 da 003.1 + 8 desta (~5 min)
./tools/cortecheck.sh | grep -E 'combinações rodadas|com moldura menor|corte= *[1-9]'
# → combinações rodadas: 51
#   com moldura menor que o conteúdo: 0
#   a única linha com corte>0 é a do controle do desvio atravessando o orderOut

# o registro chamada a chamada
CORTECHECK_VERBOSE=1 CORTECHECK_FAMILIA=real ./tools/cortecheck.sh | grep '·'
# → real-espaco-entra-telacheia · applyVisibility→orderOut: visivel=sim … → visivel=nao …
#   real-ajustes-parado · applyVisibility→orderFrontRegardless: … (sem estado que flipe)

# determinismo (o `grep -E '^  [a-z]'` pega só as linhas de transição; a linha do
# controle do desvio imprime "corte=N/N", e o N é contagem de quadros)
for i in 1 2 3; do CORTECHECK_FAMILIA=real ./tools/cortecheck.sh > /tmp/real$i.txt 2>&1; done
for i in 1 2 3; do grep -E '^  [a-z]' /tmp/real$i.txt | grep -o 'corte= *[0-9]*' | tr -d ' ' | md5 -q; done
# → hashes iguais. NÃO rode `./build/cortecheck` em sequência sem intervalo: o
#   controle sintético mede 540,0 pt em vez de 100,0 e o harness aborta (ver limites).

# A INJEÇÃO DE SENSIBILIDADE — de onde saem os 40,0 pt e o "8 de 8".
# Ela NÃO está no harness: é um patch de revisão — aplicar, rodar, reverter. Herda a
# receita da medição 003.1 e muda só o gate:
#   1. no envelope, `final class InjecaoDeSensibilidade: ObservableObject` com
#      `@Published var deslocado`, um `let injecao` global (NÃO @MainActor: um global
#      isolado no main actor não pode ser inicializado do contexto top-level), e um
#      `ViewModifier` que o observe com `.padding(.top, injecao.deslocado ? 40 : 0)`
#      vestindo a **NotchView dentro da raiz**, logo depois do `.padding(.top,
#      deslocamento)` — NÃO o `ZStack` inteiro: vestir a raiz empurra o fundo magenta
#      junto e a lacuna some;
#   2. um `func marcarDefeito()` com `guard transicaoCorrente.hasPrefix("real-")`
#      (sem o guard, os 40 pt somam aos 60 dos controles e o harness aborta antes de
#      imprimir qualquer transição) que faz `injecao.deslocado = true`; chamado no FIM
#      de `applyVisibilityReal` e no FIM (nos dois `return`) de `telasEmTelaCheia` —
#      ou seja, no ponto em que o código real é dirigido;
#   3. no começo do `rodar`, `injecao.deslocado = false`, senão a transição seguinte
#      herda o desvio.
# Assim sai a forma PERSISTENTE: as 8 acusam 40,0 pt (11/29 a 101/102 quadros).
# Para a forma TRANSIENTE de 150 ms, acrescente ao `marcarDefeito`:
#      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
#          MainActor.assumeIsolated { injecao.deslocado = false } }
# Assim as 8 também acusam 40,0 pt (1/24 a 24/171 quadros).

# a chave que decide se fullscreenDisplays() roda, na máquina do usuário
defaults read com.zoi.knobler ocultarEmTelaCheia
# → "does not exist" — e o padrão de AppSettings.swift:260 é `true`. A varredura roda.

# o código real que esta medição replica
grep -n 'applyVisibility\|fullscreenDisplays\|activeSpaceDidChange' Knobler/KnoblerApp.swift
# → 1040 fullscreenDisplays() · 1073 applyVisibility() · 371 activeSpaceDidChange
#   374 asyncAfter(+0.35) { applyVisibility() } · 377-378 AppSettings.objectWillChange
#   1269 applyVisibility() no fim do placeWindows
```
