# Pesquisa — redesenho do card de pergunta do Claude

Spec: `docs/vesta/specs/2026-11-18-card-pergunta-redesenho-design.md`

Frentes: duas internas (teclado/foco e blast radius; reuso visual e testes) e uma
externa (teclado em painel que não ativa o app, rolagem, prior art). O inspo ficou
de fora: o arquivo dele é de sites, e o card herda a linguagem do próprio notch.

## Achados

### A1 — O atalho do notch, apertado com pergunta na tela, não dá teclado ao card e arma o card de música por trás
- Fonte: `Knobler/NotchViewModel.swift:644-648`, `Knobler/KnoblerApp.swift:1271-1276`, `Knobler/NotchPresentation.swift:53-63`
- Contradiz a spec: sim — a spec diz que "falta o painel virar chave". Falta mais: nada na apresentação muda em `.question`, então o `makeKey` nunca roda, e `expanded` fica ligado invisível até a pergunta sair, quando o card de música abre sozinho e pega o teclado.
- Pergunta que levanta: nenhuma para o usuário. O atalho precisa de um ramo próprio para pergunta, que não passe por `setExpandedDirect`.

### A2 — Um vigia de teclas já existente engole ← → Tab e Esc quando o notch foi aberto pelo atalho
- Fonte: `Knobler/KnoblerApp.swift:1001-1014`
- Contradiz a spec: sim — essas quatro teclas nunca chegariam ao card se ele reaproveitasse o estado "aberto pelo teclado".
- Pergunta que levanta: nenhuma para o usuário. O teclado do card precisa de um dono próprio, separado do `abertoPorTeclado`.

### A3 — Tirar o mouse de cima do card desfaz o "aberto pelo teclado" em ~0,3 s
- Fonte: `Knobler/NotchView.swift:290`, `Knobler/NotchPresentation.swift:94-104`, `Knobler/NotchViewModel.swift:670-671`
- Contradiz a spec: parcial — reforça A2: a posse do teclado não pode morar em `abertoPorTeclado`.
- Pergunta que levanta: nenhuma.

### A4 — Pergunta que chega com o notch já aberto pelo atalho herda o teclado na hora
- Fonte: `Knobler/KnoblerApp.swift:1275` (o `makeKey` dispara na troca `.music` → `.question`)
- Contradiz a spec: sim — a spec promete que a pergunta nunca rouba o teclado, e com os atalhos numéricos um dígito digitado na nota responderia a pergunta.
- Pergunta que levanta: se você está digitando na nota ou numa conversa do notch e o Claude pergunta, o card deve cobrir o que você digitava e ficar sem teclado até você apertar o atalho, ou esperar você terminar de digitar para aparecer?

### A5 — As teclas chegam com mais segurança pelo vigia de teclas do app do que pelo mecanismo de foco do SwiftUI
- Fonte: `Knobler/KnoblerApp.swift:1001` (padrão do repo); https://developer.apple.com/forums/thread/825509 (⇧⇥ não chega ao `.onKeyPress`); https://developer.apple.com/documentation/swiftui/view/defaultfocus(_:_:priority:) (foco inicial só na primeira aparição da janela); https://github.com/jordanbaird/Ice/blob/main/Ice/UI/ViewModifiers/OnKeyDown.swift (Ice usa monitor local)
- Contradiz a spec: sim — a spec manda `.onKeyPress` num contêiner focável. Isso perde o ⇧⇥, depende de um foco inicial que não é reavaliado num painel já existente, e desenha anel de foco.
- Pergunta que levanta: nenhuma para o usuário. O vigia traduz tecla em ação do reducer quando o painel é chave, há pergunta ativa e o cursor não está num campo de texto.

### A6 — Números precisam ser lidos pelo caractere, não pela posição da tecla
- Fonte: https://github.com/p0deje/Maccy/blob/master/Maccy/Views/KeyHandlingView.swift
- Contradiz a spec: não
- Registro: em teclado AZERTY a fileira de números exige Shift; ler o caractere do evento e aceitar o teclado numérico. Repetição de tecla ignorada para números e Enter, aceita para setas.

### A7 — Soltar o teclado com o card na tela já funciona no app
- Fonte: `Knobler/KnoblerApp.swift:1178, 1273`, `docs/handoffs/2026-07.md:469, 2279-2280`; contraponto em https://developer.apple.com/documentation/appkit/nswindow/resignkey()
- Contradiz a spec: não
- Registro: como o painel nunca ativa o app, o app da frente continua ativo e recebe as teclas de volta. A Apple desaconselha chamar esse método direto, mas o caminho é o que o app já usa e foi validado ao vivo. Ninguém precisa guardar "o app anterior".

