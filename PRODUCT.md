# Product

## Register

product

## Users

Usuários de MacBook com notch (macOS 14.2+) — em boa parte devs e power-users
que querem a experiência da Dynamic Island do iPhone no Mac. O contexto de uso é
periférico: a pessoa está trabalhando, ouvindo música ou rodando um script, e o
notch é consultado de relance (glance) ou tocado por um gesto rápido. Ninguém
"abre o Knobler" para usá-lo — ele vive no canto da tela e responde a hover,
gestos e à API local. O trabalho a ser feito: acompanhar música tocando,
controlar volume/brilho/bateria sem o OSD nativo, ver notificações e countdown
de calendário, ditar texto, guardar capturas na shelf, e publicar status de
scripts/deploys no notch via `127.0.0.1:4477`.

## Product Purpose

Trazer a Dynamic Island para o notch do Mac de forma nativa (Swift/SwiftUI),
substituindo os HUDs do sistema e virando um canal ambiente de informação. O
diferencial é a API local: qualquer script pode publicar notificações e live
activities (anel de progresso) no notch. Sucesso é o notch parecer parte do
macOS — presente quando é útil, invisível quando não é — e nunca custar atenção
ou performance (medido em ~0% de CPU parado, ~22MB RAM).

## Brand Personality

Nativo, discreto, fluido. Fala a língua do macOS: SF Pro, materiais do sistema
(liquid glass / NSVisualEffectView), cantos e curvas que continuam o notch real.
Aparece quando precisa, some quando não. Todo movimento é suave, ease-out, sem
bounce nem elástico — motion a serviço da clareza, nunca decorativo. Tom:
confiante e silencioso. A melhor interação é a que o usuário mal percebe que
aconteceu.

## Anti-references

- **Widget/gadget genérico de terceiro:** nada de app colado na tela com cantos
  errados, sombras pesadas ou tipografia fora do sistema. Se não parecer que a
  Apple poderia ter feito, está errado.
- **Painel denso de dev-tool:** o notch é glanceável, não um dashboard. Sem
  paredes de números, gráficos ou configs expostas no estado aberto. Uma
  informação por vez, hierarquia clara.
- **Skeuomorfismo / neon / "gamer":** sem gradientes berrantes, glow neon,
  texturas 3D falsas. A cor vem do conteúdo (capa do álbum), não de decoração.
- **Notch que rouba atenção:** não pisca nem anima sem motivo, não fica aberto
  atoa. Interrompe o mínimo possível; música pausada se esconde, hover "espia"
  antes de comprometer a abertura.

## Design Principles

1. **Continuidade com o hardware.** O notch de software começa exatamente onde o
   notch físico termina — mesma largura, mesmo raio, mesma cor de fundo. A
   ilusão de que é uma peça só é o produto.
2. **Glanceável primeiro, acionável depois.** O estado fechado entrega
   informação sem toque. Expandir é opt-in (hover/gesto) e sempre reversível.
3. **A cor pertence ao conteúdo.** Tingir pela capa do álbum, pelo ícone do app
   que notificou — nunca por uma paleta de marca imposta sobre o conteúdo.
4. **Motion é gramática, não enfeite.** Cada animação comunica um estado
   (abrindo, espiando, escondendo). Ease-out exponencial, respeita
   `prefers-reduced-motion`. Se não diz nada, não anima.
5. **Custo zero de atenção e de máquina.** Parado, o Knobler não existe — nem na
   tela, nem no CPU. Cada estado aberto precisa justificar por que interrompeu.

## Accessibility & Inclusion

- **Reduced motion:** o app é fortemente animado (barras do visualizador,
  abrir/espiar/esconder, anéis de progresso). Toda animação precisa de uma
  alternativa quando `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`
  (ou o equivalente SwiftUI) estiver ativo — crossfade ou transição instantânea.
- **Contraste:** texto sobre o fundo do notch (preto no fechado, liquid glass no
  aberto) precisa manter ≥4.5:1. Cuidado especial ao tingir texto pela cor da
  capa — nunca deixar label de baixo contraste sobre glass.
- **Não depender só de cor:** estados (tocando/pausado, gravando, progresso)
  precisam de forma/ícone além da cor, para daltonismo.
- **Validação visual obrigatória:** `tools/snapshot.sh` renderiza todos os
  estados offscreen em `Snapshots/*.png`. Rodar e olhar antes de qualquer
  mudança de UI — é o gate de qualidade visual do projeto.
