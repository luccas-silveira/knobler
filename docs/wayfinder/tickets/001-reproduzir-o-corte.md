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
`tools/cortecheck.sh`) dirigiu **34 transições** em **11 famílias** — os identificadores da
Lista 3 da 002 nos dois sentidos, a troca de seção pelo caminho real da faixa
(`withAnimation`), duas mudanças na mesma runloop, chegada assíncrona de notificação/HUD/
Pomodoro/mensagem/link/screenshot no meio da expansão, e o `setExpandedDirect` cortando o
`pendingWork` do hover. **0 produziram moldura menor que o conteúdo.** Nenhum quadro teve
lacuna no topo, que é a forma que "só a metade de baixo" teria na imagem. O pior excedente
em toda a varredura foi 0,0 pt: o conteúdo encosta na borda de baixo da moldura e nunca
passa dela.

O "0 de 34" tem duas travas medidas por trás, para não ser um zero de detector cego: o
controle positivo (a troca de `mode` produz 8 alturas de moldura distintas, provando que a
animação corre na janela fora da tela) e o controle do detector (uma moldura sintética de
100 pt com conteúdo de 200 pt acusa excedente de 100,0 pt). Sem qualquer um dos dois o
harness aborta com código 1. Veredicto idêntico em 3 corridas (mesmo hash MD5).

Dois achados de passagem, ambos em número:

1. **A moldura salta sem interpolar quando `focar` roda em transação vazia** — 504 → 126 pt
   entre duas fotos consecutivas, 2 alturas na série inteira. Confirma empiricamente a
   leitura de código da 002. **Mas o caminho de verdade não é esse**: clicar na faixa
   (`NotchView.swift:986`) e o swipe (`KnoblerApp.swift:1006`) embrulham o `focar` num
   `withAnimation(.easeOut(duration: 0.22))` — as duas únicas ocorrências de
   `withAnimation` no projeto — e aí a moldura interpola (4 alturas: 504, 486, 153, 126).
   A divergência de transação que a 002 previu existe no código, mas não produziu corte em
   nenhuma foto.
2. **10 quadros de 34 combinações saíram sem moldura NEM conteúdo** (magenta puro), todos
   em cima de uma troca de `mode`, enquanto o controle do fechado parado mede 32 pt em
   todas as suas fotos. Não é o sintoma relatado (some tudo, não a metade de cima) e não dá
   para decidir pela imagem se é buffer não desenhado ou quadro real vazio — fica como
   pista para a 003.

Limite que o zero não cobre: as fotos saem a ~17 Hz, então um corte de **um** quadro a
60 Hz cabe entre duas. Não varridos, com o motivo: Reduced Motion (key path somente-leitura
no SDK), `.mensagens`/`.historico`/`.nota` (dar conteúdo grava no Application Support real
do usuário; cobertas por proxy pelo `.link`, 438 pt, a maior seção do app) e
`agentRequestExpanded` (`@State` privado).

O harness **não** entrou em `tools/check.sh`: determinismo foi medido (3/3), o impedimento
é ambiente — precisa de WindowServer (a CI ficaria vermelha, não pulada) e leva ~4,5 min
contra segundos dos gates atuais. A forma do gate é decisão da 004.

Números, séries por quadro e comandos de recontagem em
[medicao-001-repro.md](../medicao-001-repro.md). A pergunta volta ao mapa: o plano B de
"Ainda não especificado" é agora a rota viva.