### A8 — Esc como "soltar" contraria a convenção do sistema e do próprio Claude Code
- Fonte: https://developer.apple.com/design/human-interface-guidelines/keyboards (Esc e ⌘. cancelam); strings do diálogo do Claude Code ("Esc to cancel"); `docs/superpowers/specs/2026-07-17-perguntas-notch-design.md:18, 50`; `Knobler/LinkPreviewView.swift:39`
- Contradiz a spec: parcial — a troca foi apontada e aprovada pelo usuário em 18/11/2026 junto com a spec. Fica registrada; os textos antigos que prometem "Esc cancela" entram na lista de documentação a atualizar.
- Pergunta que levanta: nenhuma (decidida).

### A9 — "Rodada completa" precisa ser contada por pergunta, não pelo número de respostas guardadas
- Fonte: `Knobler/AskFeature.swift:99`, `Knobler/AskModels.swift:17-36`
- Contradiz a spec: parcial — as respostas são guardadas pelo texto da pergunta (é o contrato com o hook). Duas perguntas com o mesmo texto dividem uma resposta; contar respostas nunca fecharia a rodada.
- Pergunta que levanta: nenhuma. Regra: a rodada resolve quando o texto de toda pergunta tem resposta.

### A10 — O destaque no estado compartilhado aparece igual em todos os monitores
- Fonte: `docs/architecture.md:174`, `Knobler/Ask.swift:20`
- Contradiz a spec: não
- Registro: passar o mouse numa tela move o destaque nas outras. Aceitável; página, seleção e texto já são compartilhados.

### A11 — O card de pergunta e o de aprovação do Codex dividem o mesmo modo
- Fonte: `Knobler/KnoblerApp.swift:1256-1258`, `Knobler/NotchView.swift:82-83`
- Contradiz a spec: parcial — o ramo do atalho tem de testar a pergunta do Claude especificamente, senão o card do Codex (fora de escopo) ganha teclado sem ter teclas.
- Pergunta que levanta: nenhuma.

### A12 — O teto de 60% com rolagem desfaz uma decisão anterior e uma frase publicada
- Fonte: `docs/superpowers/specs/2026-08-11-ask-texto-integral-design.md:28, 103, 119-124`; `Knobler/Novidades/0.26.0.html:14-20`; `Knobler/NotchPresentation.swift:193-197`
- Contradiz a spec: parcial — a spec de agosto decidiu "sem rolagem, sem teto, descrição inteira só sob o cursor"; a novidade 0.26.0 diz que o card cresce até o Dock. O usuário aprovou o teto e as descrições sempre inteiras em 18/11/2026. A "altura útil" hoje inclui a barra de menus e vai até o Dock.
- Pergunta que levanta: nenhuma (decidida). O teto é 60% da distância do topo da tela ao Dock.

### A13 — Lista que rola dentro de um card que mede a própria altura trava a medida
- Fonte: `Knobler/Ask.swift:172-174, 221-226`; https://fatbobman.com/en/snippet/disabling-scroll-in-swiftui-scrollview-when-content-is-smaller-than-container/
- Contradiz a spec: parcial — a medida atual só cresce (`max`) e uma área rolável ocupa o espaço que recebe. O padrão que resolve é oferecer duas variantes (conteúdo puro; conteúdo dentro da rolagem) e deixar o sistema escolher a primeira que cabe. Não há precedente no repo.
- Pergunta que levanta: nenhuma.

### A14 — O harness de snapshot já sabe desenhar rolagem e campo de texto
- Fonte: `tools/main.swift:1523-1570`, `Snapshots/lembretes-criar.png`, `.claude/skills/snapshot-ui/SKILL.md:41-60`
- Contradiz a spec: não — resolve o ponto de pesquisa. Cenários de alguns prefixos rodam numa janela real em vez do renderizador offscreen, e ali rolagem, campo de texto e teclas sintéticas funcionam. Incluir `ask-` nessa lista tira o preview vazio e o "proibido" amarelo dos snapshots de hoje. A skill `snapshot-ui` precisa da atualização correspondente.

