# Diagnóstico do deslocamento visual do knob

Estado em 09/09/2026: **causa ainda não confirmada; nenhuma correção aplicada**.
Continuação do [VIS-01 da revisão](revisao-2026-09-08.md).

Atualização de 10/09: o bug lógico de fechar durante edição foi corrigido em
`setExpandedDirect`, com regressão em `tools/eventoscheck.swift` e snapshot da
nota recolhida por gesto. A investigação abaixo permanece como histórico:
**o vínculo com o deslocamento visual continua sem comprovação**.

## Reescrita da apresentação (10/09)

A implementação atual substitui o controle de abertura e a composição da
moldura, mantendo os efeitos visuais. O host agora acomoda o card de links e
mede seus próprios limites; o detector SwiftUI tornou-se passivo, sem troca
de identidade para tentar recuperar o desenho. A arquitetura está descrita em
[architecture.md](architecture.md).

O harness reproduzível `tools/presentation-windowcheck.sh` exercita 18 cenários
com intervalos de 50, 120 e 240 ms, layouts de notch e monitor externo,
interrupções de abertura, troca de seção e entrada/saída do ditado. Confere
identidade do host, geometria, texto e foco real do editor, ocultação/reexibição
e reposicionamento para outra tela quando disponível. Captura também durante
a sequência; a API de captura é assíncrona, portanto o PNG não garante um
instante exato da interpolação. As medidas finais comparam pixels e layout.
Também mede conteúdo de 736 pt dentro da moldura larga, com e sem Reduzir
Movimento. O harness inicia `NSApplication.run()` e simula a retomada do
teclado com `makeKey`; não injeta eventos de clique no app instalado.

O renderizador estático de `tools/snapshot.sh` não desenha todos os controles
AppKit: placeholders amarelos em campos de texto ou miniaturas não validam
esses controles. Para a nota, conferir os PNGs do compositor produzidos pelo
teste de janela real.

Validação concluída em 11/09: build Debug com `-derivedDataPath build/DerivedData
-disableAutomaticPackageResolution`, 39 checks canônicos e `Knobler --selfcheck`
aprovados; 62 snapshots regenerados e inspecionados. Os 18 cenários nativos
terminaram com `PlatformTextView` como primeiro respondente, janela-chave e
zero desvio entre topo/altura esperados e pixels medidos. As duas verificações
de largura também passaram. Capturas finais e exemplares intermediários foram
inspecionados; os artefatos ficam em pasta temporária e podem expirar.

Esses checks são regressões da nova apresentação. **Não comprovam a causa nem
a eliminação do defeito visual intermitente original.** As seções abaixo
registram o código e os experimentos anteriores à reescrita.

## Evidência da captura enviada

A imagem é compatível com a seção de nota deslocada para cima, não apenas com
texto ausente. Isso é uma inferência por comparação dos pixels, pois não existe
um `/status` capturado no mesmo instante da imagem original.

| Referência vertical | Imagem enviada | Nota sintética normal, escala normalizada |
|---|---:|---:|
| Fim do fundo do editor | 46 px | 168 pt |
| Fim da moldura preta | 118 px | 240 pt |
| Distância entre os dois | 72 px | 72 pt |

Assumindo a mesma escala e o mesmo inset superior do teste, ambos os elementos
estão deslocados 122 pontos para cima. Em monitor externo, o inset superior é
diferente: não se pode afirmar o deslocamento absoluto sem identificar a tela
da ocorrência. O espaçamento preservado é a evidência mais forte.

O [detector anterior](../Knobler/CorteDoKnob.swift) mede a moldura em relação ao
espaço nomeado da própria raiz SwiftUI. Se raiz e moldura se deslocarem juntas,
essa medida pode continuar em zero. A ausência de `corte-do-knob.jsonl` não
descarta esse mecanismo. **Isso identifica um ponto cego do detector, não a
causa do deslocamento.**

## Experimentos realizados

O harness temporário usa os fontes reais de `NotchView` e `NotchWindow`, dados
sintéticos e instâncias isoladas dos serviços. Não substituiu o app instalado.

- Transições rápidas entre nota, histórico, prateleira e música, intercaladas
  com recolher e expandir. A primeira variante tinha 24 ações programadas por
  cenário; as seguintes tinham 96. Ações podem ocorrer no mesmo giro do
  runloop: esses números não equivalem a quadros distintos renderizados.
