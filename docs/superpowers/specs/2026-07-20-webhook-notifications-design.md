# Notificações externas via webhook — design

**Data:** 2026-07-20
**Status:** aprovado (brainstorming), pronto para plano de implementação
**Versão-alvo:** MINOR (pré-1.0)

## Objetivo

Permitir que o Knobler receba notificações vindas **de fora do computador**, disparadas
por qualquer serviço via webhook (GitHub, Zapier, n8n, `curl`, o SaaS do próprio
usuário…). Cada dispositivo tem um **link próprio e estável**; quem dispara um `POST`
nesse link faz aparecer um card no notch com **título, descrição, imagem (avatar) e uma
ação de clique** (abrir uma URL).

Um Mac pessoal fica atrás de NAT e não recebe conexão de entrada da internet. A solução
é um **relay** na VPS do usuário: ele hospeda o link público, recebe o webhook e
**empurra** a notificação para o app pelo WebSocket que o Mac mantém aberto.

## Não-objetivos (milestones futuros, explícito)

- Contas/login, dashboard web, cobrança.
- Imagem grande de conteúdo (hero) dentro do card — v1 é só avatar/ícone.
- Allowlist de esquemas de app no clique (v1 abre só `http`/`https`).
- HMAC/assinatura do payload.
- APNs / entrega com o app fechado (o agente vive ligado enquanto o Mac está acordado).
- Sincronização multi-Mac / link que sobrevive a reinstalar (consequência de "token por
  dispositivo, sem contas" — aceito na v1).

## Decisões travadas (do brainstorming)

| Tema | Decisão |
|---|---|
| Transporte | Relay próprio na VPS do usuário (não Cloudflare, não túnel). |
| Identidade | **Token por dispositivo, sem contas.** Pareamento automático no 1º uso. |
| Conexão | **WebSocket aberto pelo Mac** (disca ele → NAT ok), heartbeat + reconnect. |
| Offline | Relay **enfileira** (máx **50 msgs / TTL 24h** por device); drena no reconnect. |
| Imagem | **Avatar/ícone** no slot esquerdo do card. **O Mac baixa direto** a URL (opção A) com guardas. Toggle "carregar imagens remotas". |
| Clique (`url`) | **Só `http`/`https`**, abre na hora. `file://` e outros esquemas: nunca. |
| Segurança | **256 bits** (32 bytes base62/base64url), storage **hasheado**; `deviceSecret` (WS) separado do `publishToken` (URL); rate limit **20/min burst 5 → 429** (na app, em memória); botão rotacionar (morte imediata); TLS/WSS; sem HMAC; token nunca em log (truncar). |
| Config | **Aba nova "Notificações externas"** no Ajustes. |
| Código do relay | Mora **no próprio repo**, em `relay/`. Deploy por **pm2** na VPS. |

## Arquitetura

```
  Remetente          VPS (147.79.87.179)                      Mac
 (GitHub, Zapier,   ┌─────────────────────────────┐      ┌──────────────────┐
  n8n, curl…)       │ nginx (TLS/certbot)          │      │ Knobler (agente) │
       │            │   push.appzoi.com.br         │      │                  │
       │  POST /w/  │        │                     │      │  WebhookClient   │
       └───────────▶│   node relay (pm2) :<porta>  │◀────▶│  (WSS, disca ele)│
                    │   ├─ ingress webhook         │ push │        │         │
                    │   ├─ WS hub (1 conn/device)  │      │        ▼         │
                    │   ├─ fila offline (SQLite)    │      │  NotchViewModel  │
                    │   └─ /register /rotate        │      │  → card no notch │
                    └─────────────────────────────┘      └──────────────────┘
```

Ambiente da VPS (levantado por recon): Ubuntu 24.04, nginx 1.24 (vhost por domínio,
`proxy_pass http://127.0.0.1:PORT`, TLS por certbot 2.9), Node 18.19 + pm2 6, Postgres
disponível mas **não usado** (relay usa SQLite auto-contido). Máquina é **produção
compartilhada e cheia** — o relay não pode perturbar nada: porta livre, vhost novo,
processo pm2 isolado.

---

## Peça 1 — Relay (novo, `relay/`, Node 18 + pm2)

### Stack
- Node 18 + `ws` (WebSocket, JS puro) + `http` nativo (ou micro-router) + **SQLite via
  `better-sqlite3@11`** (pin: v12+ dropa Node 18) para o estado (devices + fila). WAL mode
  + prepared statements. Sem Docker. pm2 **fork mode** + graceful shutdown (SIGINT/SIGTERM).
- Escuta em `127.0.0.1:<porta livre>` (confirmar porta no deploy). nginx faz proxy com
  os headers de **WS upgrade** (`Upgrade`/`Connection` — o vhost de exemplo da casa não
  os tem; o vhost novo precisa deles). certbot emite cert para `push.appzoi.com.br`.

### Modelo de dados (SQLite)
```sql
CREATE TABLE devices (
  device_id        TEXT PRIMARY KEY,     -- uuid público
  device_secret_h  TEXT NOT NULL,        -- SHA-256 do deviceSecret (auth do WS)
  publish_token_h  TEXT NOT NULL,        -- SHA-256 do publishToken (URL pública)
  created_at       INTEGER NOT NULL,
  last_seen_at     INTEGER
);
CREATE INDEX idx_devices_pubtoken ON devices(publish_token_h);

CREATE TABLE queued (                    -- fila offline por device
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id   TEXT NOT NULL,
  payload     TEXT NOT NULL,             -- JSON já normalizado
  dedupe_id   TEXT,                      -- do campo "id" do webhook (replace)
  created_at  INTEGER NOT NULL
);
CREATE INDEX idx_queued_device ON queued(device_id);
```
Poda periódica: remove `queued` com `created_at` < agora−24h e mantém no máx 50 por
device (descarta os mais antigos). `device_secret` e `publish_token` **nunca** são
gravados em claro — só o hash; comparação por hash na autenticação.

### Endpoints HTTP
| Método/rota | Auth | Função |
|---|---|---|
| `POST /register` | nenhuma | Cria device. Gera `deviceId` (uuid), `deviceSecret` (256 bits), `publishToken` (256 bits, base64url). Grava hashes. Responde `{deviceId, deviceSecret, publishToken}` **uma vez** (só aqui trafega em claro). |
| `POST /rotate` | `deviceSecret` (header `Authorization: Bearer`) | Gera novo `publishToken`, atualiza o hash, responde o novo em claro. O antigo deixa de resolver. |
| `GET /ws` (upgrade) | `deviceSecret` via **header `Authorization: Bearer`** (não query — evita vazar no access log do nginx) | Abre a conexão viva. Registra `device_id → socket` no hub; fecha conexão antiga do mesmo device. Ao conectar, **drena a fila** daquele device e a esvazia. Heartbeat ping/pong ~30s (`isAlive`/`terminate`); socket morto → remove do hub. |
| `POST /w/<publishToken>` | o token na URL | **Ingress do webhook.** Resolve o device pelo hash do token; valida + sanitiza + rate limit; device online → push imediato; offline → enfileira. |
| `GET /health` | nenhuma | Diagnóstico simples (200 + contadores). |

### Ingress `/w/<publishToken>` — detalhe
- Aceita **três formas** de entrada (todas viram o mesmo objeto normalizado):
  1. `application/json` (canônico)
  2. `application/x-www-form-urlencoded` (`curl -d "title=Oi&body=..."`)
  3. query string (`/w/<token>?title=Oi&body=...`)
- Campos → ver **Contrato do payload** abaixo.
- **Sanitização:** `title`/`body` têm caracteres de controle removidos e são truncados
  (ex.: title ≤ 200, body ≤ 1000 chars). `icon`/`url` validados como URL `https`/`http`.
- **Rate limit:** token bucket por device — **20/min, burst 5** — **na app Node, em memória**
  (o token está no path, não em header; sem Redis). Um limite grosso por IP no nginx como
  defesa em profundidade (opcional). Estouro → `429` com `Retry-After`.
- **Resposta:** `202 Accepted` `{ok:true, delivered:"push"|"queued"}` no sucesso;
  `400` payload inválido; `404` token desconhecido; `429` rate limit.

### Contrato do payload (API pública, o que o usuário documenta)
```
POST https://push.appzoi.com.br/w/<publishToken>
Content-Type: application/json

{
  "title": "Deploy finalizado",        // OBRIGATÓRIO (≤200)
  "body":  "zoi-studio em produção",   // opcional (≤1000)
  "icon":  "https://.../logo.png",     // opcional (avatar; Mac baixa; https)
  "url":   "https://.../deploy/123",   // opcional (clique; http/https)
  "sound": true,                       // opcional (default false)
  "id":    "deploy-123"                // opcional (mesmo id substitui em vez de empilhar)
}
```
Mensagem normalizada empurrada pelo WS ao Mac:
```json
{ "type":"notify", "title":"…", "body":"…", "iconURL":"…|null",
  "url":"…|null", "sound":false, "id":"…|null", "ts": 1721500000 }
```

---

## Peça 2 — Cliente no Mac (`WebhookClient.swift`, novo)

- **Pareamento (1º uso com a feature ligada):** se não há credenciais no Keychain, faz
  `POST /register`, guarda `deviceSecret` + `publishToken` + `deviceId` no **Keychain**
  (padrão do `DeepgramKeyStore`), e expõe o link (`https://push.appzoi.com.br/w/<publishToken>`).
- **Conexão:** `URLSessionWebSocketTask` para `wss://push.appzoi.com.br/ws`, com
  `deviceSecret` no **header `Authorization: Bearer`**. Mantém aberto; **reconnect com backoff
  exponencial + jitter** (teto ~30s) em queda/erro. Como o erro nativo de queda demora
  60s–3min (bug documentado da Apple DTS), a detecção rápida vem de: **pong-timeout de
  aplicação (~10s)** + `NWPathMonitor` (rede caiu/voltou) + `NSWorkspace.didWakeNotification`
  (acordou). Idempotência por **epoch token** (mata reconnect duplicado e o double-call do
  pong que dá crash); tudo numa serial queue. `maximumMessageSize` explícito (1 MiB).
  **App Nap:** segurar `ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)`
  enquanto conectado (senão o timer de ping estica e o socket morre por idle).
  Instância única pela vida do app (`URLSession` retém o delegate → evitar recriar a cada
  toggle; `shutdown()` no encerramento). **Plano B** se ficar frágil: migrar o transporte
  pra `NWConnection`/`NWProtocolWebSocket`. (Ver R3 na pesquisa: classe `WebhookClient` pronta.)
- **Recebe** mensagem `type:"notify"` → mapeia para `NotchNotification` → chama
  `viewModel.enqueue(...)` em todos os notches (reusa fila/dedupe/auto-dismiss).
  `sound:true` → toca um som (padrão do Ask). `id` → substitui card existente com mesmo id.
- **Rotacionar:** a aba de config chama `POST /rotate` (auth `deviceSecret`), grava o novo
  `publishToken` no Keychain e atualiza o link exibido. O WS **não cai** (usa `deviceSecret`).
- **Status de conexão:** publica um `@Published` (conectado/desconectado) para o indicador
  verde/cinza da aba.
- **Ciclo de vida:** só conecta se `AppSettings.shared.webhookNotifications` estiver on;
  desligar fecha o WS. Ligado por padrão? **Não** — opt-in (coerente com features novas).

---

## Peça 3 — Render no notch (edições em código existente)

- **`NotchNotification`** (em `NotificationInterceptor.swift`): novo campo
  `var iconURL: String? = nil`. Já tem `openURL`, `id` (via `UUID`), etc. Adotar o `id`
  do webhook para dedupe/replace: mapear para uma chave de replace na fila do
  `NotchViewModel` (ver abaixo).
- **`notificationCard`** (`NotchView.swift`): o slot de ícone à esquerda (`appIcon(for:)`)
  passa a, quando houver `iconURL` e o toggle de imagens remotas estiver on, carregar a
  imagem remota **de forma assíncrona** com **guardas**: só `https`, checa `Content-Type`
  de imagem, teto de tamanho (ex.: 512 KB), timeout curto (ex.: 5s), cache em memória (e
  opcional em disco por hash). Falha/desligado → fallback para um SF Symbol (sino).
- **Clique** (`openSourceApp`): antes de `NSWorkspace.shared.open(url)`, **filtrar o
  esquema** — abrir apenas se `url.scheme` ∈ {`http`, `https`}. Caso contrário, ignora.
  (Isso protege tanto o webhook quanto endurece o caminho existente.)
- **Replace por `id`** (`NotchViewModel`): `enqueue` ganha suporte a substituir uma
  notificação ativa/enfileirada com mesmo `id` de webhook em vez de empilhar (para o caso
  "build 40%→80%→pronto"). Notificações sem `id` seguem o comportamento atual.

---

## Peça 4 — Config (aba nova "Notificações externas")

Nova aba no `TabView` do `SettingsView` (junto de Geral/Lembretes/Descanso), ícone
`bell.and.waves.left.and.right` (ou similar). Conteúdo (Form/grouped, padrão da casa):

- **Toggle master** "Receber notificações externas" (`webhookNotifications`).
- **Indicador de conexão** — bolinha verde ("conectado") / cinza ("offline") a partir do
  `@Published` do `WebhookClient`.
- **O link** — campo read-only (`textSelection(.enabled)`) com o
  `https://push.appzoi.com.br/w/<publishToken>` + botão **Copiar**.
- Botão **Rotacionar link** (com confirmação — quebra webhooks antigos).
- Toggle **"Carregar imagens remotas"** (`loadRemoteImages`, default on) — corta o fetch
  do avatar (some o vazamento de IP).
- Rodapé com exemplo `curl` de conveniência.

### AppSettings (novas chaves, UserDefaults)
- `webhookNotifications: Bool` (default false)
- `loadRemoteImages: Bool` (default true)
- (segredos `deviceSecret`/`publishToken`/`deviceId` → **Keychain**, não UserDefaults)

---

## Segurança (resumo)

- `publishToken` e `deviceSecret` = **256 bits** aleatórios; VPS guarda **só SHA-256**; token
  nunca aparece em log (truncar tipo `aBcD…90_-`).
- Dois segredos separados: rotacionar o link (público) **não** derruba o WS nem re-pareia.
- Rate limit por device no relay; sanitização de título/corpo; validação de URL de
  imagem e de clique; clique só `http`/`https`.
- Todo tráfego sob TLS (nginx/certbot) e WSS.
- Toggle para desligar fetch de imagem remota (privacidade de IP).
- Fora de escopo v1 (aceito): HMAC de payload; quem tiver o link consegue notificar
  (o link **é** o segredo, modelo ntfy/Pushover).

## Tratamento de erros

- Relay indisponível / WS cai → app reconecta com backoff; UI mostra "offline"; nenhum
  crash. Webhooks disparados nesse intervalo caem na fila (até 50/24h) e chegam no
  reconnect; além do teto, são descartados (silencioso — documentado).
- `/register` falha no 1º uso → app tenta de novo com backoff; feature fica "conectando".
- Imagem remota falha/timeout/tipo errado → fallback para ícone padrão, sem travar o card.
- Payload inválido → relay responde 4xx ao remetente; nada chega ao notch.

## Estratégia de teste

- **Relay:** testes de unidade dos handlers (register/rotate/ingress/normalização/rate
  limit/fila). Teste E2E local com `wscat` (simula o Mac) + `curl` (simula o webhook):
  registrar → abrir WS → `POST /w/<token>` → ver a mensagem chegar; testar offline
  (fecha WS, dispara, reabre, drena) e replace por `id`.
- **App:** o loop de snapshot (`tools/snapshot.sh`) para o card com avatar remoto e
  fallback. Teste manual do fluxo real após deploy: copiar link, `curl`, ver no notch,
  clicar → abre no navegador. **Lembrar de adicionar `WebhookClient.swift` à lista manual
  do `tools/snapshot.sh`** se a `NotchView` passar a depender dele.

## Deploy (VPS)

1. `relay/` → `git pull` na VPS (ou rsync), `npm ci`.
2. `pm2 start relay/index.js --name knobler-relay` + `pm2 save`.
3. vhost nginx novo `push.appzoi.com.br` → `proxy_pass` pra porta do relay **com headers
   de WS upgrade**. `certbot --nginx -d push.appzoi.com.br`. `nginx -t && reload`.
4. DNS: `push.appzoi.com.br` → 147.79.87.179 (A record) antes do certbot.
5. Fumaça: `curl https://push.appzoi.com.br/health`.

## Ordem de construção

1. **Relay + deploy + testes** (`curl`/`wscat`) — backend primeiro, para o app já ter
   contra o que testar.
2. **`WebhookClient.swift`** (register, WSS, reconnect, Keychain).
3. **Render no notch** (`iconURL`, fetch com guardas, filtro de esquema, replace por `id`).
4. **Aba de config** + chaves no `AppSettings`.

## Versionamento

Feature pré-1.0 → **MINOR**. Escrever em `## [Unreleased]` do `CHANGELOG.md` conforme
desenvolve; publicar com `./tools/release.sh minor` ao final.
