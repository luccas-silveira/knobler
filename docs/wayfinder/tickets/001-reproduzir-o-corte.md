# 001 — Reproduzir o corte no harness

Map: [O knob cortado ao meio](../map-corte-do-knob.md)
Type: `measure`
Status: fechado (2026-08-21)
Assignee: sdd-001
Blocked by: —

## Pergunta

Dá para fazer o knob aparecer cortado ao meio fora do app, num harness, e em que
condição?

O que existe hoje: `tools/snapshot.sh` compila a `NotchView` isolada e renderiza estados
em `Snapshots/*.png`. Ele renderiza estados **parados**. O defeito é transitório — o
usuário vê um piscar —, então o harness precisa dirigir transições, não poses.

Condições a varrer, e o motivo de cada uma:

- Duas mudanças na mesma runloop: `mode` trocando junto com `focus` ou com uma seção que
  muda `currentSize`.
- Chegada assíncrona enquanto o card abre: notificação, HUD, Pomodoro ou screenshot
  disparando durante a animação de expansão.
- `setExpandedDirect` cancelando o `pendingWork` do hover no meio do caminho.
- Reduced Motion ligado e desligado — as animações são outras.

A medição tem que sair em número: quantas combinações rodadas, quantas produziram
moldura menor que o conteúdo. Sem número, é opinião. Escreva o comando em
`## Verificação` para a próxima sessão refazer a conta.

Se o corte não reproduzir em nenhuma combinação, **não force** — escreva o que foi
varrido e devolva a pergunta ao mapa. O plano B está em Ainda não especificado.

## Resolução

**Não reproduziu.** O harness `tools/cortecheck/main.swift` (rodado por
`tools/cortecheck.sh`) dirigiu **35 transições** em **11 famílias** — os identificadores da
Lista 3 da 002 nos dois sentidos, a troca de seção pelo caminho real da faixa
(`withAnimation`), duas mudanças na mesma runloop, chegada assíncrona de notificação/HUD/
Pomodoro/mensagem/link/screenshot no meio da expansão, e o `setExpandedDirect` cortando o
`pendingWork` do hover. **0 produziram lacuna no topo da moldura**
(`lacuna_topo_max = 0,0 pt` nas 35) — lacuna no topo é a forma que "só a metade de baixo"
teria na imagem. Como métrica secundária, 0 produziram moldura menor que o conteúdo, com o
pior excedente da varredura em 0,0 pt; esse segundo zero mede menos do que o nome sugere,
porque `shape.fill` e o conteúdo dividem o mesmo `ZStack` sob a mesma máscara
(`NotchView.swift:181` e `:249`) e encolhem juntos.

O zero tem três travas medidas por trás, para não ser um zero de detector cego: o controle
positivo (quatro trocas de `mode` produzem 5 a 11 alturas de moldura distintas contra uma
trava de 3 — a 3ª altura é a que prova interpolação; a contagem oscila com a cadência, por
isso a trava não depende dela), o controle do detector
(moldura sintética de 100 pt com conteúdo de 200 pt acusa excedente de 100,0 pt) e o
controle do desvio na view real (a `NotchView` de verdade empurrada 60 pt pra baixo acusa
lacuna de topo de 60,0 pt em todos os quadros). Sem qualquer um dos três o harness aborta
com código 1. Veredicto idêntico em 9 corridas (mesmo hash MD5).

Dois achados de passagem, ambos em número:

1. **A moldura salta sem interpolar quando `focar` roda em transação vazia** — 504 → 126 pt
   entre duas fotos consecutivas, 2 alturas na série inteira. Confirma empiricamente a
   leitura de código da 002. **Mas o caminho de verdade não é esse**: clicar na faixa
   (`NotchView.swift:986`) e o swipe (`KnoblerApp.swift:1006`) embrulham o `focar` num
   `withAnimation(.easeOut(duration: 0.22))` — as duas únicas ocorrências de
   `withAnimation` no projeto — e aí a moldura interpola (4 alturas: 504, 486, 153, 126).
   A divergência de transação que a 002 previu existe no código, mas não produziu corte em
   nenhuma foto.
2. **Alguns quadros por corrida, em 35 combinações, saíram sem moldura NEM conteúdo** (6 a
   15 nas corridas medidas; sem teto declarado, porque depende de quantas fotos calham de
   cair em cima de uma troca de `mode`) (magenta puro), todos
   em cima de uma troca de `mode`, enquanto o controle do fechado parado mede 32 pt em
   todas as suas fotos. Não é o sintoma relatado (some tudo, não a metade de cima) e não dá
   para decidir pela imagem se é buffer não desenhado ou quadro real vazio — fica como
   pista para a 003.

Limite que o zero não cobre: as fotos saem a ~17 Hz, então um corte de **um** quadro a
60 Hz cabe entre duas. Não varridos, com o motivo: Reduced Motion (key path somente-leitura
no SDK), `.mensagens`/`.historico`/`.nota` (dar conteúdo grava no Application Support real
do usuário; cobertas por proxy pelo `.link`, 438 pt, a maior seção do app) e
`agentRequestExpanded` (`@State` privado — único item da Lista 3 fora da varredura;
`vm.incoming?.mediaHeight` entrou, 200 → 0 pt).

O harness **não** entrou em `tools/check.sh`: determinismo foi medido (9/9), o impedimento
é ambiente — precisa de WindowServer (a CI ficaria vermelha, não pulada) e leva ~4,5 min
contra segundos dos gates atuais. A forma do gate é decisão da 005.

Números, séries por quadro e comandos de recontagem em
[medicao-001-repro.md](../medicao-001-repro.md). A pergunta volta ao mapa: o plano B de
"Ainda não especificado" é agora a rota viva.
