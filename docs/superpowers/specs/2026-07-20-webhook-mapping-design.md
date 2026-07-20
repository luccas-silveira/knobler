# Webhooks configuráveis (mapeamento por perfil) — design

**Data:** 2026-07-20
**Status:** aprovado (grill-me), pronto para plano
**Base:** estende a feature de notificações webhook já no ar (`push.appzoi.com.br`).
**Versão-alvo:** MINOR.

## Objetivo

Deixar qualquer serviço externo (GitHub, Stripe, n8n…) mandar **seu payload nativo**
para o notch. O usuário cria um **perfil** por fonte, manda um webhook de teste, e
**mapeia** os campos da notificação a partir do payload capturado — texto livre
misturado com variáveis do payload.

## Decisões (grill-me)

| Tema | Decisão |
|---|---|
| Onde mapeia | **No relay.** Remetente manda payload nativo; relay aplica o template do perfil e empurra `{title,body,…}` pro Mac (Mac quase não muda). |
| Perfil ↔ link | **1 perfil = 1 link (`/w/<token>`) + 1 mapa.** Device tem N perfis. |
| Captura do teste | Relay **guarda sempre o último payload cru** por perfil. Sem modo especial. |
| Sintaxe do mapa | Interpolação **`{{ dot.path }}`** (aninhado, índice de array), campo faltando → vazio. Sem lógica. |
| UI do mapa | **Lado a lado**: campos da notificação ↔ árvore do payload, **clique-pra-inserir** `{{path}}`, preview ao vivo. |
| Ícone | **Fixo por perfil (URL ou emoji)**, com template `{{}}` opcional que sobrescreve. |
| Compat | **Mapeamento obrigatório.** Sem mapa = **captura-only** (guarda o teste, não entrega). O atalho `{title,body}` direto de hoje **sai**. |
| Migração | O `publishToken` único de hoje vira um **perfil padrão** (sem mapa = captura-only até mapear). |

## Modelo de dados (relay, SQLite)

Device continua `{ device_id, device_secret_h }` (auth do WS). O `publish_token`
migra pra `profiles`:

```sql
CREATE TABLE profiles (
  profile_id      TEXT PRIMARY KEY,   -- opaco
  device_id       TEXT NOT NULL,
  publish_token_h TEXT NOT NULL,      -- SHA-256 (link público)
  name            TEXT NOT NULL,
  mapping         TEXT,               -- JSON de templates; NULL = captura-only
  icon            TEXT,               -- URL https OU emoji (fixo do perfil)
  last_payload    TEXT,               -- último payload cru (JSON, capado ~16KB)
  created_at      INTEGER NOT NULL
);
CREATE INDEX idx_profiles_pub ON profiles(publish_token_h);
CREATE INDEX idx_profiles_dev ON profiles(device_id);
```

`mapping` (JSON): `{ "title": "...{{a.b}}...", "body": "...", "url": "...", "sound": true, "id": "{{deploy.id}}", "iconTemplate": "{{sender.avatar_url}}" }`. `title` obrigatório quando há mapa. `sound` é booleano fixo do perfil. `iconTemplate` opcional sobrescreve `icon`.

## Motor de template (relay, novo módulo)

`render(template: string, payload: object): string` — substitui cada `{{ path }}` por
`get(payload, path)`; `path` é dot-notation com índice de array (`a.b.0.c`); ausente/não-string → string vazia; texto fora das chaves passa literal. Sem escape, sem lógica.
Uma função pura, ~20 linhas + self-check.

## Fluxo do ingress `/w/<publishToken>`

1. Resolve o perfil por `sha256(token)`. 404 se desconhecido.
2. Rate limit por perfil (como hoje, por device→agora por profile).
3. Lê o corpo (JSON; cap 16KB pro payload cru guardado). Grava `last_payload`.
4. Se `mapping` é NULL → **202 `{ok:true, delivered:"captured"}`** (não empurra).
5. Senão: renderiza cada campo, monta `{ type:"notify", title, body, iconURL|null,
   iconEmoji|null, url|null, sound, id|null, ts }`, resolve o ícone (fixo do perfil ou
   `iconTemplate`; URL→`iconURL`, emoji→`iconEmoji`), e entrega (push ou fila offline).

