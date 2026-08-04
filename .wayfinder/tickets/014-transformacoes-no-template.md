# Transformações no template

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: —
- blocked-by: — (006 fechado). Desbloqueou 005.

## Question

Hoje o template do relay (`relay/src/server.js`, `render()`) só substitui
`{{caminho}}` por um valor do payload. Dois dos cinco caminhos de preset não
conseguem produzir a URL de abrir com isso:

- **Notion** não manda `url`, só o id. O deep link é derivado:
  `https://www.notion.so/<id sem hífens>` — exige remover hífens.
- **ClickUp** idem: `https://app.clickup.com/t/{{task_id}}` — este caso a
  concatenação literal no template já resolve, porque o prefixo é texto fixo.
- **ClickUp, corpo de descrição**: `history_items[0].after` vem como JSON Quill
  escapado; virar texto legível exige parse + join de `ops[].insert`.
- **ClickUp, timestamp**: `history_items[0].date` é epoch em ms **como string**.

Decidir se o template ganha alguma forma de transformação e qual, sem virar
linguagem de programação dentro do painel (`PRODUCT.md` proíbe dev-tool denso).

Formas na mesa, da mais barata à mais cara:

1. **Nenhuma.** O Notion fica sem URL e o preset instrui o usuário a criar uma
   propriedade fórmula na database com o link (saída sem código, citada no
   research). Zero mudança no relay.
2. **Lista fechada de filtros** — `{{id | semHifens}}`, `{{date | dataCurta}}`,
   `{{after | quill}}`. Poucos, nomeados em pt-BR, escritos pelo preset e quase
   nunca pelo usuário à mão.
3. **Transformação embutida no preset**, invisível no template: o preset declara
   a derivação em código Swift/JS e o mapa guarda o resultado. Mais poder, mas o
   usuário não consegue reproduzir nem editar o que o preset fez.

Decidir junto: se a transformação roda **no relay** (na renderização, vale pra
fila e pra push) ou **no app**. O relay é quem renderiza hoje.

## Resolução (2026-08-04)

**Opção 2: lista fechada de filtros, no relay.** Sintaxe `{{caminho | filtro}}`.

### Por que não as outras

- **Opção 1 (nenhuma)** morre no Notion. A saída sem código exige o usuário
  digitar uma fórmula à mão na database (`"https://notion.so/" + replaceAll(id(), "-", "")`).
  Isso é escrever código fora do nosso controle, sem nossa mensagem de erro:
  tentativa-e-erro exportada, não eliminada — contra o destino do mapa.
- **Opção 3 (transformação escondida no preset)** produz um mapa que o usuário
  vê mas não consegue reproduzir nem editar. Quebra a regra de 006 ("reaplicar
  é sempre manual", o mapa é sempre editável) e cria um segundo mecanismo de
  derivação que não aparece no template.

### Os filtros (três, fechados, pt-BR)

| Filtro | Faz | Caso |
|---|---|---|
| `semHifens` | remove `-` | URL do Notion: `https://www.notion.so/{{id \| semHifens}}` |
| `data` | epoch (ms, número ou string) → data curta local | `history_items[0].date` do ClickUp |
| `quill` | parse do JSON Quill + join de `ops[].insert` | `history_items[0].after` do ClickUp |

Regras:

- **Um filtro por token.** Sem encadeamento, sem argumentos, sem expressões.
  É o que impede virar linguagem de programação dentro do painel (`PRODUCT.md`).
- **Filtro desconhecido = valor cru**, nunca erro nem vazio. Falha suave, igual
  ao caminho ausente que já renderiza vazio hoje.
- **Filtro que não se aplica** (`quill` num texto que não é JSON Quill, `data`
  num valor não-numérico) devolve o valor cru.
- Lista fechada: crescer exige release, igual a preset (006). Não há filtro
  definido pelo usuário.

### Onde roda

**No relay**, dentro de `render()` (`relay/src/template.js`) — é o único
renderizador de verdade e vale igual pra push e pra fila. O app **espelha** em
`renderTemplate()` (`Knobler/MappingEditorView.swift:188`), que já duplica o
motor hoje pra prévia; sem espelhar, a prévia mentiria. Duplicação aceita: o
motor já é duplicado, o delta é o mesmo dos dois lados.

### Quem escreve

**O preset escreve; o usuário pode editar.** O filtro é texto no template, não
estado escondido — quem sabe o que faz, digita. Mas a árvore clicável continua
inserindo só `{{caminho}}` cru: descobrir filtro não é trabalho da árvore, é do
preset e da doc. Zero UI nova.

### Fora do escopo desta decisão

Concatenação com texto fixo já funciona (`relay/src/template.js:11` faz replace
dentro de string qualquer) — o caso ClickUp/URL do enunciado não precisava de
nada.

### Fica pra execução

- `relay/src/template.js` + caso novo em `relay/test/template.test.js` (`node --test`).
- Espelho em `Knobler/MappingEditorView.swift` + gate em `tools/check.sh`.
- `docs/webhooks.md`: tabela dos três filtros.
