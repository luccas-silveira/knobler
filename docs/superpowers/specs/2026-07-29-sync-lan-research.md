# Sync pela LAN — pesquisa

Evidência experimental para as decisões de
[`2026-07-29-sync-lan-design.md`](2026-07-29-sync-lan-design.md). Tudo aqui foi
**rodado nesta máquina** (macOS 26, SDK do Xcode instalado), não deduzido.

## R1 — PSK funciona no Network.framework, mas só em TLS 1.2

Probe: `NWListener` + `NWConnection` em loopback, PSK de 32 bytes nos dois
lados, matriz de configurações de versão/ciphersuite.

| Configuração | Resultado |
|---|---|
| `min = TLSv13` | `-9858: handshake failed` |
| `min = TLSv13` + `AES_128_GCM_SHA256` | `-9858: handshake failed` |
| `min = TLSv13` + `CHACHA20_POLY1305_SHA256` | `-9858: handshake failed` |
| sem `min` | **OK** |
| `min = TLSv12` | **OK** |

Na conexão que fecha, a metadata do TLS reporta:

```
negotiated_tls_protocol_version = 771   # 0x0303 = TLS 1.2
negotiated_tls_ciphersuite      = 0xa8  # TLS_PSK_WITH_AES_128_GCM_SHA256 (RFC 5487)
```

Ou seja: o `sec_protocol_options_add_pre_shared_key` **funciona**, e o stack
escolhe uma ciphersuite PSK que **não está exposta** no enum
`tls_ciphersuite_t` (o header tem zero ocorrências de "PSK" — só RSA, ECDHE e as
três de TLS 1.3). Não há como pedir a suite explicitamente; ela só aparece
quando um PSK está configurado e o teto é 1.2.

Conclusão: **a spec estava errada ao dizer "TLS 1.3 com PSK"**. É TLS 1.2 com
`TLS_PSK_WITH_AES_128_GCM_SHA256`, e o `min`/`max` precisam ser fixados em
`.TLSv12` — deixar sem `min` funciona por acidente (negocia 1.2 de qualquer
forma) e quebraria se um macOS futuro subir o piso.

### Consequência: não há forward secrecy

`TLS_PSK_WITH_AES_128_GCM_SHA256` é PSK puro — a chave de sessão deriva **só** do
PSK, sem troca Diffie-Hellman. Se o PSK vazar depois (Keychain de um Mac
comprometido, chave copiada do painel), **tráfego gravado antes fica decifrável
retroativamente**. TLS 1.3 daria PFS via `psk_dhe_ke`, e as suites `ECDHE_PSK`
dariam em 1.2 — nenhuma das duas está acessível aqui.

Mitigações possíveis, em ordem de custo:
1. Aceitar e documentar. O tráfego é LAN, entre dois Macs do usuário, e o
   atacante precisa ter gravado a sessão **e** obtido o PSK depois.
2. Botão de rotação de PSK (re-pareamento), reduzindo a janela.
3. Handshake ECDH próprio (X25519 via CryptoKit) dentro do canal — protocolo
   criptográfico caseiro. **Recusado**: é exatamente o que PSK existia pra
   evitar.

Recomendado: (1) + (2).

### Rejeição confirmada

| Cliente | Resultado |
|---|---|
| PSK igual, identity igual | conecta |
| PSK diferente | **rejeitado** |
| PSK igual, identity diferente | **rejeitado** |

A autenticação mútua funciona: um host da LAN sem a chave não passa do
handshake. É o que a feature precisa.

### Probe reproduzível

```swift
// swiftc -swift-version 5 probe.swift && ./probe
import Foundation; import Network; import Security; import CryptoKit
let psk = Data(SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) })
func params() -> NWParameters {
    let tls = NWProtocolTLS.Options(); let o = tls.securityProtocolOptions
    let k = psk.withUnsafeBytes { DispatchData(bytes: $0) }
    let i = Data("knobler-sync".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
    sec_protocol_options_add_pre_shared_key(o, k as __DispatchData, i as __DispatchData)
    sec_protocol_options_set_min_tls_protocol_version(o, .TLSv12)
    sec_protocol_options_set_max_tls_protocol_version(o, .TLSv12)
    return NWParameters(tls: tls)
}
// listener com params(), conexão com params() → .ready; metadata revela 771 / 0xa8
```

Detalhe de chamada: a API é C e pede `dispatch_data_t`. Em Swift, monta-se
`DispatchData(bytes:)` dentro de `withUnsafeBytes` e passa-se com
`as __DispatchData`. Compila sem ponte extra.

## R2 — Serviço Bonjour novo exige entrada no Info.plist

`Knobler/Info.plist` declara apenas:

```xml
<key>NSBonjourServices</key>
<array><string>_knobler._tcp</string></array>
```

Um segundo tipo (`_knobler-sync._tcp`) precisa ser acrescentado ali, senão o
browse é barrado pela privacidade de rede local. `NSLocalNetworkUsageDescription`
já existe e cobre os dois.

## R3 — O PSK no Keychain herda o problema de ACL do webhook

Documentado em `docs/webhooks.md` e provado antes nesta base: a ACL do item
pertence a quem gravou, presa ao requisito de assinatura. Se a assinatura do app
mudar (passar a notarizado com Developer ID, por exemplo), o item deixa de
abrir — o `WebhookClient` já trata isso como estado `credentialsLocked`.

Para o sync o efeito é: **o par para de funcionar após troca de assinatura**, nas
duas máquinas ao mesmo tempo. O caminho de recuperação é o mesmo do webhook —
avisar e oferecer re-pareamento — com uma diferença a favor: re-parear sync não
invalida nada público (diferente do `publishToken`, que está colado em serviços
externos). Então aqui o re-pareamento automático é aceitável.

## R4 — `Reminder` não tem marca de modificação

`struct Reminder: Codable, Identifiable` tem `id: UUID` e o `Schedule`, sem
`updatedAt`. Acrescentar como `Date?` opcional deixa o `Codable` já gravado
decodificar (campo ausente → `nil`); o merge trata `nil` como "mais antigo que
qualquer coisa".

## Pendências de pesquisa

- **Não medido**: tempo de reconciliação com histórico cheio (20 mensagens ×
  N peers + mídia). O manifesto é KB, mas cada mídia é um frame de até 6 MB —
  vale medir antes de decidir se a transferência precisa de indicador de
  progresso no card.
- **Não testado**: `NWListener` com dois serviços Bonjour simultâneos no mesmo
  processo (mensagens + sync). Deve funcionar (são dois listeners), mas não
  provei.
