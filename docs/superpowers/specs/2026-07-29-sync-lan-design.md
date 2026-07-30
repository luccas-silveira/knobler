# Sync entre máquinas pela LAN — design

Sincronizar lembretes, Ajustes e histórico de mensagens (com mídia) entre os
Macs do mesmo usuário, pela rede local, sem servidor central.

Decidido em 2026-07-29 numa sessão de grilling. Ainda **não implementado**.

## Por que não é o item do backlog como estava escrito

O `IDEIAS.md` pedia "via endpoint central". Isso põe Ajustes, lembretes e
conversas em claro num host remoto — hoje o relay só guarda notificação em
trânsito por 24 h. Pela LAN o dado não sai da rede local e os dois Macs já se
descobrem por Bonjour.

## O bloqueio que vem antes da feature

`LANMessaging.serve()` **não autentica nada**. Qualquer host da LAN abre conexão
e manda `.message`; as defesas são só UUID canônico no `from` (contra path
traversal no cache de fotos), teto de 2000 caracteres e validação dos bytes do
anexo. Para mensagem isso passa — o pior caso é um card de spam que você vê.
Para sync não passa: numa rede compartilhada qualquer máquina sobrescreveria
lembretes e Ajustes, e poderia pedir o histórico.

Logo o primeiro passo do trabalho é **autenticação de peer**, não o sync.

## Decisões

### 1. TLS 1.2 com PSK de 256 bits, na camada de transporte

`sec_protocol_options_add_pre_shared_key(options, psk, psk_identity)` —
verificado no SDK: `API_AVAILABLE(macos(10.14))`, não depreciada, muito abaixo
do alvo 14.2. Configurada via `NWParameters`.

⚠️ **TLS 1.2, não 1.3** — provado por experimento
([pesquisa R1](2026-07-29-sync-lan-research.md)): com `min = TLSv13` o handshake
falha (`-9858`) em todas as variações de ciphersuite. Funciona com
`min = max = .TLSv12`, negociando `TLS_PSK_WITH_AES_128_GCM_SHA256` (0x00A8) —
suite que o enum `tls_ciphersuite_t` do Swift nem expõe. PSK errado e identity
errada são rejeitados no handshake, então a autenticação mútua vale.

**Sem forward secrecy**: PSK puro deriva a chave de sessão só do segredo, sem
Diffie-Hellman. PSK vazado depois torna tráfego gravado antes decifrável. TLS 1.3
(`psk_dhe_ke`) ou suites `ECDHE_PSK` resolveriam; nenhuma das duas é acessível
aqui. Aceito, com botão de rotação de chave pra encurtar a janela — a alternativa
seria handshake ECDH caseiro, que é o que PSK existe pra evitar.

A chave **é** o segredo, inteiro: 32 bytes de `SymmetricKey(size: .bits256)`,
exibidos em base32 pra transferir uma vez (clipboard/AirDrop/digitação), e
guardados no Keychain no desenho do `WebhookKeychainStore` — herdando o problema
de ACL dele: troca de assinatura do app trava o item nas duas máquinas e exige
re-pareamento ([pesquisa R3](2026-07-29-sync-lan-research.md)). Diferente do
`publishToken`, re-parear sync não invalida nada público, então pode ser
automático.

**Não** usar código curto de 6 dígitos como PSK: um handshake capturado vira
dicionário offline em segundos. O que tornaria código curto seguro é um PAKE
(SPAKE2+/OPAQUE); o CryptoKit não tem PAKE e escrever um à mão é criptografia
caseira num canal que carrega o histórico — recusado de propósito.

Descartado antes: **TOFU com certificado por dispositivo** (modelo do SSH e do
Syncthing, superior a PSK). Não há API pública no macOS pra gerar X.509
auto-assinado — `SecCertificateCreateWithData` exige DER pronto e
`SecIdentityCreate` exige cert + chave. Sairia escrevendo ASN.1 à mão.

Consequência boa: autenticação e sigilo ficam no transporte, então **o `Packet`
das mensagens não é tocado** e nenhum `case` futuro carrega nonce nem MAC.

### 2. Serviço Bonjour separado

