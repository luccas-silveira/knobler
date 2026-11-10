# Ponte do WhatsApp: contrato

## Visão geral

A ponte (`~/Code/whatsapp-mcp/whatsapp-bridge`, Go + whatsmeow, serviço do
macOS `com.whatsapp-mcp.bridge`) é o único processo que fala com o WhatsApp.
Este documento é o contrato dela com os dois clientes:

- o **Knobler**, que só usa HTTP e o canal ao vivo;
- o **MCP do Claude** (`whatsapp-mcp-server`), que lê o SQLite direto e usa
  HTTP para agir.

É a fonte única que os planos da ponte e do Knobler citam. Spec:
`docs/vesta/specs/2026-11-04-whatsapp-design.md`; pesquisa (números `A..`
citados abaixo): `docs/vesta/research/2026-11-04-whatsapp-research.md`.

- Endereço: `http://127.0.0.1:8099`. A porta vem de `WHATSAPP_BRIDGE_PORT`
  (padrão `8099`), como hoje. A ponte escuta **só** em `127.0.0.1`.
- Versão do contrato: **1**. Mudança que só acrescenta (campo, rota, tipo de
  evento) não muda o número. Mudança que quebra cliente sobe para 2, e o
  Knobler trata qualquer valor diferente de 1 como "ponte incompatível".
- A ponte sobe e abre o HTTP **sem nenhuma conta logada** (A56, A70). Cada
  conta conecta, cai e religa sozinha, sem afetar a outra.