- `onDrop` ligado, ao contrário do harness histórico de corte.
- Janela visível e captura pelo `SCScreenshotManager`, além do redesenho via
  `cacheDisplay`. As capturas finais do compositor ocorreram após as transições;
  não são uma gravação de todos os quadros intermediários.
- Remoção do fundo magenta e do contêiner adicional do harness; raiz transparente
  em janela de 700 × 1117 pontos, ancorada ao topo da tela.
- Ocultar e reexibir a janela durante as mudanças de estado.
- Callback de elegibilidade de teclado, janela-chave e editor como primeiro
  respondente. Na variante final, a nota terminou com `isKeyWindow == true` e
  `SwiftUI.PlatformTextView` como primeiro respondente.
- Remoção do `AnyView` adicional do harness, usando `NSHostingView` genérica.

Nenhuma dessas execuções reproduziu o deslocamento persistente. Na variante
final, janela, frame do host e bounds do host permaneceram na posição esperada;
os quatro estados finais foram capturados pelo compositor. A sonda de
`scrollToVisible` no host não registrou chamadas. Isso não exclui rolagem interna
de descendentes nem um gatilho que não tenha sido exercitado.

Uma execução inicial terminou o cenário chamado `stress-shelf` com foco na nota,
por causa da reconciliação de foco: ela não constitui evidência de prateleira
estável. As variantes finais registraram os quatro focos pretendidos.

Os artefatos sintéticos de trabalho ficaram em `/tmp/knobler-visual-diagnose/`
(fontes, logs e PNGs) e podem expirar. Não são gates de CI. O teste anterior
`tools/cortecheck.sh` e seus resultados históricos não foram reclassificados
como prova de ausência deste defeito.

## Investigação por código: interrupção de animações (09/09)

### Confirmado: fechar por gesto não encerra a edição

`NotchViewModel.setExpandedDirect(false)` (linha 390) cancela o trabalho de
hover e zera `expanded`, mas mantém `QuickNote.shared.editing`. Já `mode`
(linha 312) dá prioridade à nota em edição, antes de consultar `expanded`.
O resultado reproduzido com os tipos reais, sem precisar de uma view, foi:

```text
LOGIC direct-close expanded=false mode=music editing=true
LOGIC hover-close mode=closed
```

Sequência mínima executada no harness:

```swift
let vm = NotchViewModel()
vm.displayID = 1
QuickNote.shared.adotar(1)
QuickNote.shared.editing = true
vm.expanded = true
vm.setExpandedDirect(false)
assert(!vm.expanded && vm.mode == .music && QuickNote.shared.editing)
vm.fecharPorHoverOut()
assert(vm.mode == .closed && !QuickNote.shared.editing)
```

O harness isola o clipboard com `NSPasteboard(name:)`. Essas asserções provam
o defeito existente, não a correção. `fecharPorHoverOut` já libera `editing`
explicitamente pelo mesmo motivo e tem cobertura em `tools/eventoscheck.swift`;
o caminho direto não tem o teste equivalente.

No app, o gesto vertical chama o caminho direto em `KnoblerApp.swift:1008`.
O fim do peek de captura também o chama, na linha 1097. Assim, a intenção de
fechar pode divergir do modo desenhado. A elegibilidade de teclado usa
`expanded`; sua queda pode provocar `resignKey`, e só uma mudança posterior de
foco pode liberar a edição e finalmente trocar o modo. O problema está na
coordenação dos estados, antes de qualquer interpolação de pixels.

Há outra diferença no mesmo caminho: ele não registra `lastCollapseAt`, que
o hover consulta para evitar reabertura durante o encolhimento. Isso permite
que um hover de entrada agende a abertura em 180 ms, dentro da animação de
fechamento de resposta 300 ms. A possibilidade está no código; não foi
demonstrado que esse evento de hover ocorre na captura enviada.

**Não foi provado que esse bug de fechamento produz o deslocamento visual.**
No teste com janela ele também apareceu durante uma reabertura, mas o desenho
final se recuperou. A correção mínima a avaliar é fazer o fechamento direto
liberar a edição da tela dona e registrar o recolhimento, mantendo a guarda
de link aberto exclusiva do fechamento por hover. Não foi aplicada nesta
investigação.

### Hipóteses de animação verificadas

1. **Fechamento/reabertura interrompidos:** fechar pelo hover, reabrir, fechar
   pelo caminho direto e reabrir na nota.
