# Ordem das seções quando a peça entra e sai

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: claude (sessão 2026-08-04)
- blocked-by: — (004 fechado; graduou desta névoa)

## Question

A cobaia escolhida em 004 (Pomodoro) **tem seção no notch**, então o piloto não
consegue desviar desta pergunta: `notchSectionOrder` é uma lista salva que a
pessoa arrumou na mão, e agora ela ganha um item que entra e sai.

Decidir:

- **Ao desinstalar**, a seção some da ordem salva ou fica guardada na lista sem
  ser exibida? (Guardar preserva a arrumação de quem reinstala; sumir mantém a
  preferência limpa e igual ao que a pessoa vê.)
- **Ao reinstalar**, a seção volta pro lugar de antes ou vai pro fim da lista?
- **Ao instalar pela primeira vez** um plugin que a pessoa nunca teve, onde ele
  entra numa ordem já personalizada?
- O que o editor de ordem (painel Notch) mostra: só as seções instaladas, ou as
  desinstaladas em cinza?

Restrição conhecida: `NotchSectionOrder.swift` e o `sectionordercheck` já
existem e 003 decidiu **não** encolher o enum `NotchSection` — ou seja, o enum
continua listando todas as seções e o filtro é por peça instalada.

## Resolução (2026-08-04)

**A ordem salva não é tocada — nunca.** Instalar e desinstalar não escrevem em
`notchSectionOrder` nem em `notchSectionsFixadas`.

Isso não é uma escolha de desenho, é o que o código já faz. Duas funções que já
existem entregam três das quatro perguntas do ticket de graça:

- `NotchSectionOrder.sanear(salva:)` (`Knobler/NotchSectionOrder.swift:126`)
  completa a lista salva com tudo do enum que faltar. Como 003 decidiu **não**
  encolher `NotchSection`, o `pomodoro` continua no enum quando a peça está
  desinstalada, então a linha nunca some da ordem salva.
- `NotchSectionOrder.ordenar(...)` (`:79`) só deixa passar seção com
  `hasContent == true` (ou fixada). Plugin que não nasce não reporta conteúdo.

Respostas, então:

- **Ao desinstalar** a seção **fica guardada** na ordem salva, só não é exibida.
- **Ao reinstalar** ela volta **exatamente pro lugar de antes** — sem código.
- **Ao instalar pela primeira vez**, cai onde `sanear` a coloca numa ordem já
  personalizada: no fim, junto com o resto que a lista salva não conhecia. Mesmo
  comportamento que uma seção nova de uma versão nova já tem hoje; nada especial
  pra plugin.

Duas decisões que exigem código, ambas de uma linha:

1. **O editor de ordem (Ajustes › Notch) esconde a seção de peça desinstalada.**
   Hoje o `ForEach` de `SettingsView.swift:248` lista as 10 sempre. Filtrar por
   instalado. Motivo: 002 já travou que "a opção some, sem avisar" quando a peça
   não está lá; linha cinza morta contradiz isso e não há o que arrastar num item
   que o notch não mostra. A vitrine de plugins é o painel do 006, não este
   editor.
2. **Fixada de peça desinstalada é ignorada, não apagada.** `fixadas` passa por
   cima de `hasContent`, então sem isto a faixa do Pomodoro apareceria vazia no
   notch depois de desinstalar. O filtro entra **dentro** do cálculo de
   `visiveis`, junto do `hasContent` — um lugar só, cobre os dois caminhos.
   Nada é escrito em `notchSectionsFixadas`: mesma regra do 007 ("desinstalar não
   apaga nada") e do 005 ("id órfão ignora calado"), e o código novo que rodaria
   na desinstalação é justo onde mora o bug de apagar demais.

Como `ordenar` é função pura e sem AppKit, o filtro entra como um parâmetro a
mais (o conjunto de seções instaladas), **não** como consulta ao registro lá
dentro — é o que mantém o `sectionordercheck` rodando sem subir o app. O gate do
piloto (004) ganha dois casos: seção de peça desinstalada não aparece nem quando
fixada, e a ordem salva sai da desinstalação byte a byte igual à que entrou.

Escopo confirmado como fora daqui: mexer no enum `NotchSection` (003 fechou) e o
que o `GET /status` devolve na lista de seções (é o 008).
