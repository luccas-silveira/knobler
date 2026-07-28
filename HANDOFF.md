# 🆕 SESSÃO 2026-07-28 (tarde) — aviso e instalação de atualizações

Branch `feat/updater`. Spec `docs/superpowers/specs/2026-07-28-auto-update-design.md`,
plano `docs/superpowers/plans/2026-07-28-updater.md`, Tasks 1–6 fechadas.

O app não sabia que era velho: atualizar significava lembrar de rodar
`brew upgrade` na mão. Agora ele consulta o GitHub uma vez por dia, avisa e
instala com um clique.

## O que foi feito

| Commit | Entrega |
|---|---|
| `db96975` | `Knobler/Updater.swift` — `Release`, `UpdateState`, `isNewer`, `stripMarkdown`, `parseRelease` + `tools/updatercheck.swift` |
| `1eeb5cf` | classe `Updater` (checagem 24h, launch+30s, `skippedVersion`) e `AppSettings.checkForUpdates` |
| `f13f6ed` | instalação: sonda do brew, caminho brew, caminho direto, relaunch |
| `cd214e4` | Ajustes › Geral + endurecimento da origem/identidade do download |
| `75f6d2f` | card no notch (`Mode.update`, `updateNotchCard`, 2 cenários de snapshot) |
| `a6f8135` | fiação no `AppDelegate`, CHANGELOG, `docs/settings.md`, README |

**Dois instaladores, escolhidos em runtime.** `brew list --cask knobler` responde
→ `brew upgrade --cask knobler` (mantém o Caskroom em dia); não responde → baixa
o `.zip` do release, valida e substitui o bundle com `replaceItemAt`. Sem os dois
caminhos a feature não serviria a quem a pediu: **a máquina do autor não tem o app
instalado via brew** (sem Caskroom, e `codesign -dv` mostra `TeamIdentifier=7UNDW72N73`,
Apple Development — cópia manual de build do Xcode).

O relaunch é um `/bin/sh` destacado que espera o PID morrer e roda `open -a`: o
processo antigo sobrevive à substituição do bundle, então quem reabre tem que ser
externo.

## Decisões que não estavam no plano

- **`ActivityRingView` no lugar de `ProgressView`** no card: o indicador do AppKit
  precisa de `NSView` real e vira o ícone de "proibido" no harness de snapshot.
- **Origem e identidade do download validadas** (achado da revisão de segurança):
  `codesign --verify --strict` prova integridade, não autoria. Agora exige
  `https://github.com/luccas-silveira/knobler/releases/download/…` e
  `CFBundleIdentifier` igual ao atual. A *identidade* de assinatura **não** é
  comparada de propósito — travaria a transição Apple Development → cert local.
- **`canInstall` virou propriedade publicada e cacheada**: era computada e rodava
  `brew list` (~1s) dentro do `body` do SwiftUI, travando a janela a cada redraw.

## Validação

- `updatercheck` (SemVer, strip de markdown, parse) ✅; `snapshot.sh` 51 cenários ✅;
  `xcodebuild` Debug ✅.
- Ao vivo, com `MARKETING_VERSION=0.8.0` forçado: a checagem achou 0.8.4, o card
  desceu sozinho no notch com as notas do release, e com `updateSkippedVersion`
  gravado ele **não** reaparece.
- **Não verificado**: o ciclo instalar → substituir bundle → relançar. Rodando de
  `build/dd`, a guarda `isInApplications` (correta) recusa e mostra "Ver release".
  Provar exige rodar de `/Applications` e substituir o app instalado.

## Pendências

- **Teste de aceitação do update real**: publicar a próxima release
  (`./tools/release.sh minor` — é feature nova) e atualizar a partir da anterior.
- **O primeiro update pelo caminho direto troca a identidade de assinatura**
  (Apple Development → `Knobler Local Signing`) e vai derrubar a Acessibilidade
  **uma vez**: reconceder e seguir. Das próximas não acontece mais.
- `feat/updater` ainda não foi mesclada em `master` nem publicada — a feature está
  em `[Unreleased]`.
- `AGENTS.md` e `footer-check.png` na raiz continuam sem rastreamento (herdado da
  sessão da manhã; ver abaixo).

