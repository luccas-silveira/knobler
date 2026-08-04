# Regras do auto-mapeamento de campos

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: —
- blocked-by: — (001, 002, 003, 006 e 014 fechados)

## Question

Quando um payload chega e os campos estão vazios, o editor deve chutar o mapa.
Decidir: quais nomes de chave viram título, corpo, URL, ícone e id; como tratar
aninhamento e arrays; o que acontece quando nada casa; e se o chute sobrescreve
campo já preenchido (nunca? só se vazio? com desfazer?).

A resposta tem que valer contra os payloads reais levantados nos tickets de
GHL, ClickUp e Notion, não contra um payload inventado.

## Nota de 006 (2026-08-04)

006 fechou definindo que o preset carrega **dicas de forma** (o formato do
caminho, não o caminho literal — `properties.<sua propriedade de título>.title[0].plain_text`).
Elas são semente deste ticket: quando o payload real chega, o auto-mapeamento
casa a forma contra a árvore e propõe o caminho concreto. Ou seja, este ticket
deixa de ser "chute genérico por nome de chave" e passa a ter dois modos —
**com preset** (dicas do preset primeiro, heurística genérica de fallback) e
**sem preset** (só heurística). Decidir as duas.

006 também criou 014 (transformações no template), que **bloqueia este ticket**:
sem saber se existe transformação, não dá pra decidir o que o auto-mapeamento
propõe pra URL do Notion e do ClickUp.

## Nota de 014 (2026-08-04)

014 fechou com **lista fechada de três filtros** no template
(`{{caminho | semHifens}}`, `| data`, `| quill`), renderizados no relay.
O que isso define pra este ticket:

- O auto-mapeamento **pode propor um caminho com filtro**, não só caminho cru.
  A URL do Notion vira `https://www.notion.so/{{<id> | semHifens}}` proposto
  inteiro, não campo vazio.
- Logo a **dica de forma** de 006 precisa carregar o template completo (prefixo
  fixo + caminho + filtro), não só a forma do caminho. Decidir aqui como a dica
  expressa isso.
- Nada de encadeamento nem filtro do usuário: a proposta do auto-mapeamento sai
  da lista fechada, então o espaço de chute é finito.
- A árvore clicável continua inserindo `{{caminho}}` cru — filtro só aparece via
  preset/auto-mapeamento. O chute é a única fonte de filtro na UI.

## Resolução (2026-08-04)

Dois modos, como a nota de 006 previu. **Preset primeiro, heurística de
fallback**, campo a campo — não bloco a bloco.

### Modo com preset: dica de forma casada contra a árvore

A dica de 006 é uma **forma de caminho** com buracos
(`properties.<propriedade de título>.title[0].plain_text`). O casamento anda a
árvore procurando um caminho concreto que satisfaça a forma; achou, o campo
recebe o **template completo** — prefixo fixo, caminho e filtro de 014 quando a
dica pede (`https://www.notion.so/{{id | semHifens}}`).

Dica que não casa não bloqueia o campo: cai na heurística. Dica que casa em mais
de um lugar usa a ocorrência mais rasa; empate na mesma profundidade, a primeira
em ordem alfabética (a árvore já ordena por chave,
`MappingEditorView.swift:107`) — determinismo importa mais que acerto aqui,
porque o usuário corrige com um clique.

### Modo sem preset: heurística por nome de chave

Busca em **largura** (mais raso vence), comparando a chave normalizada
(minúscula, sem `_`, `-` e `.`) contra uma lista fechada por campo:

| Campo | Chaves |
|---|---|
| título | `title`, `name`, `subject`, `taskname`, `summary`, `event` |
| corpo | `body`, `text`, `message`, `description`, `content`, `comment` |
| URL | `url`, `link`, `permalink`, `htmlurl` — **e** o valor precisa começar com `http` |
| id | `id`, `taskid`, `eventid`, `webhookid`, `messageid` |
| ícone | — |

- **Ícone nunca é chutado.** Emoji e URL de imagem são escolha estética, não
  dado do payload; vem do preset ou do perfil.
- **Só folhas** string ou número. Objeto e array nunca viram valor de campo —
  o `render()` do relay já devolve vazio pra objeto (`template.js:16`), chutar
  um seria propor um campo garantidamente vazio.
- **Arrays**: desce sempre pelo índice `0`, e só por ele. É o que os payloads
  reais exigem (`history_items[0]` do ClickUp, `title[0].plain_text` do Notion)
  e evita inventar critério de escolha entre elementos.
- **Profundidade máxima 4**. Abaixo disso o caminho vira ilegível e o acerto cai.
- A ordem da lista é a ordem de preferência: `title` ganha de `name` na mesma
  profundidade.

### Quando roda, o que sobrescreve

- Dispara quando a árvore é populada **e** o campo está vazio. Campo preenchido
  nunca é tocado — nem pelo preset, nem pela heurística, nem em reaplicação.
  Isso é o mesmo princípio de 006 ("o real vence, o preset nunca sobrescreve").
- Roda **uma vez por payload novo**, chaveado pelo `lastPayloadAt` de 007. O
  polling de 2s não re-chuta em cima do que o usuário está digitando.
- O chute entra como texto normal nos campos, não como estado à parte: é
  editável na hora, e o `allowsUndo` do `NSTextView` já cobre o desfazer.
- Um banner não-bloqueante no topo do editor diz que os campos foram sugeridos e
  oferece **"Limpar sugestões"**, que esvazia só os campos que o chute preencheu
  e que ainda não foram editados. O banner some ao primeiro toque em qualquer
  campo.

### Nada casa

Campos ficam vazios e o banner troca de texto: "não reconheci este payload —
clique num valor da árvore pra inserir". Sem erro, sem modal. Este é o caminho
esperado pro webhook de workflow do GHL, cujo corpo é customizável e não tem
forma fixa (001).

### Validação pendente

As listas acima valem contra os payloads dos researches 001–003. Os tickets de
captura 010, 011 e 012 trazem payload real dos três caminhos que faltam — a
regra não muda com eles, mas **as listas de chaves podem ganhar entradas**.
Ajustar lista é edição de literal, não redecisão.

## Nota das capturas 010 e 012 (2026-08-04)

Payload real revelou três chaves que a lista fechada não cobre. **Edição de
literal, não redecisão** — a regra (largura, só folhas, primeira que casa)
continua valendo.

| Campo | Acrescentar | Por quê |
|---|---|---|
| título | `fullname`, depois `firstname` | GHL workflow manda `full_name`; normalizado vira `fullname` e não casa com `name`. Hoje o título sairia vazio |
| corpo | `textcontent` **antes** de `content` | ClickUp Automação manda `content` = **Quill escapado** e `text_content` = o mesmo texto limpo. Com a lista atual o corpo do card viraria JSON de Quill |
| id | `contactid` | GHL workflow identifica por `contact_id` |

A ordem importa em `textcontent`/`content`: os dois estão na mesma
profundidade (`payload.*`), e o desempate hoje é alfabético — `content` venceria.
Pôr `textcontent` primeiro na lista resolve sem mexer na regra de desempate.

Nada a mudar no ClickUp de **API** (§1-§5 do research): lá o corpo continua sendo
`history_items[0].after`, alcançado por preset, não por heurística.
