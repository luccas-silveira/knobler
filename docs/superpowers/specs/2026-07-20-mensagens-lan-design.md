# Mensagens LAN entre computadores — design

**Data:** 2026-07-20
**Status:** aprovado, pronto para plano de implementação
**Tipo:** feature (SemVer MINOR)

## Objetivo

Trocar mensagens entre computadores rodando Knobler na mesma rede local.
O usuário abre a aba de mensagens no notch, vê quem está online na rede,
escolhe uma pessoa e manda uma mensagem — que aparece no notch do
destinatário junto com nome e foto de perfil do remetente.

## Decisões de escopo (brainstorming)

- **Modelo:** transporte bidirecional; o remetente marca **por mensagem** se
  aceita resposta. "Recado one-shot" = mensagem com `allowReply=false` (esconde
  o campo de resposta no card de quem recebe). Um sistema só, não dois.
- **Identidade:** config no app — nome de exibição + foto, pré-preenchidos com
  o do macOS mas editáveis.
- **Privacidade:** aberto na LAN (qualquer Knobler na mesma rede te vê e te
  alcança). Risco de rede pública aceito; toggle "invisível" fica como upgrade.
- **Entrada:** aba dentro do notch aberto, ao lado de Música.
- **Histórico:** últimas ~20 mensagens por pessoa, persistidas em disco.
- **Recebimento:** mensagem chegando abre o notch com foto + nome + texto,
  mesmo com o notch fechado (como uma notificação).

## Abordagem escolhida

**Bonjour + socket próprio.** Anuncia `_knobler._tcp` via `NWListener`/
`NWBrowser` (framework `Network`, já usado no projeto). Protocolo minúsculo:
conecta → manda um JSON → fecha. Listener **separado** do servidor
`localhost:4477` — a API de automação (`/notify`, `/ask`, `/mirror`) **não**
fica exposta à rede.

Rejeitadas:
- **Reaproveitar o HTTP server em `0.0.0.0`:** expõe a API de automação à LAN
  inteira. Rebaixamento de segurança.
- **MultipeerConnectivity:** orientado a sessão (convite/aceite antes de
  enviar, sessões caem/reconectam); briga com o modelo fire-and-forget.

## Componentes

### Arquivos novos

| Arquivo | Responsabilidade |
|---|---|
| `Peer.swift` | Modelos: `Peer`, `PeerMessage`, `PeerProfile`. |
| `LANMessaging.swift` | Motor de rede: anuncia+descobre via Bonjour, aceita conexões de entrada, `send(to:)` / `fetchProfile(from:)`. Publica `@Published var peers`. |
| `MessageStore.swift` | Persistência: últimas 20 msgs por peer + cache de fotos + identidade. |
| `MessagesView.swift` | Aba no notch: lista de online → conversa → campo de escrever. |
| `IncomingMessageView.swift` | Card de entrada no notch (foto + nome + texto + resposta rápida). |

### Alterações em arquivos existentes

- `AppSettings.swift` — identidade: `myID`, `displayName`, caminho da foto.
- `NotchViewModel.swift` — novo `mode .message` + estado de aba (`tab`).
- `NotchView.swift` — barra de abas quando aberto + apresentação do card de entrada.
- `KnoblerApp.swift` — instancia o motor, fia recebimento → notch.
- Settings de identidade numa seção própria onde vivem os ajustes do app.
- `project.yml` — linkar `Collaboration.framework`; adicionar Info.plist `NSLocalNetworkUsageDescription` e `NSBonjourServices=["_knobler._tcp"]` (ver Pesquisa).
- `tools/snapshot.sh` — adicionar `MessagesView.swift` e `IncomingMessageView.swift` à lista manual.

## Protocolo

JSON emoldurado sobre TCP. Conexão efêmera: conecta → manda → (lê resposta) → fecha.

- **Moldura:** prefixo de 4 bytes (tamanho do corpo, big-endian) + corpo JSON.
  Teto de 64 KB por moldura; rejeita maior.
- **Descoberta:** cada instância anuncia `_knobler._tcp` com TXT record
  `id=<uuid>` e `name=<displayName>`. O nome vem no TXT → a lista renderiza na
  hora; foto é buscada preguiçosamente via `profile`.
- **Pedidos:**
  - `{"t":"profile"}` → resposta `{"id","name","avatar":<jpeg base64 ~64px | null>}`
  - `{"t":"msg","id":<uuid>,"from":<id>,"fromName":<nome>,"text":<str>,"reply":<bool>}`
    → resposta `{"ok":true}` (ack) e fecha.

## Identidade

UUID estável por instalação, gerado uma única vez e guardado em `UserDefaults`.
Histórico e cache de foto são chaveados por esse `id` (nome pode mudar/colidir;
o `id` não). `displayName` e foto começam preenchidos com os do macOS, editáveis.

## Modelo de dados

