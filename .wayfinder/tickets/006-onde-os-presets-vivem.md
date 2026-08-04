# Onde os presets vivem e como versionam

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: sessão 2026-08-04
- blocked-by: — (001, 002 e 003 fechados) · bloqueia a execução de 004

## Question

Um preset (GHL, ClickUp, Notion) é mapa + payload de exemplo + ícone. Decidir
onde ele mora: embutido no bundle do app (versiona com o release, funciona
offline, corrigir um preset exige update do app) ou servido pelo relay
(corrige sem release, mas adiciona dependência de rede num fluxo que já é
frágil quando offline).

Decidir junto: o preset preenche o mapa e sai da frente, ou fica ligado ao
perfil como "origem" que pode ser reaplicada quando o preset é atualizado?

## Nota dos researches (2026-08-04)

Os três researches convergiram num aperto: **preset como "mapa pronto de forma
fixa" cobre menos do que parecia**. GHL de workflow tem corpo customizável e
variável por gatilho; ClickUp de API não manda o nome da tarefa; Notion não
manda URL. Antes de decidir onde o preset mora, decidir o que ele **é** — mapa
pronto, ou receita de configuração (payload de exemplo + instruções do lado do
serviço + mapa sugerido editável). A segunda forma é a que sobrevive aos três.

## Nota de 004 (2026-08-04)

004 fechou com **assistente de passos**, e dois dos cinco passos (Serviço e
Link) são preenchidos pelo preset: nome/ícone do serviço, instrução de onde
colar o link do lado do serviço, sugestão de mapa e a ressalva do serviço
(workflow do GHL, nome de tarefa do ClickUp, URL do Notion). Este ticket passou
a **bloquear a implementação desses dois passos** — decidir aqui o que o preset
carrega, não só onde ele mora.

## Resolução — 2026-08-04

**Preset é receita, mora no bundle, fica ligado ao perfil como origem.** Cinco
decisões, na ordem em que foram grilladas.

### 1. Grão = caminho, não serviço

"Serviço" não é unidade coerente: GHL são dois sistemas incompatíveis
(Marketplace camelCase com `type`/`webhookId` × workflow snake_case sem
discriminador nem dedupe) e ClickUp tem dois caminhos (webhook de API × automação
"Call webhook"). O passo Serviço de 004 lista **caminhos achatados**, agrupados
por serviço num `Section` do `Form`:

```
GoHighLevel — app do Marketplace
GoHighLevel — ação Webhook num workflow
ClickUp — webhook de API
ClickUp — automação "Call webhook"        (só se 010 confirmar o payload)
Notion — automação de database
Outro / genérico
```

Cada caminho tem instrução, exemplo, ressalva e assinatura próprios. Lê como
três serviços na tela sem mentir no conteúdo.

### 2. Preset não é mapa — é o que faz o auto-mapeamento acertar

Mapa fixo escrito à mão só é possível em 2 dos 5 caminhos: as chaves do Notion
são `properties.<nome que o usuário escolheu>` e o corpo do GHL de workflow varia
por gatilho. Então o preset carrega **duas coisas com papéis diferentes**:

- **Mapa fixo (opcional)** — só onde as chaves são universais (GHL Marketplace;
  parcialmente ClickUp de API). Aplica na hora, antes de chegar payload nenhum.
- **Dicas de forma (sempre)** — não caminhos literais, mas o *formato* do caminho
  (`properties.<sua propriedade de título>.title[0].plain_text`). Vira texto na
  tela **e** semente pro auto-mapeamento: quando o payload real chega, 005 casa a
  forma contra a árvore e propõe o caminho concreto.

Consequência: **005 deixa de ser auto-mapeamento genérico** e passa a receber
pista do preset. 005 ainda está aberto — anotado lá.

### 3. Payload divergente: o real sempre vence, o preset some

Cada caminho declara uma **assinatura mínima** (1–2 chaves discriminantes, nunca
o exemplo inteiro):

| caminho | assinatura |
|---|---|
| GHL Marketplace | `type` **e** `locationId` |
| GHL workflow | `first_name` **ou** `location.id` |
| ClickUp API | `event` **e** `task_id` |
| Notion | `data.properties` (objeto) |

Casou: aplica mapa fixo e dicas. **Não** casou: mapa fixo **não** é aplicado e
aparece uma linha não-bloqueante no passo do mapa — "Esse envio não parece
<caminho>. O mapa sugerido foi desligado; a árvore ao lado é o que chegou de
verdade. [Trocar o serviço] [Ignorar]".

Validação dura foi rejeitada: GHL de workflow varia legitimamente por gatilho e
`history_items[].after` do ClickUp é polimórfico — falso positivo em payload
válido. A regra dura é a outra ponta: **o preset nunca sobrescreve nem filtra o
payload real**, só some quando não serve. É essa a falha que mata o destino do
mapa (mapa de exemplo aplicado sobre payload diferente = card vazio em silêncio).

Isto também define a fonte "exemplo embutido" das quatro: serve pra montar mapa
**antes** do primeiro POST; quando o real chega, é descartado como fonte, nunca
mesclado.