---

# 🏁 SESSÃO 2026-07-28 — solicitações de agente no notch (plano fechado)

Plano `docs/superpowers/plans/2026-07-25-agent-requests.md` concluído: Tasks 1–8.
As 1–5 já estavam commitadas; esta sessão fechou a 5 e fez 6, 7 e 8.

## O que foi feito

| Commit | Entrega |
|---|---|
| `7e6682e` | contrato do hook `PermissionRequest` documentado; teste cobre timeout e o payload exato |
| `6053dc3` | `tools/codex-agent-bridge.mjs` — proxy stdio ↔ `codex app-server`, os três pedidos de aprovação viram card; `docs/agent-requests.md` |
| `fdc9070` | `tools/codex-integration-check.mjs` — gate de superfícies + seção no troubleshooting |
| `aecf231` | `tools/agent-requests-e2e.mjs` + entrada `Added` no `[Unreleased]` |
| `0c30632` | documentação da sessão de 25/07 que estava órfã (índice, arquitetura, desenvolvimento, contribuição, segurança) |

A ponte é proxy: repassa tudo entre cliente e `app-server` menos
`item/commandExecution|fileChange|permissions/requestApproval`, que viram card.
Ação → decisão: `allow`→`accept`, `allowForSession`→`acceptForSession`,
`deny`→`decline`, `cancel`→`cancel`; em permissões, `allow`/`allowForSession`
devolvem o perfil pedido com `scope` `turn`/`session` e `deny`/`cancel`
devolvem perfil vazio. Emendas de execpolicy e de política de rede **não** viram
botão: são regras persistentes.

## Descoberta que limita o escopo do Codex

`codex-cli 0.145.0` expõe os três pedidos (o gate confirma), mas o **daemon** do
`app-server` — por onde Desktop app e extensão de IDE falariam — exige a
instalação standalone do instalador oficial:

```
Error: managed standalone Codex install not found at ~/.codex/packages/standalone/current/codex
```

Num Codex de Homebrew ele não sobe. Então hoje só espelha a CLI iniciada por
`tools/knobler codex bridge`; TUI já aberto, app e IDE seguem com aprovação
nativa. O gate reimprime esse estado a cada execução.

## Validação

Todos verdes nesta sessão:

- `agentrequestcheck` (reducer), `askcheck` (regressão do Ask, **sem alteração**
  necessária), `agentrequest-api-check` (servidor real: 401/413/400, leitura
  única, publish duplicado em 409).
- `bash tools/claude-hook/test.sh`, `node tools/codex-agent-bridge-check.mjs`,
  `node tools/codex-integration-check.mjs`, `node tools/agent-requests-e2e.mjs`.
