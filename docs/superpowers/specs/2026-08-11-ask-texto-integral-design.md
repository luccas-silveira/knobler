# Card de pergunta: texto integral

Data: 2026-08-11
Área: `Knobler/Ask.swift` (`AskCardView`)

## Problema

O card do `POST /ask` trunca o que o usuário precisa ler para responder. Hoje a
pergunta usa `.lineLimit(2)` no header e cada descrição de opção usa
`.lineLimit(2)` na linha da opção. Perguntas longas — o caso real que motivou
isto foi uma fila de grill de 16 perguntas — chegam cortadas em `…`, e as
descrições que carregam o trade-off entre as opções chegam cortadas também. Não
dá para responder corretamente sem ver o texto.

O card já é agnóstico à ferramenta de origem: qualquer processo que faça
`POST /ask` no formato `AskUserQuestion` aparece nele, e o card não sabe quem
mandou (`source` é só um rótulo opcional no header). Esta mudança é puramente de
exibição e não toca no contrato da API.

## Comportamento

A **pergunta** aparece sempre por inteiro, sem `lineLimit`. Não depende de hover:
o cabeçalho não muda de altura enquanto o mouse percorre a lista.

A **descrição da opção sob o cursor** aparece por inteiro. As demais opções
continuam em 2 linhas. Ao sair da opção, ela volta a 2 linhas.

O card **cresce em altura** o quanto for preciso. Sem rolagem interna, sem teto.
Se existir algum clamp de altura em `NotchView`/`NotchWindow` que corte o card,
ele cede — a pesquisa da fase 2 confirma onde está.

O painel lateral de `preview` fica inalterado: quando alguma opção traz
`preview`, a lista continua com 250pt de largura e a expansão in-place acontece
dentro dela.

## Implementação

Duas mudanças em `Knobler/Ask.swift`:

- `header(question:)` — remover `.lineLimit(2)` do `Text(question.question)`.
- `optionRow(_:question:)` — o `.lineLimit` da descrição passa a ser `nil`
  quando `hovered == option.label`, e `2` caso contrário.

O estado `hovered` já existe e já é atualizado pelo `.onHover` da linha; nenhum
estado novo entra.

## Verificação

`tools/snapshot.sh` gera `ask-simple.png` e `ask-multiselect.png`. Eles cortam
antes do campo de texto (o `TextField` não renderiza offscreen), mas cobrem
header e lista de opções, que é exatamente o que muda aqui. O harness renderiza
sem cursor, então o estado de hover não sai no PNG por padrão — a validação do
texto expandido é inspeção visual no app rodando, com um `POST /ask` de
descrição longa.

Nenhum gate de `tools/check.sh` cobre layout de view; nenhuma entrada nova é
necessária.

## Fora de escopo

Rolagem interna no card. Truncamento por teto de altura. Qualquer mudança no
contrato de `POST /ask`. O painel de `preview`.
