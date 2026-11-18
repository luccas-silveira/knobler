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

A pergunta aparece **sem roubar o teclado**, sempre — nem do app em uso, nem do
próprio notch.

Se o usuário está digitando dentro do notch (nota, WhatsApp, agenda, lembretes —
o que o app já chama de `protegeEdicao`), a pergunta **espera** naquela tela: o
card em uso continua onde está e ganha um selo discreto no topo, "Claude
perguntou". A pergunta abre quando ele sai do campo (Esc, clique fora) ou clica
no selo, e abre sem teclado. Abrir pelo selo não descarta o rascunho do campo.
Nas outras telas a pergunta aparece na hora. O card de aprovação do Codex não
entra nessa espera: segue como hoje.

O atalho global que já abre o notch pelo teclado (⌃⌥K por padrão, configurável)
ganha um caso: com um card de pergunta do Claude na tela, ele dá o teclado ao
card em vez de abrir o card de música. Apertar de novo solta o teclado, que
volta ao app da frente; o card continua na tela. Clicar no campo "Outra
resposta" também dá o teclado ao card, como hoje.

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

Números valem pelo caractere digitado, não pela posição da tecla (teclado
numérico e layouts não americanos incluídos). Segurar um número ou o Enter não
repete a ação; segurar uma seta repete.

Cada opção mostra seu número num selo à esquerda. Com o teclado no card, o
rodapé mostra a legenda das teclas; sem o teclado, mostra qual atalho foca o
card, lido da configuração atual — se o usuário apagou o atalho nos Ajustes, a
dica não aparece. Clique de mouse segue funcionando exatamente como hoje, e passar o mouse
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
- Cores, raios e tipografia saem do que o notch já usa: branco em opacidades
  sobre preto (linha normal, em destaque e marcada em três degraus), raio 8,
  selo em cápsula. O notch não tem arquivo de estilo nem cor de destaque; se o
  card continua monocromático ou ganha uma cor só dele se decide no mockup.
  Nenhum efeito de vidro.

### Texto longo

A pergunta e **todas** as descrições aparecem inteiras, sempre. O card deixa de
mudar de altura conforme o cursor anda.

O card cresce até 60% da distância entre o topo da tela e o Dock. Acima disso, a
lista de opções rola por dentro; pergunta, abas, campo de texto e legenda ficam
fixos. Enquanto cabe, não existe área rolável nenhuma.

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
resolve. O invariante é: a rodada resolve no instante em que o texto de toda
pergunta tem resposta em `answers`. A conta é por pergunta, não pelo número de
respostas guardadas — as respostas são indexadas pelo texto (é o contrato com o
hook), e duas perguntas de mesmo texto dividem uma resposta.

`AskCardView` é dividida em peças pequenas em `Knobler/AskCard/` (abas, linha de
opção, preview, rodapé), cada uma recebendo valores prontos. Cada arquivo novo
entra em `tools/notchview-fontes.txt` e pede `xcodegen generate`.

**Dono do teclado.** A posse do teclado pelo card é um estado próprio do
`NotchViewModel` daquela tela, separado do `abertoPorTeclado`. Este último não
serve: tirar o mouse do card o zera em 0,3 s, e ele arma o card de música por
trás da pergunta. `alternarPeloTeclado` ganha um ramo anterior a tudo: com
pergunta do Claude ativa e visível (`askStore.state.active`, não o card do
Codex), liga ou desliga a posse e faz o painel virar ou largar a chave, sem
tocar em `expanded`. A posse cai sozinha quando a pergunta sai da tela.

**Teclas.** Entram pelo vigia de teclas que o app já tem
(`KnoblerApp.swift:1001`), num ramo que vem antes do de seções: painel chave,
posse ligada, pergunta do Claude ativa e cursor fora de campo de texto. Ele
traduz a tecla em `AskAction` e a consome. Com o cursor no campo de texto, só
trata `esc` (volta à lista) e `⇧⇥`. Nada de `.onKeyPress` nem contêiner focável:
esse caminho perde o `⇧⇥`, depende de um foco inicial que o sistema não reavalia
num painel já existente e desenha anel de foco. O pedido de "leve o cursor ao
campo" (`⇥`) viaja por um sinal que a view observa.

**Espera durante a digitação.** `contentState(question:)` passa a receber
"há pergunta do Claude **e** esta tela não está em `protegeEdicao`", ou o clique
no selo. O selo é uma peça pequena desenhada pelo `NotchView` sobre o card em
edição.

**Troca de aba.** A página sai da identidade do conteúdo (`contentID`), para a
troca não disparar a animação de card inteiro; a transição acontece dentro do
card e a altura acompanha pela medida.

**Rolagem acima do teto.** Duas variantes da lista — conteúdo puro, e o mesmo
conteúdo dentro de uma área rolável — com o sistema escolhendo a primeira que
cabe no teto (`ViewThatFits`). A auto-medição do card deixa de usar "o maior
valor visto" e passa a aceitar encolher.

## Bordas

- Pergunta nova chega enquanto outra está ativa: entra na fila, como hoje; o
  destaque e a aba zeram na promoção.
- Hook cancela ou a pergunta expira com o teclado no card: o card some e o
  teclado volta ao app anterior.
- Mais de 9 opções: as além da nona não têm número; setas e mouse alcançam.
- Dois monitores: o atalho foca o card da tela onde está o cursor, como já faz
  para o notch.
