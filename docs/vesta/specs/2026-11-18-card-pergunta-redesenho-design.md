# Card de pergunta do Claude: redesenho

Data: 2026-11-18
Área: `Knobler/Ask.swift` (`AskCardView`), `Knobler/AskFeature.swift` (reducer),
encaixe em `Knobler/NotchView.swift` e o atalho global em `Knobler/KnoblerApp.swift`.

## Problema

O card que mostra o `AskUserQuestion` do Claude Code no notch funciona, mas tem
quatro dores, todas confirmadas pelo usuário:

1. **Só responde com mouse.** O painel só vira janela-chave depois de um clique
   no campo de texto; não há número, seta nem Enter para escolher opção.
2. **Várias perguntas são um corredor de mão única.** Com 2–4 perguntas o card
   mostra `1/3`, não deixa voltar, não mostra o que já foi respondido.
3. **Visual sem acabamento.** Linhas cinzas iguais; chip, pergunta, origem,
   contador e ✕ disputam uma linha só; nada indica opção recomendada, opção
   marcada ou foco.
4. **Texto longo fica apertado.** A descrição só abre inteira sob o cursor (o
   card pula de altura enquanto o mouse anda) e o preview usa letra de 9 pt numa
   coluna estreita.

## Resultado esperado

Responder uma rodada de 3 perguntas do começo ao fim só no teclado, e voltar a
uma pergunta já respondida para trocar a resposta sem cancelar a rodada.

O contrato com o hook (`POST /ask`, `GET /ask/<id>`, formato das respostas) não
muda. `docs/local-api.md` fica como está.

## Comportamento

### Teclado

A pergunta aparece **sem roubar o teclado** do app em uso, como hoje.

O atalho global que já abre o notch pelo teclado (`alternarPeloTeclado`) ganha
um caso: com um card de pergunta na tela, ele dá o teclado ao card em vez de
abrir o card de música. Apertar de novo solta o teclado e devolve o foco ao app
anterior; o card continua na tela.

Com o teclado no card:

| Tecla | Efeito |
|---|---|
| `↑` `↓` | move o destaque entre as opções |
| `1`…`9` | escolhe a opção daquele número (pergunta simples: responde; múltipla: marca/desmarca) |
| `⏎` | pergunta simples: responde com a opção em destaque; múltipla: confirma as marcadas |
| `espaço` | múltipla: marca/desmarca a opção em destaque |
| `←` `→` | troca de aba (pergunta anterior/seguinte), quando há mais de uma |
| `⇥` | leva o cursor ao campo "Outra resposta"; `⇧⇥` volta à lista |
| `esc` | no campo de texto, volta à lista; na lista, solta o teclado (o card fica) |
| `⌘.` | cancela a pergunta, igual ao ✕ (ela volta para o terminal) |

Mudança deliberada: hoje `esc` cancela a pergunta. Passa a soltar o teclado,
porque cancelar por engano custa uma rodada inteira e soltar não custa nada.

Cada opção mostra seu número num selo à esquerda. Com o teclado no card, o
rodapé mostra a legenda das teclas; sem o teclado, mostra qual atalho foca o
card. Clique de mouse segue funcionando exatamente como hoje, e passar o mouse
move o mesmo destaque que as setas movem.

### Várias perguntas: abas com envio direto

Com mais de uma pergunta, o topo do card vira uma fileira de abas, uma por
pergunta, rotulada pelo `header` da pergunta. Cada aba mostra um de três
estados: pendente, atual, respondida (com ✓ e a resposta resumida, truncada).

Responder leva à **próxima aba pendente**. Quando não sobra pendente, a rodada é
enviada na hora — não há tela de revisão.

Clicar numa aba (ou `←` `→`) abre aquela pergunta. Numa pergunta já respondida,
a resposta aparece marcada: opção com ✓, conjunto marcado restaurado, ou o texto
livre de volta no campo. Responder de novo substitui a resposta anterior.

Seleção múltipla ainda não confirmada e texto ainda não enviado **não**
sobrevivem à troca de aba. Com uma pergunta só, não há abas.

### Visual

- **Hierarquia em três faixas**: topo (abas ou chip do `header`, origem da
  sessão, ✕), pergunta como título em linha própria e inteira, corpo (opções,
  preview, campo de texto, legenda).
- **Opção**: selo do número, rótulo, descrição inteira. Três estados visíveis e
  distintos: normal, em destaque (hover ou seta), marcada/respondida.
- **Recomendada**: rótulo que termina em `(Recomendado)` ou `(Recommended)`
  perde o sufixo e ganha um selo. A resposta enviada ao Claude usa o rótulo
  original, com o sufixo.
- **Múltipla escolha**: caixa de marcação alinhada ao selo; o botão vira
  "Confirmar 2" com a contagem e o `⏎` ao lado; desabilitado sem marcação.