### A15 — Trocar de aba hoje dispara a animação de troca de card inteiro, em dois tempos
- Fonte: `Knobler/NotchView.swift:81, 343-345, 616`, `Knobler/NotchShell.swift:9-28`
- Contradiz a spec: parcial — a página faz parte da identidade do conteúdo, então cada troca de aba anima o card todo e a altura nova chega um passo depois, com conteúdo cortado embaixo no meio do caminho. O `AberturaDoCard` citado na spec de agosto não existe mais (removido em `f6dbff6`). Nenhum gate cobre transição de altura do card de pergunta.
- Pergunta que levanta: nenhuma. A troca de aba sai da identidade do conteúdo e anima só dentro do card.

### A16 — O notch não tem arquivo de estilo nem cor de destaque
- Fonte: `Knobler/NotchShell.swift:32-41`, `Knobler/WhatsApp/WhatsAppListaView.swift:115-125, 183-184, 232-242`, `Knobler/WhatsApp/WhatsAppEstadosView.swift:228-236`
- Contradiz a spec: parcial — "sai do que o notch já usa" significa branco em opacidades (fundo de linha 0,06/0,08, destaque 0,15, marcada 0,25), raio 8 e selo em cápsula. Os componentes mais bem-acabados são privados do WhatsApp. O notch é monocromático: o selo "Recomendado" e o ✓ não têm cor para herdar.
- Pergunta que levanta: fica para o mockup — o card segue todo em branco sobre preto ou ganha uma cor de destaque só dele.

### A17 — A legenda não pode ter o atalho escrito fixo
- Fonte: `Knobler/SettingsView.swift:16-18, 347`, `Vendor/MonitorControl/KeyboardShortcuts.swift:186-194, 791-795, 899-901`
- Contradiz a spec: parcial — o atalho é ⌃⌥K por padrão, configurável e apagável nos Ajustes. A legenda lê o valor atual; sem atalho definido, não mostra dica.
- Pergunta que levanta: nenhuma.

### A18 — Deslizar de lado sobre o card de pergunta pode trocar de música
- Fonte: `Knobler/KnoblerApp.swift:1037, 1083-1106`
- Contradiz a spec: não
- Registro: com pergunta ativa o tratamento de rolagem considera o card fechado. A rolagem vertical chega ao conteúdo; a horizontal vira gesto de faixa. Conferir ao vivo quando a lista rolar — rolagem só se testa com evento real na fila do sistema.

### A19 — Documentação que fica velha sem nenhum gate avisar
- Fonte: `docs/ask.md:3-24`, `docs/images/ask-simple.png`, `docs/images/ask-multiselect.png`, `Knobler/Ask.swift:15`, `Knobler/LinkPreviewView.swift:39`, `VERSIONING.md:44-48`, `tools/notchview-fontes.txt:28-31`
- Contradiz a spec: parcial — a spec só cita CHANGELOG e novidades. Faltam `docs/ask.md` e suas duas imagens, os comentários que dizem "1/N" e "Esc fecha como no card de pergunta", e a lista manual de fontes da `NotchView` se o card for dividido em arquivos. A próxima MINOR é a 0.38.0.
- Pergunta que levanta: nenhuma.

### A20 — O diálogo do Claude Code no terminal tem tela de revisão; apps de referência mostram o atalho ao lado de cada ação
- Fonte: https://code.claude.com/docs/en/agent-sdk/user-input; https://manual.raycast.com/action-panel; https://developer.apple.com/design/human-interface-guidelines/focus-and-selection
- Contradiz a spec: não
- Registro: o usuário escolheu envio direto, sem revisão. O selo numérico por opção e a legenda no rodapé seguem a convenção do Raycast. A HIG pede destaque de linha na lista e anel de foco só no campo de texto, e Tab entre grupos com setas dentro do grupo — é o que a tabela de teclas da spec faz.

### A21 — Bloqueio de teclado vence a pergunta
- Fonte: `Knobler/NotchPresentation.swift:36-38`, `Knobler/NotchAPIServer.swift:499`
- Contradiz a spec: não
- Registro: borda que a spec não cita. Com o teclado bloqueado o card some e o painel larga a chave pelo caminho que já existe.

## Fila do grill

Ordenada por dependência — decisão que trava outras vem primeiro.

1. A1 + A2 + A3 + A11 — dono próprio para o teclado do card, fora do `abertoPorTeclado` (trava A4, A5)
2. A5 — teclas pelo vigia do app, não por foco do SwiftUI
3. A4 — pergunta que chega enquanto o usuário digita no notch
4. A9 — regra de rodada completa
5. A13 + A15 — rolagem acima do teto e animação da troca de aba
6. A16 — monocromático ou cor de destaque (decide no mockup)
7. A17 — legenda lê o atalho atual
8. A19 — documentação a atualizar
9. A8, A12 — já decididos pelo usuário; só o registro