- Ditado com o card ativo segue alimentando o campo de texto.
- Teclado bloqueado (`POST /keyboard/lock`) vence a pergunta: o card some e a
  posse do teclado cai junto.
- O destaque mora no estado compartilhado: passar o mouse numa tela move o
  destaque nas outras. Aceito — página, seleção e texto já são compartilhados.
- Deslizar de lado sobre o card hoje pode virar gesto de trocar de música.
  Quando a lista rolar, conferir ao vivo que a rolagem vertical chega nela e
  que o gesto lateral não dispara.
- Pergunta em espera expira (15 min) ou é cancelada pelo hook: o selo some.

## Testes

- `tools/askcheck.swift`: casos novos para `goTo` (restaura resposta simples,
  múltipla e de texto), próxima pendente com volta ao início, resolução quando
  a última pendente é respondida fora de ordem, `choose` fora do intervalo,
  `moveHighlight` nas pontas, descarte de seleção não confirmada na troca de aba.
- `tools/snapshot.sh`: os cenários `ask-*` passam a rodar na janela real do
  harness (como `agenda-`, `lembretes-`, `whatsapp-`), onde campo de texto e
  rolagem desenham — hoje o preview sai vazio e o campo sai como "proibido".
  `ask-simple`, `ask-multiselect`, `ask-preview` e `ask-paged` regenerados;
  cenários novos para teclado em foco (destaque + legenda), aba respondida
  revisitada, descrição longa, opção recomendada, lista acima do teto e o selo
  "Claude perguntou" sobre a nota.
- `tools/presentationcheck.swift`: pergunta não vence a tela em edição.
- Ao vivo: `POST /ask` com 3 perguntas (simples, múltipla, com preview),
  respondido só pelo teclado, incluindo voltar e trocar a primeira resposta;
  pergunta chegando no meio da digitação da nota; rolagem com evento real.

## Documentação

- `## [Unreleased]` do `CHANGELOG.md`, `Knobler/Novidades/0.38.0.html` e a
  versão em `NovidadesCatalogo.versoes`.
- `docs/ask.md` e as imagens `docs/images/ask-simple.png` e
  `ask-multiselect.png`.
- Comentários que ficam falsos: `Knobler/Ask.swift:15` ("paginação 1/N") e
  `Knobler/LinkPreviewView.swift:39` ("Esc fecha como no card de pergunta").
- `.claude/skills/snapshot-ui/SKILL.md`: os cenários `ask-*` saem da lista do
  que não renderiza.
- As specs antigas (`2026-07-17`, `2026-08-11`) são registro histórico e não
  são reescritas.

## Fora de escopo

O card de aprovação do Codex (`AgentRequestCard`). O contrato de `/ask`.
Renderizar Markdown no preview. Atalho novo ou configurável só para o card. Card
que pega o teclado sozinho ao aparecer. Tela de revisão antes do envio.

## Decisões do grill

Dossiê: `docs/vesta/research/2026-11-18-card-pergunta-redesenho-research.md`

- **A1, A2, A3, A11** — a posse do teclado pelo card virou estado próprio, com
  ramo próprio no atalho, e só para a pergunta do Claude. Motivo: o estado
  "aberto pelo teclado" existente não dá a chave ao painel em modo pergunta,
  arma o card de música por trás, é zerado quando o mouse sai, e seu vigia de
  teclas engole ← → Tab e Esc.
- **A5** — as teclas entram pelo vigia de teclas do app, não por foco do
  SwiftUI. Motivo: ⇧⇥ não chega ao `.onKeyPress`, o foco inicial não é
  reavaliado num painel já existente, e o vigia é o padrão do repositório.
- **A4** — pergunta que chega durante a digitação no notch espera naquela tela,
  com o selo "Claude perguntou" no card em uso; abre ao sair do campo ou no
  clique do selo. Decisão do usuário, contra a recomendação de mostrar o card
  na hora sem teclado. Motivo: nada interrompe a digitação, e o selo cobre o
  risco de o Claude esperar sem ninguém ver.
- **A6** — números lidos pelo caractere; repetição só nas setas.
- **A7** — soltar o teclado usa o caminho que o app já usa; ninguém guarda o app
  anterior. Motivo: o painel nunca ativa o app, então o app da frente recebe as
  teclas de volta sozinho — validado ao vivo em julho.
- **A8** — `esc` solta o teclado em vez de cancelar, mantido. Motivo: aprovado
  pelo usuário com a spec; cancelar segue no ✕ e no `⌘.`, que a HIG também
  reserva para cancelar.
- **A9** — a rodada resolve quando o texto de toda pergunta tem resposta.
- **A10** — destaque compartilhado entre telas, aceito.
- **A12** — teto de 60% com rolagem e descrições sempre inteiras, mantidos.
  Motivo: aprovados pelo usuário; desfazem de propósito a decisão de agosto
  ("sem teto, descrição inteira só sob o cursor"), que fazia o card pular.
- **A13, A15** — rolagem só acima do teto por escolha entre duas variantes; a
  página sai da identidade do conteúdo para a troca de aba animar só por dentro.
- **A14** — cenários `ask-*` vão para a janela real do harness.
- **A16** — monocromático ou cor de destaque: decide no mockup.
- **A17** — a legenda lê o atalho atual e some se ele foi apagado.
- **A18, A21** — viraram bordas a conferir.
- **A19** — a lista de documentação cresceu.
- **A20** — sem tela de revisão, mantido. Motivo: escolha do usuário; o diálogo
  do terminal tem revisão, o card privilegia um passo a menos.