- `xcodebuild -configuration Debug … CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED.
- **Não verificado**: turno real do Codex e uso da ponte numa sessão de trabalho
  de verdade. O gate valida handshake, capacidade e fixtures — de propósito não
  gasta tokens da conta. Turno ao vivo é manual:
  `codex --ask-for-approval on-request --sandbox read-only "…"`.

## Pendências

- **Nada foi publicado**: a feature está em `[Unreleased]`. Próximo release é
  **minor** (`./tools/release.sh minor`) — é feature nova, pré-1.0.
- `AGENTS.md` na raiz é um dump do `claude-mem` (128 linhas de
  `<claude-mem-context>`), não documentação. Ficou fora do commit; apagar ou
  reescrever de verdade. `footer-check.png` na raiz também ficou fora.
- P1/P2 do ditado seguem abertos (via única de instalação e pílula persistente
  de Acessibilidade) — ver a sessão de 25/07 abaixo.
- Snapshots dos cards de agente não foram regerados nesta sessão.

---

# 🔧 SESSÃO 2026-07-25 (tarde) — ditado morto de novo: identidade de assinatura

Nenhuma linha de código mudou. O ditado voltou a funcionar reconcedendo
Acessibilidade; o valor da sessão é a causa raiz, que é **diferente** da que o
0.8.4 corrigiu.

## Diagnóstico

`GET /status` do app rodando separou as duas metades na primeira consulta:

```
axTrusted: false   tapExists: false   tapEnabled: false   keyLog: []
dictation: { enabled: true, modelReady: true, recording: false }
```

Ditado sadio, canal de entrada morto. Sem Acessibilidade o `CGEventTap`
(`VolumeHUD.swift:142`) não é criado e o `flagsChanged` da ⌥ direita nunca
chega ao `rightOptionChanged` — falha 100% silenciosa, como o comentário em
`Dictation.swift:274-277` já previa.

## Causa raiz — não é a mesma do 0.8.4

O 0.8.4 trocou o `codesign --sign -` do release por um cert local fixo e o
CHANGELOG deu o assunto por encerrado. Mas a recorrência de hoje aconteceu num
app **0.8.4 já assinado com identidade estável**. A máquina tem duas
identidades válidas:

```
1) Apple Development: luccaspessoal11@gmail.com (J8UFPJ9AZJ)
2) Knobler Local Signing
```

`/Applications/Knobler.app` (instalado 09:27 hoje) está assinado com a **(1)**,
mas `tools/release.sh:119` assina com a **(2)**. Ou seja: a cópia instalada veio
de um `xcodebuild`, não do `release.sh`. A troca de identidade entre instalações
invalida o `csreq` que o TCC guardou — `tccutil reset` respondeu **4 entradas
stale**, e a UI mostrava o app marcado enquanto nada valia.

**O fix do 0.8.4 só segura a permissão se toda instalação passar pelo
`release.sh`.** Misturar as duas vias derruba a Acessibilidade de novo.

## Conserto aplicado (na máquina, não no repo)

```bash
tccutil reset Accessibility com.zoi.knobler   # 4 entradas apagadas
killall Knobler && open -a Knobler            # dispara o prompt do sistema
```

Reconcedido no painel. O `checkTapHealth` (`VolumeHUD.swift:107`) recriou o tap
sozinho, **sem** novo relançamento.

## Validação

- `/status` após conceder: `axTrusted: true`, `tapExists: true`,
  `tapEnabled: true`.
- Hold real da ⌥ direita observado por polling: `recording: true` capturado —
  o evento chega ao controller.
- Ciclo fechou com `recording: false`/`transcribing: false` e **nenhuma** linha
  `knobler ditado:` no log unificado (o `catch` de `Dictation.swift:437` não
  disparou).
- **Não verificado**: se o texto colou no campo e se a transcrição saiu
  correta. O `/status` prova o ciclo, não o conteúdo.

## Documentação atualizada

- `docs/dictation.md` — a permissão de Acessibilidade era descrita como
  necessária só pro ⌘V. Corrigido: ela é necessária **antes**, pro event tap.
  Esse erro é o que fazia o sintoma parecer inexplicável.
- `docs/troubleshooting.md` — seção "Ditado não inicia" reescrita: tabela de
  leitura do `/status`, entrada stale que aparece marcada, procedimento de
  reset, e o `grep Authority` pra conferir a identidade.
- `docs/development.md` — aviso na instalação local sobre a troca de identidade
  entre `xcodebuild` e `release.sh`.
- `CHANGELOG.md` — em `[Unreleased] / Documentation`.

## Pendências

- **P1 — decidir a via única de instalação.** Enquanto `xcodebuild` e
  `release.sh` assinarem com identidades diferentes, isto reaparece. Opções:
  apontar o `project.yml` pra `Knobler Local Signing`, ou tratar
  `ditto` do build Release como não suportado e sempre passar pelo `release.sh`.
- **P2 — falha ainda é silenciosa demais.** O `start()` mostra a pílula "Ditado
  precisa de Acessibilidade" por 2s no launch e ela passa despercebida. Proposta
  não implementada (usuário não decidiu): tornar a pílula persistente enquanto
  `axTrusted == false && dictation.enabled == true`.
- O CHANGELOG do 0.8.4 segue afirmando que o problema foi resolvido "de vez".
  Entrada publicada não se reescreve; a ressalva ficou no `[Unreleased]`.

---

## Sessões anteriores

Handoffs de antes de 26/07/2026 foram arquivados em
[`docs/handoffs/2026-07.md`](docs/handoffs/2026-07.md) — este arquivo guarda só
o estado operacional recente.