- Nenhuma rota exige que o cliente diga a conta. Sem `conta`, vale a **conta
  padrão** (o 4143, ver [Contas](#contas-e-conta-padrão)). O Knobler manda
  `conta` sempre; o padrão existe para o MCP e as rotas antigas.

## Chave de acesso

Toda requisição, inclusive as rotas antigas `/api/*` e o canal ao vivo,
exige a chave. Sem ela, `401`.

| Item | Valor |
|---|---|
| Arquivo | `~/Library/Application Support/whatsapp-bridge/api-key` |
| Pasta | modo `0700` |
| Arquivo | modo `0600` |
| Conteúdo | 64 caracteres hexadecimais minúsculos (32 bytes aleatórios), sem quebra de linha |
| Cabeçalho | `Authorization: Bearer <chave>` |

**Quem cria: a ponte**, na subida, se o arquivo não existir. Knobler e MCP só
leem e nunca criam. O padrão é o do `Knobler/TokenDeAgente.swift`:

1. cria a pasta com `0700` e **impõe** `0700` mesmo se ela já existir;
2. gera 32 bytes com `crypto/rand` e codifica em hex;
3. abre um temporário `.api-key.<aleatório>` na mesma pasta com
   `O_CREAT|O_EXCL` e modo `0600`, escreve e faz `rename` por cima do destino.
   O arquivo nunca existe com outro modo.

A chave é **persistente**: sobrevive ao religar da ponte (ao contrário do
token do `TokenDeAgente`, que nasce a cada sessão). Na subida, a ponte lê o
arquivo, corta espaço e quebra de linha das pontas e confere o formato. Se o
conteúdo não forem 64 caracteres hex, ela gera outra chave do mesmo jeito e
registra no log que trocou. Se não conseguir gravar, a ponte **sai com erro**
(o launchd religa): ela nunca serve sem chave. A comparação é em tempo
constante (`crypto/subtle`).

Para trocar a chave: apague o arquivo e religue a ponte.

Os clientes leem o arquivo, cortam espaço das pontas e guardam a chave em
memória. Quando recebem `401`, releem o arquivo **uma vez** e repetem a
requisição. Se der `401` de novo, o Knobler mostra "a chave não confere" e o
MCP devolve erro com o mesmo texto.

O Knobler só sonda a ponte se o arquivo existir. Sem arquivo, nenhuma
conexão é aberta (spec, peça instalável).

## Segurança: requisições de navegador

A chave não basta contra página aberta no navegador (A20). A ponte recusa
com `403`, **antes** de olhar a chave, a requisição que só um navegador faria.
É a mesma regra do `Knobler/NotchAPIGuard.swift`, portada para Go:

- `Host` presente e diferente de `127.0.0.1`, `localhost`, `127.0.0.1:<porta>`
  ou `localhost:<porta>` → `403 host_nao_permitido` (DNS rebinding).
- `Origin` presente e diferente de `http://127.0.0.1:<porta>` ou
  `http://localhost:<porta>` → `403 origem_nao_permitida` (CSRF).
- `Sec-Fetch-Site` presente e diferente de `none` ou `same-origin` →
  `403 outro_site` (GET cruzado, como `<img src=…>`).

A comparação ignora maiúsculas. curl, `requests` do Python, `URLSession` e a
própria ponte não mandam `Origin` nem `Sec-Fetch-Site` e passam. Vale igual
para o handshake do WebSocket.

Ordem de checagem em toda rota: guarda de navegador (`403`), chave (`401`),
método (`405`), corpo (`400`/`413`), conta (`404`).

## Layout em disco

Tudo mora em `store/`, relativo à pasta de trabalho da ponte
(`~/Code/whatsapp-mcp/whatsapp-bridge/store`, o `WorkingDirectory` do serviço).

```
store/
  whatsapp.db                      cofre do whatsmeow: TODAS as sessões (um aparelho por conta)
  messages.db                      mensagens da conta padrão (o 4143), o arquivo de hoje, sem migração
  eventos.db                       diário numerado do canal ao vivo (todas as contas)
  contas.json                      manifesto das contas: é por ele que o MCP acha os bancos
  contas/
    554791744143/
      midia/<chat>/<id>.<ext>      mídia baixada da conta padrão, daqui pra frente
      fotos/<jid>.<id-da-foto>.jpg cache de foto de perfil
    554792508292/
      messages.db                  mensagens do 8292
      midia/<chat>/<id>.<ext>
      fotos/…
  <chat>/…                         mídia antiga do 4143, nome por segundo (legado, só leitura)
```

Pasta e arquivo **novos** nascem com `0700`/`0600`. A ponte não mexe no modo
do que já existe.

### Cofre de sessões

Um `sqlstore.Container` só, em `store/whatsapp.db`, com um
`whatsmeow.Client` por aparelho (`GetAllDevices`, A68). A ponte deixa de usar
`GetFirstDevice`. Conta nova nasce de `container.NewDevice()` no pareamento.
A tabela `whatsmeow_contacts` já separa por conta na coluna `our_jid` (JID do
aparelho, com o sufixo `:N`); `whatsmeow_lid_map` é global.

### Identidade da conta

A conta é identificada pelo **número**: a parte de usuário do JID do aparelho,
só dígitos, com DDI (`554791744143`, `554792508292`). É o valor do parâmetro
`conta` em todo lugar. O JID do aparelho (`554791744143:17@s.whatsapp.net`)
muda a cada pareamento; o número não. Não há apelido nem sufixo curto:
`conta=4143` responde `404 conta_inexistente`. Quem quiser aceitar "4143" (o
MCP, por exemplo) resolve o sufixo pela lista de contas antes de chamar.

### Bancos de mensagens

Um banco por conta (decisão A51/A67/A52/A66): grupo em comum não colide e o
`is_from_me` de cada conta fica certo.

- A **primeira conta registrada** no `contas.json` é a padrão e usa
  `store/messages.db`. Na primeira subida da ponte multi-conta, sem
  `contas.json`, a ponte registra o aparelho que já está no cofre (o 4143)
  como padrão. É assim que o `messages.db` atual vira o do 4143 sem mover
  nada.
- Toda outra conta usa `store/contas/<numero>/messages.db`, criado no
  primeiro pareamento.
- Conta deslogada **continua** no `contas.json`, com `jid` nulo, e mantém o
  banco. Parear o mesmo número de novo religa a conta ao mesmo banco.

Os bancos de mensagens e o `eventos.db` abrem em WAL, com
`_txlock=immediate` e `_busy_timeout=5000` (A65/A69). O `whatsapp.db` também
passa a WAL. O esquema de hoje fica. A ponte só **acrescenta**, com
`ALTER TABLE … ADD COLUMN` idempotente (as consultas do MCP nomeiam colunas,
então nada quebra):

```sql
-- chats
unread_count     INTEGER NOT NULL DEFAULT 0
marked_unread    INTEGER NOT NULL DEFAULT 0

-- messages
mimetype         TEXT
is_voice         INTEGER NOT NULL DEFAULT 0   -- nota de voz (PTT)
duration_seconds INTEGER                      -- áudio e vídeo
thumbnail        BLOB                         -- JPEGThumbnail da mensagem, quando vier
quoted_id        TEXT
quoted_sender    TEXT
quoted_text      TEXT                         -- só o texto da original (A80)
edited_at        TIMESTAMP
deleted_at       TIMESTAMP
status           TEXT                         -- só em is_from_me: 'sent' | 'delivered' | 'read'

CREATE TABLE IF NOT EXISTS reactions (
  chat_jid   TEXT NOT NULL,
  message_id TEXT NOT NULL,
  sender     TEXT NOT NULL,                   -- JID completo de quem reagiu
  emoji      TEXT NOT NULL,
  timestamp  TIMESTAMP NOT NULL,
  PRIMARY KEY (chat_jid, message_id, sender)
);
CREATE INDEX IF NOT EXISTS idx_messages_chat_ts ON messages (chat_jid, timestamp);
```

Regras de gravação que o MCP vê:

- `media_type` ganha o valor `sticker`. Reação, edição e apagamento deixam de
  ser descartados (A54), mas **não viram linha** em `messages`: reação vai
  para `reactions` (emoji vazio apaga a linha), edição troca `content` e
  preenche `edited_at`, apagamento ("apagar para todos") limpa `content` e os
  campos de mídia, preenche `deleted_at` e apaga o arquivo baixado.
- `last_message_time` de `chats` só anda com mensagem que vira linha. Reação
  e figurinha descartada deixam de subir a conversa (A63).
- `sender` mantém o formato de hoje (às vezes só o número, às vezes JID
  completo, A62). A API devolve sempre o JID completo.
- `filename` guarda o nome de exibição: o original no documento, `<id>.<ext>`
  nos outros tipos.

### Mídia

O arquivo baixado é nomeado pelo **id da mensagem** (A58):
`store/contas/<numero>/midia/<chat>/<id>.<ext>`, onde `<chat>` é o `chat_jid`
com `:` trocado por `_`, `<id>` tem tudo fora de `[A-Za-z0-9_-]` trocado por
`_` e `<ext>` vem do nome original ou do mimetype.

Mídia antiga do 4143 (`store/<chat>/<filename>`, nome por segundo) só é
aproveitada quando **nenhuma outra** mensagem do mesmo chat tem o mesmo
`filename`. Nesse caso a ponte faz um hard link para o caminho novo e segue
dali. Nome repetido é tratado como não baixado e vai de novo ao servidor.

### `contas.json`

Escrito pela ponte (temporário + `rename`) na subida e a cada mudança de conta
(pareou, deslogou, trocou de nome). Caminhos relativos a `store/`. Editar à
mão só com a ponte parada.

```json
{
  "versao": 1,
  "padrao": "554791744143",
  "contas": [
    {
      "conta": "554791744143",
      "jid": "554791744143:17@s.whatsapp.net",
      "nome": "Luccas Silveira",
      "mensagens": "messages.db",
      "midia": "contas/554791744143/midia"
    },
    {
      "conta": "554792508292",
      "jid": null,
      "nome": "Luccas",
      "mensagens": "contas/554792508292/messages.db",
      "midia": "contas/554792508292/midia"
    }
  ]
}
```

`jid` nulo = conta deslogada (o banco segue legível). `nome` é o push name
do aparelho.

**Como o MCP descobre os bancos:** lê `store/contas.json`. Sem o arquivo
(ponte antiga), usa `store/messages.db` como conta única, que é o
comportamento de hoje. Contato da conta sai de `whatsmeow_contacts` filtrado
por `our_jid = <jid da conta>`.

## Contas e conta padrão

Estados de uma conta (`estado`):

| Estado | Quando |
|---|---|
| `conectando` | subindo ou religando depois de queda de rede |
| `conectada` | `events.Connected` recebido |
| `desconectada` | caiu (`Disconnected`, `KeepAliveTimeout`); a ponte tenta de novo sozinha |
| `deslogada` | `LoggedOut`: o celular removeu o aparelho. O cofre apaga a sessão; só volta com QR |
| `substituida` | `StreamReplaced`: outro processo abriu a mesma sessão (A85). A ponte **não** religa sozinha nesse estado |
| `suspensa` | `TemporaryBan` ou `ConnectFailure` sem nova tentativa; `motivo` traz o texto |

Ação (envio, reação, leitura, mídia ainda não baixada, foto ou grupo fora do
cache) em conta que não está `conectada` responde `409 conta_desconectada`.
Leitura do banco (`/v1/conversas`, `/v1/mensagens`) funciona em qualquer
estado.

## Convenções

- JSON em UTF-8, `Content-Type: application/json`. Chaves em pt-BR.
- Toda resposta JSON de sucesso traz `"ok": true`.
- Tempo é **inteiro em segundos Unix** (`ts`), sempre.
- `conta`: número da conta (ver acima). Em GET vai na query string, em POST no
  corpo. Ausente = conta padrão.
- JID e id de mensagem vão em query string (GET) ou no corpo (POST), nunca no
  caminho. O cliente codifica a query (`@` → `%40` é aceito, cru também).
- Paginação: a resposta traz `antes` (cursor opaco) quando há página mais
  velha, ou `null` quando não há. O cliente devolve o cursor como veio, sem
  interpretar.
- `ref`: texto livre opcional (até 64 caracteres) nas rotas de envio. A ponte
  devolve o `ref` na resposta e no evento `mensagem` que o envio gera. É assim
  que o Knobler casa a bolha "enviando" com a mensagem real, mesmo que o
  evento chegue antes da resposta HTTP.

### Unificação telefone/LID

Conversa individual que existe como `…@s.whatsapp.net` e como `…@lid` aparece
**uma vez** (A62), unida pelo `whatsmeow_lid_map`.

- `jid` da conversa é o **canônico**: o de telefone quando o mapa o conhece,
  senão o LID. Grupo (`@g.us`) é ele mesmo.
- `jids` lista todos os apelidos.
- Toda rota que recebe uma conversa aceita qualquer apelido e responde com o
  canônico. As mensagens são a união dos apelidos.
- Para enviar, a ponte usa o apelido da conversa com a mensagem mais recente.
- Remetente (`remetente`) também sai canônico, com JID completo, sem `:N`.

Ficam de fora das listas e do canal ao vivo (nenhum evento sai deles):
`status@broadcast`, canais (`@newsletter`) e `@broadcast` em geral.

## Objetos

### Conta

```json
{
  "conta": "554791744143",
  "jid": "554791744143:17@s.whatsapp.net",
  "nome": "Luccas Silveira",
  "padrao": true,
  "estado": "conectada",
  "motivo": null,
  "desde": 1762270000,
  "nao_lidas": 12,
  "conversas_nao_lidas": 3
}
```

`desde` = quando entrou no estado atual. `nao_lidas` soma as conversas;
`conversas_nao_lidas` conta as que têm `nao_lidas > 0` ou
`marcada_nao_lida`. É o número do sinal no ícone da seção (A18).

### Conversa

```json
{
  "jid": "5547999990000@s.whatsapp.net",
  "jids": ["5547999990000@s.whatsapp.net", "157192044961796@lid"],
  "tipo": "individual",
  "nome": "Fulano",
  "nao_lidas": 2,
  "marcada_nao_lida": false,
  "ts": 1762270500,
  "ultima": {
    "id": "3EB0A1B2C3D4E5F6",
    "de_mim": false,
    "remetente": "5547999990000@s.whatsapp.net",
    "remetente_nome": "Fulano",
    "tipo": "imagem",
    "previa": "olha isso",
    "ts": 1762270500,
    "segundos": null,
    "apagada": null
  }
}
```

`tipo`: `individual` ou `grupo`. `nome`: no individual, o melhor nome do
contato daquela conta (`full_name`, `first_name`, `push_name`,
`business_name`, nome salvo em `chats`, número, nessa ordem); no grupo, o
assunto. `ts` = hora da última mensagem. `ultima` é `null` se a conversa não
tem mensagem guardada. `previa` é o texto ou a legenda, cortado em 200
caracteres; vazio quando a mídia não tem legenda. `segundos` e `apagada` têm o
mesmo sentido que na [Mensagem](#mensagem): `segundos` é a duração (inteiro)
só em `audio`, `voz` e `video`, `null` nos outros tipos e quando a duração não
é conhecida; `apagada` é o `ts` do "apagar para todos" ou `null`, e quando
preenchida `previa` vem `""`. As duas chaves sempre vêm (com `null`), para a
lista de conversas mostrar "Vídeo · 0:18" e "Mensagem apagada" sem pedir a
mensagem inteira.

### Mensagem

```json
{
  "id": "3EB0A1B2C3D4E5F6",
  "conversa": "120363406741729308@g.us",
  "remetente": "5547999990000@s.whatsapp.net",
  "remetente_nome": "Fulano",
  "de_mim": false,
  "ts": 1762270500,
  "tipo": "imagem",
  "texto": "olha isso",
  "midia": {
    "mimetype": "image/jpeg",
    "nome": "3EB0A1B2C3D4E5F6.jpg",
    "tamanho": 183422,
    "segundos": null,
    "miniatura": true,
    "baixada": false
  },
  "citacao": {"id": "3EB0FFEE", "remetente": "554791744143@s.whatsapp.net", "texto": "e aí?"},
  "reacoes": [{"remetente": "554792508292@s.whatsapp.net", "de_mim": false, "emoji": "❤️", "ts": 1762270510}],
  "editada": null,
  "apagada": null,
  "status": null
}
```

- `tipo`: `texto`, `imagem`, `video`, `audio`, `voz`, `documento` ou
  `figurinha`. Contato (vCard) chega como `texto`, como hoje.
- `texto`: o texto ou a legenda; `""` quando não há.
- `midia`: `null` em `texto`. `segundos` só em áudio, voz e vídeo.
  `miniatura` diz se há miniatura JPEG embutida (ver `GET /v1/midia`).
  `baixada` diz se o arquivo já está no disco da ponte (a próxima leitura não
  vai ao servidor).
- `citacao`: `null` ou a mensagem citada, só com o texto (A80).
- `reacoes`: uma por pessoa; reação removida some da lista.
- `editada`: `ts` da última edição, ou `null`. `apagada`: `ts` do apagamento,
  ou `null`; com apagada, `texto` vem `""` e `midia` vem `null`.
- `status`: só em `de_mim`; `enviada`, `entregue` ou `lida`. Nas recebidas,
  `null`. Em grupo, `entregue` e `lida` querem dizer "pelo menos um
  participante" (ver [Recibos](#recibo)).

### Pareamento

```json
{
  "id": "p-7f3a9c",
  "estado": "qr",
  "qr": "2@AbCdEf…,…,…",
  "qr_expira_em": 1762270620,
  "fim": 1762270720,
  "conta": null,
  "motivo": null
}
```

| `estado` | Significado |
|---|---|
| `iniciando` | aparelho criado, conectando para pedir o primeiro QR |
| `qr` | `qr` traz o texto a desenhar como QR code; troca sozinho em `qr_expira_em` |
| `sucesso` | o celular escaneou; `conta` traz o número pareado |
| `expirado` | os QRs acabaram (cerca de 160 s, A82); para tentar de novo, inicie outro |
| `cancelado` | `DELETE /v1/pareamento` |
| `erro` | `motivo` traz o texto (`err-client-outdated`, `err-scanned-without-multidevice` ou o erro do pareamento) |

`fim` é a estimativa de quando a janela fecha (início + 160 s). `qr` e
`qr_expira_em` só existem em `estado = qr`. O `qr` é o texto cru do
`QRChannelItem.Code`; o Knobler desenha o código (CoreImage), a ponte não
manda imagem.

## Referência das rotas

Todas exigem a chave e passam pela guarda de navegador.

### `GET /v1/ponte`

Identifica a ponte. É a sondagem que o Knobler usa para mostrar a peça na
vitrine e nas Ações rápidas (A24): porta aberta não basta, só vale `200` com
este corpo.

```json
{"ok": true, "servico": "whatsapp-ponte", "contrato": 1, "versao": "a1b2c3d"}
```

`versao` é o commit do binário (`-ldflags`), ou `dev`. Responde mesmo sem
nenhuma conta. Leitura do Knobler:

| Resposta | O Knobler conclui |
|---|---|
| `200` com `servico = whatsapp-ponte` e `contrato = 1` | ponte presente |
| `200` com `contrato` diferente de 1 | ponte incompatível |
| `401` (depois de reler o arquivo) | a chave não confere |
| conexão recusada ou tempo esgotado | ponte fora do ar |
| qualquer outra coisa | não é a ponte (outro serviço na porta) |

### `GET /v1/contas`

```json
{"ok": true, "contas": [ <Conta>, … ]}
```

Ordem: a padrão primeiro, depois por número. Lista também as deslogadas.

### `GET /v1/conversas`

Parâmetros: `conta`, `limite` (padrão 50, máximo 200), `antes` (cursor).

```json
{"ok": true, "conversas": [ <Conversa>, … ], "antes": "…" }
```

Ordem: `ts` decrescente (mais recente primeiro), desempate por `jid`.

### `GET /v1/conversa`

Parâmetros: `conta`, `jid` (qualquer apelido). Uma conversa só, para o
Knobler montar a linha de uma conversa que chegou por evento e não estava no
cache.

```json
{"ok": true, "conversa": <Conversa>}
```

`404 conversa_inexistente` se não há nada guardado com esse JID.

### `GET /v1/mensagens`

Parâmetros: `conta`, `conversa` (qualquer apelido), `limite` (padrão 50,
máximo 200), `antes` (cursor).

```json
{"ok": true, "conversa": "5547999990000@s.whatsapp.net", "mensagens": [ <Mensagem>, … ], "antes": "…"}
```

Sem `antes`, devolve as mais recentes. As mensagens vêm em **ordem
cronológica** (mais antiga primeiro), desempate por `id`, prontas para
desenhar. `antes` aponta a página anterior; `null` quando chegou ao começo do
que a ponte guarda. Conversa sem nada guardado devolve lista vazia, não `404`.

### `GET /v1/midia`

Parâmetros: `conta`, `conversa`, `id`, `miniatura` (`1` para a miniatura).

Resposta `200` com o **arquivo** (não JSON): `Content-Type` = mimetype,
`Content-Length`, `Content-Disposition: inline; filename*=UTF-8''<nome>`. Aceita
`Range` (serve vídeo por partes). Se o arquivo não está no disco, a ponte
baixa do servidor, grava no caminho da conta e serve. O Knobler guarda o que
recebe no cache dele, que pode ser apagado.

Com `miniatura=1`: `200 image/jpeg` com a miniatura embutida na mensagem, sem
ir ao servidor; `404 sem_miniatura` se a mensagem não trouxe.

Erros: `404 mensagem_inexistente`, `404 sem_midia` (mensagem sem mídia ou
apagada), `409 conta_desconectada` (precisa baixar e a conta caiu),
`410 midia_expirada` (o servidor não tem mais o arquivo: o link e o caminho
direto falharam).

### `POST /v1/midia/recuperar`

Pede ao celular que reenvie a mídia expirada (o `/api/mediaretry` de hoje,
A81). O Knobler chama **uma vez** depois de um `410`.

```json
{"conta": "554791744143", "conversa": "…", "id": "3EB0A1B2C3D4E5F6"}
```

Responde `200 {"ok": true}` assim que o pedido sai. O resultado chega depois,
pelo evento [`midia`](#midia). Com `ok: true`, o próximo `GET /v1/midia`
serve o arquivo; com `ok: false`, a bolha mostra "mídia indisponível".

### `GET /v1/foto`

Parâmetros: `conta`, `jid` (contato ou grupo), `tamanho` (`miniatura`,
padrão, ou `cheia`).

`200 image/jpeg` com `ETag: "<id da foto>"`. Com `If-None-Match` igual, `304`.
A ponte guarda a foto em `store/contas/<numero>/fotos/` e pergunta ao
WhatsApp de novo no máximo uma vez a cada 24 h por JID, ou antes disso quando
chega `events.Picture` daquele JID. `404 sem_foto` quando não há foto ou ela
está escondida para a conta (`ErrProfilePictureNotSet`,
`ErrProfilePictureUnauthorized`). O Knobler usa um carregador próprio com a
chave; o `RemoteAvatarLoader` segue recusando loopback (A12).

### `GET /v1/grupo`

Parâmetros: `conta`, `jid` (`…@g.us`).

```json
{
  "ok": true,
  "grupo": {
    "jid": "120363406741729308@g.us",
    "nome": "COISAS",
    "descricao": "",
    "criado": 1575256960,
    "dono": "554792508292@s.whatsapp.net",
    "so_admins_enviam": false,
    "participantes": [
      {"jid": "554791744143@s.whatsapp.net", "telefone": "554791744143", "lid": "11373408956608@lid", "nome": "Luccas Silveira", "admin": true, "superadmin": false, "eu": true}
    ]
  }
}
```

Vem de `GetGroupInfo`, guardado por 10 min e descartado quando chega
`events.GroupInfo` do grupo. `telefone` e `lid` podem ser `null`. `nome` do
participante segue a mesma ordem de nomes da conversa. `404
conversa_inexistente` se a conta não está no grupo.

### `POST /v1/enviar/texto`

```json
{
  "conta": "554791744143",
  "para": "5547999990000@s.whatsapp.net",
  "texto": "chego em 10",
  "citar": "3EB0FFEE",
  "ref": "k-41"
}
```

- `para`: JID (qualquer apelido ou grupo) ou só dígitos (vira
  `@s.whatsapp.net`, como no `/api/send`).
- `texto`: obrigatório, não vazio, até 65 536 caracteres.
- `citar`: opcional, id de mensagem **da mesma conversa**. A ponte busca
  remetente e texto no banco e monta o `ContextInfo` (`StanzaID`,
  `Participant`, `QuotedMessage` só com texto). Id que não está no banco →
  `404 mensagem_inexistente`.

Resposta:

```json
{"ok": true, "ref": "k-41", "mensagem": <Mensagem com status "enviada">}
```

A ponte grava a mensagem no banco da conta e publica o evento `mensagem`
(com o mesmo `ref`). O whatsmeow não devolve como evento o que o próprio
cliente envia, então quem gera o evento é a ponte.

Envio que falha não grava nada e não gera evento: `502 whatsapp_recusou`
(o servidor recusou, ou o upload falhou), `504 whatsapp_sem_resposta`
(passou o prazo de confirmação do `SendMessage`, 75 s). Nada é reenviado
sozinho.

### `POST /v1/enviar/midia`

Foto, vídeo ou documento. O arquivo vai **por caminho local**, como no
`/api/send`: o Knobler grava num temporário dele, chama a rota e pode apagar o
arquivo assim que receber a resposta (a ponte lê tudo antes de responder).

```json
{
  "conta": "554791744143",
  "para": "120363406741729308@g.us",
  "tipo": "documento",
  "arquivo": "/Users/…/Library/Caches/com.zoi.knobler/envio/9F1C.pdf",
  "nome": "proposta.pdf",
  "legenda": "segue",
  "citar": null,
  "ref": "k-42"
}
```

- `tipo`: `imagem` (jpeg, png, webp), `video` (mp4, mov) ou `documento`
  (qualquer arquivo). A ponte confere pela extensão: `imagem` só aceita
  `.jpg`, `.jpeg`, `.png` e `.webp`; `video` só `.mp4` e `.mov`; fora disso,
  `400 campo_invalido`. GIF vai como `documento`. O mimetype sai da extensão
  (`mime.TypeByExtension`, com `application/octet-stream` de reserva).
- `arquivo`: caminho **absoluto** de um arquivo comum, legível pelo usuário.
  Até 100 MiB (`413 arquivo_grande_demais`).
- `nome`: nome mostrado no documento; padrão = nome do arquivo. Ignorado em
  imagem e vídeo.
- `legenda`, `citar`, `ref`: opcionais.

Resposta e erros: iguais aos de `/v1/enviar/texto`.

### `POST /v1/enviar/voz`

Nota de voz. O Knobler grava, codifica em Opus e monta o Ogg ele mesmo
(A71–A74); a ponte não converte nada e não chama ffmpeg.

```json
{
  "conta": "554791744143",
  "para": "5547999990000@s.whatsapp.net",
  "arquivo": "/Users/…/Library/Caches/com.zoi.knobler/envio/voz-7A.ogg",
  "segundos": 12,
  "onda": [3, 8, 20, 41, 55, 60, …, 12],
  "citar": null,
  "ref": "k-43"
}
```

- `arquivo`: Ogg com Opus **mono**. A ponte confere `OggS` e o cabeçalho
  `OpusHead` com 1 canal; fora disso, `400 audio_invalido`.
- `segundos`: inteiro de 1 a 3600, a duração arredondada para cima. A ponte
  usa este valor como `Seconds`.
- `onda`: exatamente **64** inteiros de 0 a 100, a forma de onda real tirada
  do nível do microfone. Vai como `Waveform` no lugar da onda sintética de
  hoje.

Sai como `AudioMessage` com `PTT = true` e
`Mimetype = "audio/ogg; codecs=opus"`. Resposta e erros: iguais aos de
`/v1/enviar/texto`; a mensagem volta com `tipo = "voz"`.

### `POST /v1/reagir`

```json
{"conta": "554791744143", "conversa": "…", "alvo": "3EB0A1B2C3D4E5F6", "emoji": "👍"}
```

`emoji` vazio remove a reação. A ponte pega o remetente do alvo no banco para
montar a chave (`BuildReaction`). Responde `200 {"ok": true}`, grava em
`reactions` e publica o evento `reacao`. `404 mensagem_inexistente` se o alvo
não está no banco.

### `POST /v1/lida`

Marca a conversa como lida. É o **único** jeito de a ponte mandar recibo de
leitura: ela nunca marca sozinha. O Knobler chama no botão e logo depois de
responder naquela conversa (spec, Leitura).

```json
{"conta": "554791744143", "conversa": "…"}
```

A ponte manda `MarkRead` para as últimas `nao_lidas` mensagens recebidas
que tem no banco, uma chamada por remetente nos grupos (A78). Se a
privacidade de leitura da conta estiver desligada, o whatsmeow troca sozinho
para `read-self`. Manda também o `BuildMarkChatAsRead` (lida, com a chave da
última mensagem da conversa), que limpa a contagem e a marca de não lida nos
outros aparelhos mesmo quando a contagem veio da sincronização e a mensagem
não está no banco.
Zera `nao_lidas` e `marcada_nao_lida`, publica o evento `leitura` e responde:

```json
{"ok": true, "marcadas": 3}
```

Conversa já lida responde `marcadas: 0`, sem mandar nada.

### `POST /v1/pareamento`

Inicia o pareamento de uma conta nova (ou de uma deslogada) por QR. Sem corpo.
A ponte cria um aparelho (`container.NewDevice()`), pede o `GetQRChannel`
**antes** do `Connect` e responde:

```json
{"ok": true, "pareamento": <Pareamento>}
```

Um pareamento por vez: com outro em andamento, `409 pareamento_em_andamento`
e o corpo traz o atual em `pareamento`. Cada mudança de estado sai também
pelo evento `pareamento`. Só QR; não há pareamento por código (A82).

No `sucesso`, a conta entra no `contas.json` (número novo ganha banco e
pastas; número conhecido volta ao banco dele) e passa a aparecer em
`/v1/contas`. A ponte mantém **um aparelho por número**: se o número pareado
já tinha um aparelho no cofre, o antigo é deslogado e apagado.

### `GET /v1/pareamento`

`200 {"ok": true, "pareamento": <Pareamento>}` com o atual, ou com o último
terminado há menos de 60 s. Fora disso, `404 sem_pareamento`.

### `DELETE /v1/pareamento`

Cancela: desconecta o cliente do pareamento e descarta o aparelho.
`200 {"ok": true}`; `404 sem_pareamento` se não há nada em andamento.

## Canal ao vivo

`GET /v1/eventos` com upgrade para **WebSocket** (decisão A57/A76; a ponte usa
`github.com/coder/websocket`, que passa a dependência direta).

### Handshake

```
GET /v1/eventos?desde=4182&jornal=6f0c2d1e-… HTTP/1.1
Host: 127.0.0.1:8099
Authorization: Bearer <chave>
Upgrade: websocket
```

- A chave vai no **cabeçalho** `Authorization`, nunca na URL (URL vai para
  log). O `URLSessionWebSocketTask` aceita cabeçalho pelo `URLRequest`.
- Guarda de navegador e chave valem antes do upgrade: `403`/`401` em HTTP
  comum.
- `desde` e `jornal` vêm juntos ou não vêm. Só um dos dois → `400
  campo_invalido`.
- Até 16 conexões ao mesmo tempo; acima disso, `503 ocupada`.

### Fluxo

O canal é **só de ida**: a ponte manda quadros de texto, um evento JSON por
quadro; o que o cliente mandar em texto é ignorado.

1. Primeiro quadro, sempre:

   ```json
   {"tipo": "ola", "contrato": 1, "jornal": "6f0c2d1e-…", "seq_atual": 4190, "seq_minimo": 1022}
   ```

2. Depois, uma de três coisas:
   - **sem `desde`**: ao vivo a partir de `seq_atual`;
   - **`desde` válido**: os eventos guardados com `seq > desde`, em ordem, e
     então ao vivo, sem buraco nem repetição;
   - **`desde` inválido**: um quadro `ressincronize` e então ao vivo a partir
     do `seq_atual` dele.

   ```json
   {"tipo": "ressincronize", "jornal": "6f0c2d1e-…", "seq_atual": 4190}
   ```

`desde` é válido quando `jornal` é o atual **e**
`seq_minimo - 1 <= desde <= seq_atual`. É inválido quando o `jornal` é outro
(o `eventos.db` foi recriado e a contagem voltou), quando `desde` é mais
velho que o que sobrou da retenção, ou quando é maior que `seq_atual`.

Ao receber `ressincronize`, o Knobler descarta o estado das conversas, relê
`/v1/contas`, `/v1/conversas` e a conversa aberta, e guarda o novo `jornal` e
`seq_atual` como último visto.

O cliente guarda `jornal` e o maior `seq` que aplicou, e reconecta com eles.
Evento com `seq` menor ou igual ao último aplicado é ignorado.

### Sinal de vida

- A ponte manda **ping** de WebSocket a cada 20 s e fecha a conexão se o pong
  não vier em 10 s.
- O Knobler manda ping a cada 25 s e reconecta se o pong não vier em 10 s (o
  ritmo do `WebhookClient`, A40/A76). `URLSessionWebSocketTask` responde ao
  ping da ponte sozinho.
- Reconexão do Knobler: espera crescente com jitter e teto de 30 s (A8).

### Fechamento

| Código | Motivo |
|---|---|
| `1001` | a ponte está desligando |
| `1013` | o cliente ficou para trás: mais de 1024 eventos na fila de envio. Reconecte com `desde` |

### Diário em disco

`store/eventos.db`:

```sql
CREATE TABLE IF NOT EXISTS eventos (
  seq       INTEGER PRIMARY KEY AUTOINCREMENT,
  criado_em INTEGER NOT NULL,   -- segundos Unix
  conta     TEXT NOT NULL,
  tipo      TEXT NOT NULL,
  dados     TEXT NOT NULL       -- JSON do campo "dados"
);
CREATE INDEX IF NOT EXISTS idx_eventos_criado ON eventos (criado_em);
CREATE TABLE IF NOT EXISTS meta (chave TEXT PRIMARY KEY, valor TEXT NOT NULL);
-- meta: ('jornal', '<uuid v4>'), gerado quando o arquivo nasce
```

- `AUTOINCREMENT` garante que o `seq` nunca é reaproveitado, nem depois de
  apagar as linhas mais novas, e sobrevive ao religar da ponte (A77).
- **Retenção: 7 dias.** A limpeza roda na subida e de hora em hora e apaga
  `criado_em < agora - 7 dias`. Sete dias cobrem o Mac dormindo um fim de
  semana inteiro com folga.
- `seq_minimo` = menor `seq` na tabela, ou `seq_atual + 1` se ela está vazia.
  `seq_atual` = último `seq` dado (de `sqlite_sequence`), 0 num diário novo.
- O evento é gravado **na mesma transação** da mudança no banco da conta
  quando possível, e sempre antes de ir para os clientes. Evento que não foi
  gravado não é enviado.

### Formato dos eventos

Envelope dos **eventos numerados** (gravados no diário, entram no `desde`):

```json
{"seq": 4191, "tipo": "mensagem", "conta": "554791744143", "ts": 1762270500, "dados": { … }}
```

Envelope dos **eventos de estado** (`conta`, `pareamento`): igual, **sem
`seq`**. Não vão para o diário nem se repetem no `desde`: são estado atual, e
quem reconecta relê `/v1/contas` e `/v1/pareamento`. O QR do pareamento nunca
toca o disco.

`ts` do envelope = quando a ponte gerou o evento. `conta` em `pareamento` é
`""`.

#### `mensagem`

Mensagem nova numa conversa, recebida ou enviada (do celular, de outro
aparelho, do Knobler ou do MCP). Também a que chega quando a ponte reconecta
depois de um tempo fora: o Knobler decide pelo `ts` da mensagem se ainda vale
card.

```json
{"mensagem": <Mensagem>, "conversa": <Conversa>, "ref": "k-41"}
```

`conversa` já vem com `nao_lidas` contando esta mensagem. `ref` só existe
quando a mensagem saiu por uma rota de envio que recebeu `ref`.

A sincronização de histórico **não** gera `mensagem` (seriam milhares); ela
gera um `sincronizacao` no fim de cada lote.

#### `recibo`

```json
{"conversa": "…", "ids": ["3EB0A1B2", "3EB0C3D4"], "recibo": "lida", "de": "5547999990000@s.whatsapp.net", "ts": 1762270600}
```

| `recibo` | Vem de | Efeito na ponte |
|---|---|---|
| `entregue` | recibo de entrega de outra pessoa para mensagem minha | `status` → `entregue` |
| `lida` | `read` ou `played` de outra pessoa para mensagem minha | `status` → `lida` |
| `lida_por_mim` | `read`, `read-self` ou `played-self` vindo **de outro aparelho meu** | recalcula as não lidas da conversa e publica `leitura` |

`status` só anda para a frente (`enviada` → `entregue` → `lida`). Em grupo,
o primeiro recibo de cada tipo já avança o `status` (simplificação
deliberada: a ponte não guarda recibo por participante). A ponte só publica
`recibo` quando ele mudou algo guardado. Recibo de `retry`, `sender`,
`server-error`, `inactive`, `peer_msg` e `hist_sync` não vira evento.

#### `reacao`

```json
{"conversa": "…", "alvo": "3EB0A1B2", "remetente": "…", "de_mim": false, "emoji": "❤️", "ts": 1762270610}
```

`emoji` vazio = reação removida. Vale para reação recebida e para a enviada
por `POST /v1/reagir` ou por outro aparelho.

#### `edicao`

```json
{"conversa": "…", "alvo": "3EB0A1B2", "texto": "texto novo", "ts": 1762270620}
```

Vem de `events.Message` com `IsEdit`. Edição de mensagem que a ponte não
tem é publicada igual; o cliente ignora se não conhece o alvo.

#### `apagamento`

```json
{"conversa": "…", "alvo": "3EB0A1B2", "por": "5547999990000@s.whatsapp.net", "ts": 1762270630}
```

"Apagar para todos" (`ProtocolMessage` do tipo `REVOKE`). "Apagar para mim"
de outro aparelho não vira evento.

#### `leitura`

```json
{"conversa": "…", "nao_lidas": 0, "marcada_nao_lida": false}
```

Publicado quando `nao_lidas` ou `marcada_nao_lida` mudam por qualquer motivo
que não seja mensagem nova (essa já vem no evento `mensagem`): recibo
`lida_por_mim`, `events.MarkChatAsRead` (marcar como lida ou não lida noutro
aparelho), `POST /v1/lida`.

Regra das não lidas, por conversa unificada:

- mensagem recebida que vira linha soma 1;
- `lida_por_mim` → passa a ser o número de recebidas com `ts` maior que a
  mais nova das mensagens do recibo;
- `MarkChatAsRead` lida → 0 e `marcada_nao_lida = false`; não lida →
  `marcada_nao_lida = true`;
- sincronização de histórico → `UnreadCount` e `MarkedAsUnread` da conversa
  substituem os valores (A63);
- `POST /v1/lida` → 0 e `false`.

#### `midia`

```json
{"conversa": "…", "alvo": "3EB0A1B2", "ok": true}
```

Resultado de `POST /v1/midia/recuperar` (ou do `/api/mediaretry`).

#### `sincronizacao`

```json
{"conversas": 37}
```

Um lote da sincronização de histórico foi gravado. O cliente relê
`/v1/conversas` (e a conversa aberta, se estiver no lote).

#### `conta` (estado, sem `seq`)

`dados` = objeto [Conta](#conta) com o estado novo. Sai a cada mudança de
`estado`, de `nome` ou de `nao_lidas` agregado. O Knobler usa para o seletor
de conta.

#### `pareamento` (estado, sem `seq`)

`dados` = objeto [Pareamento](#pareamento), a cada QR novo e a cada mudança de
estado.

## Rotas antigas (`/api/*`)

Continuam com o mesmo método, corpo e resposta de sucesso de hoje, para o MCP
não quebrar. O que muda:

1. **Exigem a chave** e passam pela guarda de navegador (`401`/`403` em JSON
   no formato de [erro](#erros-e-limites)).
2. Aceitam **`conta`** opcional: no corpo JSON nas rotas POST, na query em
   `GET /api/group/info`. Sem `conta`, valem a conta padrão (o 4143).
3. Tudo que mandam mensagem passa a gravar no banco e publicar o evento
   `mensagem`, como as rotas novas.

| Rota | Corpo/parâmetros de hoje | Observação |
|---|---|---|
| `POST /api/send` | `recipient`, `message`, `media_path` | a ponte segue escolhendo o tipo pela extensão; `.ogg` vira nota de voz com a onda sintética de hoje |
| `POST /api/download` | `message_id`, `chat_jid` | `path` passa a apontar para o layout novo (`store/contas/<numero>/midia/…`) |
| `POST /api/history` | `chat_jid`, `before_id`, `count` | sem mudança |
| `POST /api/mediaretry` | `message_id`, `chat_jid` | passa a exigir POST (`405` nos outros métodos); o resultado também sai no evento `midia` |
| `POST /api/group/add` | `group_jid`, `participant` | sem mudança |
| `POST /api/group/create` | `name`, `participants` | sem mudança |
| `GET /api/group/info` | `group_jid` | segue devolvendo o `types.GroupInfo` cru do whatsmeow |

Os erros de validação dessas rotas (texto puro em `400`, `success: false` em
`500`) ficam como estão; só `401`, `403` e `404 conta_inexistente` são novos.

**Ordem de troca sem janela de queda (A59):** primeiro sobe o MCP que manda
`Authorization` quando o arquivo da chave existe (a ponte antiga ignora o
cabeçalho); depois a ponte nova, que cria a chave e passa a exigi-la. O MCP
relê o arquivo no `401`, então pega a chave criada depois que ele subiu.

## Erros e limites

Corpo de erro das rotas `/v1` e dos `401`/`403`/`404 conta_inexistente` das
rotas antigas:

```json
{"ok": false, "erro": "conta_desconectada", "detalhe": "a conta 554792508292 está deslogada"}
```

`erro` é o código estável (o cliente decide por ele); `detalhe` é texto
para log, em pt-BR, e pode mudar.

| HTTP | `erro` | Quando |
|---|---|---|
| `400` | `json_invalido` | corpo não é JSON |
| `400` | `campo_invalido` | campo ausente, vazio, fora do formato ou combinação inválida; `detalhe` diz qual |
| `400` | `audio_invalido` | `/v1/enviar/voz` com arquivo que não é Ogg Opus mono |
| `401` | `nao_autorizado` | sem `Authorization`, formato errado ou chave diferente |
| `403` | `host_nao_permitido`, `origem_nao_permitida`, `outro_site` | guarda de navegador |
| `404` | `rota_inexistente` | caminho desconhecido |
| `404` | `conta_inexistente` | `conta` não está no `contas.json` (ou não há conta nenhuma) |
| `404` | `conversa_inexistente` | `GET /v1/conversa` ou `/v1/grupo` sem dado |
| `404` | `mensagem_inexistente` | `id`, `alvo` ou `citar` fora do banco |
| `404` | `sem_midia`, `sem_miniatura`, `sem_foto`, `sem_pareamento` | ver cada rota |
| `405` | `metodo_nao_permitido` | método errado para a rota |
| `409` | `conta_desconectada` | ação em conta que não está `conectada` |
| `409` | `pareamento_em_andamento` | `POST /v1/pareamento` com outro aberto |
| `410` | `midia_expirada` | o servidor do WhatsApp não tem mais o arquivo |
| `413` | `corpo_grande_demais` | corpo JSON acima de 1 MiB |
| `413` | `arquivo_grande_demais` | `arquivo` acima de 100 MiB |
| `500` | `erro_interno` | falha da ponte (banco, disco) |
| `502` | `whatsapp_recusou` | o WhatsApp recusou o envio ou o upload |
| `503` | `ocupada` | mais de 16 conexões no canal ao vivo |
| `504` | `whatsapp_sem_resposta` | o envio não foi confirmado no prazo (75 s) |

Prazos sugeridos para o cliente: 15 s em leitura, 120 s em envio e em
`GET /v1/midia` (upload e download de arquivo grande). Corpo JSON até 1 MiB;
texto até 65 536 caracteres; arquivo até 100 MiB.

## O que a ponte garante além das rotas

- **Nunca anuncia presença "disponível"** (A79): aparelho vinculado online
  faz o celular parar de notificar. Depois de conectar, manda uma vez
  `SendPresence(unavailable)`, que registra o nome de exibição sem ficar
  online. Também nunca manda "digitando".
- **Nunca marca como lida sozinha.** Recibo de leitura só sai por
  `POST /v1/lida`. O recibo de entrega automático do whatsmeow segue como
  hoje.
- **Um processo só.** Duas pontes com o mesmo cofre derrubam uma à outra
  (A85). Teste de desenvolvimento usa cópia do `store/` noutra porta, com o
  serviço parado se precisar do cofre real.

## O que o MCP muda

- Lê a chave do arquivo e manda `Authorization: Bearer` em toda chamada;
  relê no `401`.
- Lê `store/contas.json` para achar o banco de cada conta; sem o arquivo, usa
  `store/messages.db`.
- Toda ferramenta ganha o parâmetro opcional `conta` (o padrão é o `padrao`
  do manifesto) e passa adiante nas chamadas HTTP.
- `search_contacts` filtra `whatsmeow_contacts` por `our_jid` da conta.
- Segue lendo o SQLite direto e só lendo: nunca grava nos bancos da ponte.

## Fora deste contrato

Apagar ou editar mensagem enviada, encaminhar, presença e "digitando",
pareamento por código, ligação, status, canais, comunidades, criar grupo pelo
Knobler. As rotas de grupo antigas seguem só para o MCP.