2. **Troca de seção durante redimensionamento:** nota → histórico → nota →
   prateleira → nota. O chamador usa `withAnimation(.easeOut(duration: 0.22))`,
   como os botões reais; o conteúdo tem sua própria animação de 300 ms.
3. **Remoção/reinserção do editor:** nota → ditado → nota → ditado → nota,
   exercitando `onAppear`, `onDisappear` e o foco do editor durante transições.

Cada sequência foi programada com intervalos de 50, 120 e 240 ms, nas duas
configurações de layout: notch real e ilha externa. Foram **18 cenários e 72
ações executadas**, com `NotchWindow`, `onDrop` e teclado ligados. A janela
temporária ficou visível; não substituiu a instalação do usuário.

Desta vez não houve `cacheDisplay` entre as ações: o custo da captura na CPU
agrupava ações nos experimentos anteriores. Os horários reais foram
registrados. A maior demora além do prazo programado foi 148 ms na configuração
de notch real e 18 ms na externa; os intervalos programados não são uma
garantia de cadência exata.

As 18 capturas finais do compositor concluíram. Não apareceu deslocamento
persistente nas verificações realizadas. As nove imagens finais externas
foram medidas: editor de 12 a 140 pt e moldura terminando em 212 pt, iguais
ao layout esperado. Exemplares das duas configurações foram inspecionados
visualmente. As imagens externas sobrescreveram os PNGs dos cenários reais;
os logs das duas execuções ficaram separados.

Artefatos temporários: `probe-interrupt`, `main.swift`, `interrupt.log` e
`interrupt-external.log`, em `/tmp/knobler-visual-diagnose/`. Continuam sendo
experimentos, não gates de CI nem prova de ausência de todos os bugs visuais.

O código também aplica máscara e composição antes do frame externo, enquanto
conteúdo removido participa de transições. Isso merece inspeção se houver
divergência entre layout e apresentação, mas a ordem dos modificadores e a
existência de animações de durações diferentes, sozinhas, não demonstram uma
falha. Não há base para declarar que uma mola ficou travada ou remover as
transições como correção confirmada.

## Coletar uma ocorrência ativa

Antes de recolher, reabrir ou reiniciar o knob, executar na raiz do projeto:

```bash
bash tools/diagnostico-visual.sh
```

O [coletor](../tools/diagnostico-visual.swift) não reinicia o app, não troca seu
foco e não instala uma build de diagnóstico. Ele grava uma pasta temporária e
imprime o caminho. Precisa do Xcode/Swift, da API local em `127.0.0.1:4477` e de
permissão de gravação de tela para capturar; a disponibilidade de Acessibilidade
é registrada no JSON.

A pasta contém:

- `geometry.json`: horário, PID, telas, escala, inset superior, estados dos
  knobs, frames das janelas e geometria disponível via Acessibilidade. O JSON
  não copia textos de notas, títulos de notificações ou payloads da API.
- `window-*.png`: imagens das janelas visíveis do processo Knobler. Podem conter
  notas e mensagens que estavam visíveis: são capturas pessoais e não devem ser
  commitadas. Janelas ocultas ficam de fora das imagens.

A coleta é sequencial, não atômica: os horários de captura estão no JSON. Não
força redesenho nem chama `cacheDisplay` dentro do processo instalado.

Foi validada em 09/09/2026 com o app instalado: duas janelas capturadas, três
estados de knobs e três telas registrados, JSON e PNGs conferidos. Nessa
validação todos os knobs estavam recolhidos, portanto não é uma reprodução.

## Próxima decisão baseada em evidência

Com o defeito presente, comparar o topo da tela com o frame da janela, a
geometria acessível dos controles e a posição deles no PNG. O `/status` usa
coordenadas AppKit; ScreenCaptureKit/Acessibilidade usam coordenadas de tela com
origem superior. Converter usando as telas registradas antes de comparar.

- Janela deslocada: rastrear o reposicionamento e as mudanças de display.
- Janela correta, geometria dos controles deslocada: rastrear layout/foco no
  host e nos ancestrais dos controles.
- Janela e geometria corretas, pixels deslocados: investigar a composição e as
  transições de camadas. A árvore de Acessibilidade pode ser incompleta; ausência
  de um controle nela não prova ausência no layout.

Ainda falta uma ocorrência ativa para escolher entre esses caminhos. Não há
evidência suficiente para remover animações, reconstruir periodicamente o knob
ou apontar o compositor como causa confirmada.