O de mensagens fica como está; o sync anuncia tipo próprio
(`_knobler-sync._tcp`), com TLS-PSK obrigatório, e só fala com o par pareado.
O tipo novo **precisa** entrar em `NSBonjourServices` no `Info.plist`, senão o
browse é barrado ([pesquisa R2](2026-07-29-sync-lan-research.md)).

Migrar tudo pra TLS obrigaria pareamento pra mandar um recado ao Mac do lado —
regressão de produto numa feature publicada, em troca de proteger contra spam de
card. O canal novo nasce fechado; o antigo não muda.

### 3. `SyncPacket` separado, `Frame` genérico

O `Packet` é protocolo publicado: roda em máquina de terceiro, e o `init(from:)`
dele **derruba a conexão** em tipo desconhecido (`default: conn.cancel()` no
`serve`) — um Mac velho recebendo `case sync` não degrada, cai. O `SyncPacket`
só fala com o par pareado, que atualiza junto, então pode mudar de formato.

`Frame` (4 bytes big-endian + corpo, coberto pelo `wirecheck`) passa a aceitar
qualquer `Codable` em vez de só `Packet` — reuso, não framing novo.

Campo `v` inteiro no `SyncPacket`; versão desconhecida é recusada com log.

### 4. LWW-Element-Set com relógio híbrido (HLC)

Cada lembrete, mensagem e chave de Ajuste sincronizada ganha marca de
modificação; na chegada vence a maior; exclusão deixa **tombstone** que também
viaja.

O tombstone não é refinamento: sem ele, apagar um lembrete numa máquina faz ele
ressuscitar da outra no próximo sync, para sempre.

O relógio é HLC — `(tempo de parede, contador, id do nó)` — e não `Date()` cru.
Relógio de parede de duas máquinas divergem; a que está adiantada ganharia toda
disputa, inclusive contra uma edição feita depois na outra, e uma edição sua
desapareceria sem log. O `id` desempata de forma determinística, então as duas
pontas convergem pro **mesmo** vencedor. ~30 linhas, função pura.

`Reminder` hoje **não tem** marca de modificação (só `id: UUID` + `Schedule`) —
entra como campo opcional com default, migrando o `Codable` já gravado.

### 5. Escopo: os três tipos de dado

- **Lembretes** — já `Codable`, o caso mais útil e mais bem-comportado.
- **Ajustes** — com **allowlist explícita de chaves**, nunca "tudo o que está no
  `UserDefaults`". Ficam de fora, no mínimo: `mirrorDeviceID` (ID de câmera é
  por máquina), `formatEndpoint` (pode apontar pra localhost) e o pareamento do
  webhook (mora no Keychain, com ACL presa à assinatura). Sincronizar esses
  cegamente estraga a outra máquina.
- **Histórico de mensagens** — o texto é pequeno: `maxPerPeer = 20` e 2000
  caracteres por mensagem, uns poucos KB, cabe num frame só.

### 6. Mídia viaja, em duas fases, sem chunking

Um anexo é ≤ 6 MB (`Frame.maxMedia`) e o frame aceita 12 MB, então **cada mídia
cabe inteira num frame**. O conjunto não cabe — logo: um frame de manifesto
(texto + quais mídias existem) e depois um frame por mídia faltante.

Isso dá retomada de graça (o que já chegou não é pedido de novo) sem escrever
protocolo de chunk.

### 7. Quando sincroniza

Reconciliação completa ao descobrir o par no Bonjour, mais push incremental com
debounce em cada mudança — o mesmo padrão de `saveWork`/`DispatchWorkItem` que
`MessageStore` e `NotificationHistory` já usam.

## Gate

`tools/synccheck.swift`, entrada nova no `tools/check.sh`: HLC e o merge do
LWW-Element-Set são funções puras, testáveis sem rede — ordem de vencedor,
convergência das duas pontas, tombstone que não ressuscita, empate resolvido
pelo id do nó.

## O que a UI precisa

Painel de pareamento nos Ajustes (novo caso em `SettingsPane`): gerar/exibir a
chave em base32, campo pra colar a do outro Mac, estado do par (pareado /
visto agora / offline).
