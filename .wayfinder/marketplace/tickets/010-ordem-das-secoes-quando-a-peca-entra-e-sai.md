# Ordem das seções quando a peça entra e sai

- map: ../map.md
- label: wayfinder:grilling
- status: open
- assignee: —
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