## API de perfis (relay, auth `Authorization: Bearer <deviceSecret>`)

- `POST /profiles {name}` → cria, retorna `{profileId, publishToken}` (token só aqui em claro).
- `GET /profiles` → lista `[{profileId, name, hasMapping, icon}]` (sem token/segredo).
- `GET /profiles/<id>` → `{profileId, name, mapping, icon, lastPayload, link}` (pro editor).
- `PUT /profiles/<id> {name?, mapping?, icon?}` → salva.
- `DELETE /profiles/<id>`.
- `POST /profiles/<id>/rotate` → novo publishToken (link novo), como o rotate de hoje.

## App (Mac)

- **Aba "Notificações externas" vira lista de perfis** + "Adicionar perfil". Cada item:
  nome, status (mapeado/captura-only), link+copiar, "Mapear", rotacionar, excluir.
- **Editor de mapeamento (lado a lado)** — sheet/janela por perfil:
  - Esquerda: campos (Título*, Corpo, URL de clique, Ícone [URL/emoji + toggle "do payload"],
    Som [toggle], ID [dedupe opcional]) — cada um um **`NSViewRepresentable` sobre `NSTextView`**
    (não `TextField`: `TextSelection`/cursor é macOS 15+, alvo é 14.2 — ver pesquisa); um
    `InsertionRouter` compartilhado guarda o último campo focado.
  - Direita: `lastPayload` em **árvore** (`DisclosureGroup` recursivo, **expandida por padrão**,
    tipo+valor por nó); folha usa **`.onTapGesture`** (não `Button` — roubaria o foco) → insere
    `{{ caminho }}` no cursor via o router.
  - **Preview ao vivo**: renderiza o template contra o `lastPayload` (mesmo motor, reimplementado
    em Swift — ~20 linhas — pra não round-trip no relay a cada tecla).
  - "Mandar teste": mostra o link + instrução; ao chegar, o `GET /profiles/<id>` traz o payload novo.
- **`WebhookClient`**: novos métodos pra API de perfis (create/list/get/update/delete/rotate);
  o pareamento passa a criar um perfil padrão no 1º uso (em vez do publishToken solto).
- **Card do notch**: `RemoteAvatarView`/`appIcon` renderiza `iconEmoji` (glifo grande no slot
  32×32) quando presente; senão `iconURL` (path atual); senão fallback. `NotchNotification`
  ganha `iconEmoji: String?`.

## Fora de escopo (v1)

- Upload de imagem local pro ícone (fica URL/emoji).
- Lógica no template (if/loops/filtros).
- Histórico de payloads (só o último).
- Transformar/formatar valores (datas, números).

## Segurança / limites

- `publishToken`/`deviceSecret` 256 bits, hasheados (como hoje). API de perfis por deviceSecret.
- `last_payload` capado (~16KB) — é dado do próprio usuário, guardado no relay.
- Máx perfis por device (ex.: 50) pra não crescer sem teto.
- Rate limit por perfil (o token-bucket de hoje, chaveado por profile_id).
- Template é só interpolação (sem execução) → sem injeção de código; a saída ainda passa
  pela sanitização de título/corpo que já existe.

## Migração

Feature nova (shipada hoje, sem usuários externos reais). O device atual tem 1 `publishToken`
→ vira um perfil "Padrão" (captura-only até mapear). O relay migra na subida
(`devices.publish_token_h` → `profiles`), ou o app recria via `/profiles` no próximo start.
Detalhe fecha no plano.

## Versionamento

MINOR. Escrever em `## [Unreleased]` do CHANGELOG; release no fim.
