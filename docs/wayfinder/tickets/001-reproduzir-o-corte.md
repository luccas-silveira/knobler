# 001 — Reproduzir o corte no harness

Map: [O knob cortado ao meio](../map-corte-do-knob.md)
Type: `measure`
Status: aberto
Assignee: —
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