- `Peer { id: String, name: String, endpoint: NWEndpoint, online: Bool }`
- `PeerMessage { id: UUID, peerID: String, incoming: Bool, text: String, allowReply: Bool, at: Date }`
- `PeerProfile { id: String, name: String, avatar: Data? }`
- Foto cacheada em `Application Support/Knobler/avatars/<peerID>.jpg`.

## UI no notch

- Notch aberto (`expanded`) ganha barra de abas: **Música | Mensagens**
  (`@Published var tab` no vm). Default segue Música.
- **Aba Mensagens:**
  - Lista de gente **online** (foto + nome). Vazio → "ninguém online na rede".
  - Toca no peer → **conversa**: bolhas das últimas 20 + campo de escrever.
    Antes de enviar, toggle **"permite resposta"** (one-shot vs ida-e-volta, por
    mensagem). Enviar → `LANMessaging.send`.
- **Card de entrada** (`mode .message`, prioridade perto de notificação): chega
  mensagem → notch abre com foto + nome + texto. Se `allowReply`, campo de
  resposta rápida no card (padrão do rodapé do `Ask`). Auto-some como
  notificação; clicar abre a conversa na aba Mensagens.

## Persistência

- `MessageStore`: `messages.json` em App Support = `{ peerID: [até 20 PeerMessage] }`.
  Carrega no launch, salva com debounce. Fotos como arquivos `.jpg`.
- Identidade em `UserDefaults`: `myID`, `displayName`; foto em `me.jpg`.

## Segurança e casos de borda

- Listener aceita conexões da LAN (modo aberto). Teto de 64 KB por moldura,
  rejeita malformado, trunca texto (~2000 chars). Foto decodificada via ImageIO
  — inválida vira placeholder de iniciais. Nenhum caminho de execução a partir
  do payload (só exibição).
- Filtra o próprio usuário da lista (compara `myID` com o `id` do TXT).
- Peer caiu no meio do envio → conexão falha → bolha marcada "não entregue".
- `// ponytail:` sem criptografia (confiança de LAN, escolha "aberto"); upgrade
  = TLS via `NWParameters` se necessário.

## Teste

Self-check `assert`-based do codec + moldura: encoda um `PeerMessage`, emoldura,
desemoldura, decoda, confere igualdade; idem `profile`. É a única lógica
não-trivial (parsing/framing binário).

## Pesquisa (verificado 2026-07-20)

Verificação por compilação/execução real contra o SDK instalado (não memória).

1. **APIs de rede — compilam no alvo macOS 14.2.** `NWListener.Service(name:type:txtRecord:)`,
   `NWTXTRecord`, `NWBrowser(for: .bonjourWithTXTRecord(type:domain:))` com TXT lido
   via `case .bonjour(let txt) = result.metadata`, `NWConnection(to:)` e framing
   length-prefixed com `receive(minimumIncompleteLength:maximumLength:)` — todos type-check limpo.
2. **Nome + foto do macOS — viável (Collaboration.framework).** `CBUserIdentity(posixUID:
   getuid(), authority: .default())` dá `.fullName` (String) e `.image` (NSImage da conta;
   veio 640×640 em runtime). **Mantém o prefill de foto** (antes cogitado dropar). Requer:
   linkar `Collaboration.framework` no `project.yml`; redimensionar para ~64px antes do JPEG
   (imagem cheia = ~152 KB).
3. **Permissão de Rede Local (macOS 15+/26) — NOVO REQUISITO, risco resolvido.** Bonjour
   agora exige consentimento do usuário. Info.plist precisa de `NSLocalNetworkUsageDescription`
   e `NSBonjourServices = ["_knobler._tcp"]` (ambos via `project.yml`; o tipo vale para anunciar
   E descobrir). Fatos que rebaixam o risco (TN3179 + fóruns Apple):
   - O caminho do **framework `Network`** (`NWBrowser`/`NWListener`/`NWConnection`) É o
     suportado e dispara o prompt corretamente. Os relatos de "prompt não aparece" eram de
     **UDP broadcast cru** (BSD sockets) — caminho diferente, não o nosso.
   - Negação é **detectável em código**: `kDNSServiceErr_PolicyDenied (-65570)` chega no
     `stateUpdateHandler` do browser/connection.
   - **Mitigação de app agente (`LSUIElement`):** disparar browse/advertise quando o usuário
     **abre a aba Mensagens** (app ativo = momento certo do prompt), não no launch. Ao ver
     `-65570`, mostrar "libere Rede Local em Ajustes" e expor o estado no `GET /status`.
   - Reset p/ testar: `tccutil reset` não cobre Local Network de forma confiável; testar em
     VM limpa / alternar o toggle em Ajustes › Privacidade › Rede Local.

## Versionamento

Feature → **MINOR**. Escrever em `## [Unreleased]` do `CHANGELOG.md`; publicar
depois com `./tools/release.sh minor`. Não editar `MARKETING_VERSION` à mão.