- **Campo de texto**: placeholder curto ("Outra resposta…"); a dica de Enter e
  de ditado sai do placeholder e vai para a legenda.
- **Movimento**: troca de aba e de destaque animadas, desligadas com
  "Reduzir movimento".
- Cores, raios e tipografia saem do que o notch já usa. Nenhum efeito de vidro.

### Texto longo

A pergunta e **todas** as descrições aparecem inteiras, sempre. O card deixa de
mudar de altura conforme o cursor anda.

O card cresce até cerca de 60% da altura útil da tela. Acima disso, a lista de
opções rola por dentro; pergunta, abas, campo de texto e legenda ficam fixos.

O preview acompanha a opção em destaque (hover ou seta), usa letra de 11 pt e
ganha a largura que sobra do card. Continua texto monoespaçado puro.

## Arquitetura

O reducer continua sendo o dono das regras; a view só desenha e traduz tecla em
ação.

`AskState` ganha `highlight: Int?` (índice da opção em destaque na página
atual). `AskAction` ganha:

- `goTo(page:)` — troca de aba; restaura `selected`/`text` a partir de
  `answers[pergunta]` se houver, zera se não houver; `highlight` volta ao início.
- `moveHighlight(by:)` e `setHighlight(Int?)` — limitados ao número de opções.
- `choose(index:)` — atalho numérico: fora do intervalo é no-op; simples vira
  `submit`, múltipla vira `toggle`.

`submit` muda em um ponto: em vez de `page += 1`, avança para a próxima página
sem resposta (procurando a partir da atual, com volta ao início); se não houver,
resolve. O invariante é: a rodada resolve no instante em que `answers` cobre
todas as perguntas.

`AskCardView` é dividida em peças pequenas no mesmo arquivo ou em
`Knobler/AskCard/` (abas, linha de opção, preview, rodapé), cada uma recebendo
valores prontos. As teclas entram por `.onKeyPress` (macOS 14) num contêiner
focável; o campo de texto mantém o foco próprio.

O teclado chega pelo caminho que já existe: `NotchPresentation.keyboard` já é
`true` em `.question`; falta o painel virar chave quando o atalho é apertado com
pergunta ativa, e devolver a chave no `esc`/segundo aperto.

## Bordas

- Pergunta nova chega enquanto outra está ativa: entra na fila, como hoje; o
  destaque e a aba zeram na promoção.
- Hook cancela ou a pergunta expira com o teclado no card: o card some e o
  teclado volta ao app anterior.
- Mais de 9 opções: as além da nona não têm número; setas e mouse alcançam.
- Dois monitores: o atalho foca o card da tela onde está o cursor, como já faz
  para o notch.
- Ditado com o card ativo segue alimentando o campo de texto.

## Testes

- `tools/askcheck.swift`: casos novos para `goTo` (restaura resposta simples,
  múltipla e de texto), próxima pendente com volta ao início, resolução quando
  a última pendente é respondida fora de ordem, `choose` fora do intervalo,
  `moveHighlight` nas pontas, descarte de seleção não confirmada na troca de aba.
- `tools/snapshot.sh`: `ask-simple`, `ask-multiselect`, `ask-preview` e
  `ask-paged` regenerados; cenários novos para teclado em foco (destaque +
  legenda), aba respondida revisitada, descrição longa e opção recomendada.
- Ao vivo: `POST /ask` com 3 perguntas (simples, múltipla, com preview),
  respondido só pelo teclado, incluindo voltar e trocar a primeira resposta.

## Documentação

Entrada em `## [Unreleased]` do `CHANGELOG.md`, página de novidades da próxima
MINOR em `Knobler/Novidades/` e a versão em `NovidadesCatalogo.versoes`.

## Fora de escopo

O card de aprovação do Codex (`AgentRequestCard`). O contrato de `/ask`.
Renderizar Markdown no preview. Atalho novo ou configurável só para o card. Card
que pega o teclado sozinho ao aparecer. Tela de revisão antes do envio.

## Pontos para a pesquisa

- `ScrollView` não renderiza no harness de snapshot (sai preto): como rolar a
  lista só quando passa do teto sem perder os snapshots dos casos que cabem.
- Como o painel `nonactivating` vira chave pelo atalho com `.question` ativo e
  devolve o foco ao app anterior; o que `abertoPorTeclado` e `aoPerderTeclado`
  já fazem e o que quebra se reaproveitados.
- `.onKeyPress` dentro do painel do notch: recebe teclas com a janela chave sem
  o app ativo? Convive com o `TextField` focado?
- Qual é o atalho global hoje, onde é configurado, e como mostrá-lo na legenda.
- Tokens visuais do notch (cores, raios, fontes) para o card herdar.
- Referências de cards de escolha guiados por teclado (Raycast, Spotlight, o
  próprio diálogo do Claude Code no terminal).