### 4. Origem fica ligada ao perfil — dentro do `mapping`, sem coluna nova

`relay/src/server.js:109-120` lê só `m.title/body/url/sound/id/iconTemplate` do
mapping: **chave desconhecida é ignorada em silêncio**. Então a origem mora ali:

```json
{ "title": "…", "body": "…", "_origem": { "preset": "ghl-marketplace", "versao": 1 } }
```

Zero mudança no relay, zero migração, e viaja junto com o perfil. Underscore
marca "não é slot do card". `ponytail:` no ponto onde grava, apontando pra coluna
dedicada se um dia precisar consultar origem sem baixar o mapping inteiro.

Paga: aviso de divergência (§3) continua valendo **depois** do assistente (o
gatilho do workflow muda seis meses depois e o card esvazia — sem origem gravada
não há contra o que comparar); linha do perfil mostra o serviço; "reaplicar mapa
sugerido" tem sentido.

Duas consequências aceitas de propósito:

- Perfil captura-only não tem origem. No assistente não acontece: o passo Serviço
  já grava mapa antes do primeiro POST.
- **Reaplicar é sempre manual.** Preset atualizado nunca reescreve mapa: mostra
  "o preset do ClickUp mudou — [ver o que muda] [reaplicar]". Reaplicar em
  silêncio destrói edição do usuário — mesma falha de §3 com outro chapéu.

### 5. Bundle, literal Swift, versão inteira por preset

**Bundle e ponto — sem override servido pelo relay.** A restrição offline já
elimina o relay como fonte primária (o passo Serviço mostra instrução antes de
qualquer rede, e no primeiro contato o relay pode nem estar pareado).

Literal Swift, não JSON de recurso: JSON custaria parse, arquivo faltando e um
caminho de erro em runtime, para dado que só muda quando o app muda. Literal dá
erro de compilação em vez de erro de usuário.

```swift
struct Preset {
    let id: String            // "ghl-marketplace"
    let versao: Int
    let servico: String       // agrupa o Form
    let caminho: String
    let icone: String
    let instrucao: String     // onde colar o link, do lado do serviço
    let ressalva: String?
    let assinatura: [String]  // §3
    let mapaFixo: [String: String]?   // §2, só onde as chaves são universais
    let dicasDeForma: [Dica]          // §2, semente pro 005
    let exemplo: String       // a fonte "exemplo embutido"
}
```

**Versão = `Int` monotônico por preset**, não a versão do app; bump só quando o
conteúdo muda de um jeito que valha reaplicar. `_origem.versao < preset.versao` é
a condição exata do aviso de §4.

Corolário aceito: **corrigir preset errado exige release do app.** O alívio já
existe sem preset nenhum — as outras três fontes de payload (ao vivo, colar JSON,
histórico) mais a árvore clicável resolvem na mão. Preset é atalho, não
pré-requisito; override remoto seria fetch + cache + fallback + versão divergente
entre Macs pra economizar um release.

### O que isto destrava e o que isto cria

- **Destrava 004**: os passos Serviço e Link têm conteúdo definido
  (`servico`/`caminho`/`icone`/`instrucao`/`ressalva`).
- **Muda 005**: auto-mapeamento recebe `dicasDeForma` do preset.
- **Cria ticket novo**: `mapaFixo` e `dicasDeForma` não conseguem produzir a URL
  do Notion (só id, deep link derivado) nem a do ClickUp
  (`https://app.clickup.com/t/{task_id}`), porque hoje o template só substitui
  `{{caminho}}`. Virou
  [Transformações no template](014-transformacoes-no-template.md), que bloqueia 005.

## Nota das capturas 010 e 012 (2026-08-04)

**As assinaturas escolhidas sobrevivem ao payload real** — com uma lacuna.

| caminho | assinatura | veredito |
|---|---|---|
| GHL workflow | `first_name` **ou** `location.id` | ✅ o payload real tem **os dois** |
| ClickUp API | `event` **e** `task_id` | ✅ e o payload da Automação **não** tem nenhum dos dois, então os caminhos não se confundem |
| ClickUp **Automação** | — | ⚠️ **a tabela não tem linha pra ele.** Proposta: `auto_id` **e** `payload.id` (`auto_id` é exclusivo da Automação; `payload` é o envelope) |
| GHL Marketplace | `type` **e** `locationId` | não recapturado nesta sessão; permanece como estava |
| Notion | `data.properties` | **não verificado** — ticket 011 não foi executado |

Dicas de forma que as capturas confirmam:

- ClickUp Automação: título `payload.name`, corpo **`payload.text_content`**
  (não `payload.content`, que é Quill escapado — o filtro `quill` de 014 é
  desnecessário neste caminho), URL `https://app.clickup.com/t/{{payload.id}}`.
- GHL workflow: título `full_name`, id `contact_id`, e a URL só existe montada:
  `https://app.gohighlevel.com/v2/location/{{location.id}}/contacts/detail/{{contact_id}}`
  — **dois tokens no mesmo campo**, que `render()` já resolve. É a primeira dica
  de forma com dois buracos; vale conferir na implementação que o casamento de
  005 lida com isso.
