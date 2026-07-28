# 🆕 SESSÃO 2026-07-28 (noite) — P1 e P2 do ditado fechados

As duas pendências que sobraram de 25/07: a causa (duas identidades de
assinatura) e o sintoma (falha silenciosa). Nenhum comportamento novo no notch.

## O que foi feito

**P1 — uma identidade só.** `project.yml` assinava com
`Apple Development: … (J8UFPJ9AZJ)` e o `tools/release.sh` com
`Knobler Local Signing`. Copiar um build por cima do outro em `/Applications`
trocava a identidade, invalidava o `csreq` guardado pelo TCC e matava o ditado em
silêncio. Agora `CODE_SIGN_IDENTITY: "Knobler Local Signing"` no `project.yml`
(e `DEVELOPMENT_TEAM` removido — cert self-signed não tem team). A CI não
precisa do cert: builda com `CODE_SIGNING_ALLOWED=NO`.

**P2 — o aviso saiu do notch e foi pra barra de menus.** Com o ditado ligado e
`AXIsProcessTrusted() == false`, o ícone vira `◐⚠` e o menu ganha
**⚠ Ditado precisa de Acessibilidade…**, que abre o painel do sistema. A pílula
de 2s do launch continua, mas deixou de ser o único sinal. Descartada a pílula
persistente no notch da proposta original: ela cobriria mídia, HUDs e o resto
enquanto a permissão faltasse.

O badge não abriu timer novo — pegou carona no `checkTapHealth`
(`VolumeHUD.swift`), que já sondava a Acessibilidade a cada 3s. Ele ganhou
`onAXTrust`, disparado só na mudança; o `AppDelegate` reavalia o título ali e no
sink de `AppSettings` (o toggle do ditado também muda a condição).

Arquivos: `project.yml`, `Knobler/KnoblerApp.swift`, `Knobler/VolumeHUD.swift`,
`CHANGELOG.md`, `README.md`, `docs/development.md`, `docs/troubleshooting.md`.

## Validação

- `xcodebuild` Debug ✅; `codesign -dvv` do produto imprime
  `Authority=Knobler Local Signing` — o P1 provado no artefato, não no YAML.
- `./tools/check.sh` → 8/8 ✅ (o gate do Codex segue pulado sem `--com-ambiente`).
- **Não verificado**: o badge aparecendo de verdade. Exigiria rodar uma segunda
  instância junto da instalada — mexe em estado global (OSD nativo suprimido,
  prompt de TCC) por um ícone. Fica pro primeiro launch depois de instalar.

## Pendências

- **Publicado**: `f70f427` (assinatura) e `980f478` (badge) em `master`.
- A cópia em `/Applications` ainda está assinada `Apple Development` (instalada
  antes desta unificação): a **próxima** instalação, por qualquer via, derruba a
  Acessibilidade uma vez. Reconceder e seguir — depois dela, nunca mais.
- Segue valendo a pendência da sessão anterior: publicar `0.9.0`
  (`./tools/release.sh minor`) e usar esse release pro teste de aceitação do
  update real (instalar → substituir bundle → relançar), único caminho nunca
  exercitado.
- ~~`CLAUDE.md` afirmava que o `glassEffect`/Liquid Glass estava em uso~~ —
  corrigido nesta sessão (zero ocorrências no código; o target é macOS 14.2).
- `graphify-out/` segue sem regenerar (mudança pequena, não justificava o custo).

---

# SESSÃO 2026-07-28 (tarde) — atualizações no notch + auditoria da documentação

Duas frentes: a feature de update (Tasks 1–6 do plano) e, depois, uma auditoria
de documentação que rendeu licença, CI e arrumação de casa. Tudo mesclado em
`master` e publicado, com a CI verde.

Spec `docs/superpowers/specs/2026-07-28-auto-update-design.md`,
plano `docs/superpowers/plans/2026-07-28-updater.md`.

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

---

# Auditoria da documentação (mesma sessão) — `524a4d5`

Medida, não opinada: varredura de links, imagens, órfãos e freshness em todos os
`.md`. Veredito: a documentação estava **acima da média** (Diátaxis real, template
uniforme por feature, zero imagem órfã), e o que faltava era do repositório.

| Item | Antes | Depois |
|---|---|---|
| Licença | nenhuma, repo público distribuindo binário | `LICENSE` MIT + README + índice |
| CI | inexistente | `.github/workflows/ci.yml` (build Debug + gates) |
| Gates | 8 comandos manuais em comentários | `./tools/check.sh`, exit code validado nos dois sentidos |
| `HANDOFF.md` | 1358 linhas / 27 sessões | 223 linhas + `docs/handoffs/2026-07.md` |
| Specs | 3 soltas na raiz | todas em `docs/superpowers/specs/` |
| `AGENTS.md` | dump do claude-mem | instrução curta e versionada |

**Bug de documentação encontrado:** o comando do `wirecheck` em
`docs/development.md` estava errado — usava `-parse-as-library` num harness
`main.swift`, que tem código top-level. Quem seguisse o doc nunca rodaria o gate.

**Erro meu, registrado:** afirmei que as 3 SPECs da raiz eram órfãs; a primeira
varredura não cobria código nem `docs/superpowers/`. Eram citadas por
`DescansoController.swift` e 3 planos — as 8 referências foram atualizadas junto.

**CI verde na quinta tentativa** — e o caminho até lá rendeu mais que o workflow:

1. Build passou de primeira no runner (o risco de SDK não se materializou).
2. `claude-hook` reprovou por falta de `jq` — existe local via Homebrew, não no
   runner. Agora a CI instala e o `check.sh` confere `jq`/`node` na entrada.
3. O próprio `check.sh` atrapalhava: truncava a saída em 15 linhas e engolia o
   erro. Passou a imprimir tudo e, em gate shell, a re-rodar com `bash -x`.
4. Com o trace, a causa apareceu: o servidor de teste do hook não subia. A espera
   era de 20×0,05s = **1 segundo** — folgada numa máquina quente, apertada num
   runner. Subiu para ~10s, com mensagem quando estoura.
5. Ainda assim falhava. O runner usa o `python3` 3.14 do Homebrew; o teste passou
   a fixar `/usr/bin/python3` (Command Line Tools), com `PYTHON=` como escape.
   **Honestidade:** o mesmo 3.14.6 do brew passa nesta máquina, então a versão
   sozinha não explica — o que resolveu foi parar de depender do `python3` do
   PATH. A causa exata no runner segue desconhecida.

Nada disso era bug do produto: eram dois testes com premissas de ambiente
(ferramenta instalada, máquina rápida) que só a CI expôs.

## Pendências

- **Publicado**: `master` em dia com o `origin`, CI verde, licença MIT
  reconhecida pelo GitHub e descrição do repo preenchida. `footer-check.png`
  apagado.
- **Teste de aceitação do update real**: publicar a próxima release
  (`./tools/release.sh minor` — é feature nova, pré-1.0) e atualizar a partir da
  anterior. É o único jeito de exercitar substituir bundle → relançar.
- **O primeiro update pelo caminho direto troca a identidade de assinatura**
  (Apple Development → `Knobler Local Signing`) e vai derrubar a Acessibilidade
  **uma vez**: reconceder e seguir.
- `CLAUDE.md` diz que o Liquid Glass/`glassEffect` está em uso, mas não há uma
  ocorrência de `glassEffect` nem de `#available(macOS 26` no código.
- `graphify-out/` não foi regenerado (só um arquivo novo de domínio: `Updater.swift`).

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
