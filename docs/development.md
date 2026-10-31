# Desenvolvimento

## Pré-requisitos

- macOS com Xcode capaz de compilar o target macOS 14.2.
- XcodeGen (`brew install xcodegen`).
- Swift/Xcode Command Line Tools.
- `curl`, `jq` e Python 3 para os utilitários locais.
- Node.js 18–20 para o relay (`relay/package.json`).

FluidAudio é resolvido como pacote Swift pelo Xcode. O primeiro build pode
baixar dependências e compilar o framework de áudio.

## Build do app

O `.xcodeproj` é gerado. Nunca edite esse arquivo manualmente; altere
`project.yml` e rode:

```bash
./tools/make-signing-cert.sh      # uma vez por máquina, antes do primeiro build
xcodegen generate
xcodebuild -project Knobler.xcodeproj -scheme Knobler \
  -configuration Debug build
```

O `project.yml` assina com `Knobler Local Signing` — a **mesma** identidade que
o `tools/release.sh` usa, para que o TCC não invalide a Acessibilidade quando um
build local substitui uma instalação de release (veja
[Instalação local do build](#instalação-local-do-build)). Sem o certificado o
build falha na assinatura; para só compilar (é o que a CI faz), acrescente
`CODE_SIGNING_ALLOWED=NO`.

Para um build Release isolado:

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler \
  -configuration Release -derivedDataPath /tmp/knobler-dd build
```

O app produzido fica em
`/tmp/knobler-dd/Build/Products/Release/Knobler.app`.

## Checks

Um comando roda todos os self-checks — é exatamente o que a CI executa:

```bash
./tools/check.sh                  # gates herméticos (o que a CI roda)
./tools/check.sh --com-ambiente   # + gate do Codex (exige a CLI) e o instancia-e2e (sessão gráfica)
```

São 25 gates hoje — a lista viva está no próprio `tools/check.sh`, que é a fonte
canônica (uma cópia aqui só envelheceria). Sai com código 1 se qualquer um
falhar. Ao adicionar um self-check novo, inclua-o no script, senão a CI não o vê.

Um deles não é hermético no sentido usual: o `avisoscheck` também valida o
`avisos.json` publicado neste repo (schema, ids únicos, faixa de versão, ações
só em https). É de propósito — publicar um aviso é irreversível, e o gate é a
única rede antes da base inteira. Ver [Avisos do desenvolvedor](avisos.md).

Exige `jq` e `node`, que **não** vêm num macOS limpo (`brew install jq node`) —
os hooks do Claude e as pontes do Codex dependem deles. O script confere isso na
entrada e falha com a mensagem certa em vez de estourar no meio de um gate.

Self-check do binário instalado ou compilado (não entra no script: depende de um
app já construído):

```bash
/Applications/Knobler.app/Contents/MacOS/Knobler --selfcheck
```

Para rodar um gate isolado, o cabeçalho de cada `tools/*check*.swift` traz a
linha de compilação. Atenção: harness escrito como `main.swift` (é o caso do
`wirecheck`) tem código top-level e **não** aceita `-parse-as-library`.

## CI

`.github/workflows/ci.yml` roda em push para `master`, em pull request e sob
demanda: gera o projeto com XcodeGen, compila em Debug com
`CODE_SIGNING_ALLOWED=NO` (o runner não tem o certificado local) e executa
`./tools/check.sh`. O snapshot visual **não** roda na CI — precisa de sessão
gráfica e o gate é humano: alguém precisa olhar os PNGs.

## Validação visual

O harness offscreen é o gate de UI:

```bash
./tools/snapshot.sh
```

Leia os PNGs gerados em `Snapshots/` depois de mudanças visuais. A lista de
fontes em `tools/snapshot.sh` é manual; ao adicionar uma dependência SwiftUI
da `NotchView`, inclua-a ali.

## Relay

```bash
cd relay
npm ci
npm test
```

O relay não é necessário para a API local nem para o app básico. Ele é usado
pelas notificações externas e deve ser validado separadamente.

## Flags úteis

- `Knobler --selfcheck` — valida o shim de exceção sem abrir UI.
- `Knobler --download-model` — baixa o modelo Parakeet e encerra; usado pelo
  postflight do cask.
- `Knobler --ajustes` — abre Ajustes.
- `Knobler --ajustes=pomodoro` — abre um painel específico para screenshots.

Só uma instância roda por vez, e a mais nova vence: abrir um build do
DerivedData (com ou sem flag) com o Knobler de `/Applications` aberto **encerra**
o de `/Applications`. Os modos que saem sem UI (`--selfcheck`,
`--download-model`, `--permissoes`) não encerram nada. Detalhes em
`docs/architecture.md`.

## Logs

Log do app usa `os.Logger`, nunca `NSLog`: no macOS 27 o `NSLog` chega ao log
unificado com o texto inteiro trocado por `<private>`, e o gate `semnslog` do
`tools/check.sh` barra a volta dele.
`print` só vale onde a saída é o terminal — os modos de linha de comando
(`--download-model`, `--permissoes`, `--selfcheck`) e os self-checks.

```swift
import os

private let log = Logger(subsystem: "com.zoi.knobler", category: "midia")
```

- Um logger por arquivo, `private` no topo, com a categoria da área (lista em
  [Troubleshooting › Logs úteis](troubleshooting.md#logs-úteis)). No escopo do
  arquivo ele não colide com o `log` de outro fonte, dispensa `self.` em
  closure e não obriga os harnesses que compilam o arquivo isolado a arrastar
  um fonte a mais.
- Nível: falha é `.error`; evento que vale guardar é `.notice`. `.info` e
  `.debug` não persistem — não use para nada que precise ser lido depois.
- Privacidade: valor técnico (porta, pid, status, código, `localizedDescription`
  de erro do sistema) com `privacy: .public`; conteúdo do usuário (nome de
  arquivo, título de notificação, URL vinda de payload) com `.private`. Erro de
  operação em arquivo do usuário registra `domain` e `code` públicos e a
  `localizedDescription` privada, porque ela repete o nome do arquivo.
- A mensagem é autoclosure: dentro de classe, propriedade interpolada precisa de
  `self.` explícito.
- Falha que se repete num timer registra uma vez e de novo só quando volta ao
  normal (`tapFalhaRegistrada` em `VolumeHUD.swift`), senão enche o log.

## Instalação local do build

```bash
ditto /tmp/knobler-dd/Build/Products/Release/Knobler.app \
  /Applications/Knobler.app
open -a /Applications/Knobler.app
```

Se substituir uma cópia em uso, encerre o app antes.

O TCC ancora a permissão de Acessibilidade na assinatura do binário: se a
identidade mudar entre uma instalação e outra, o `csreq` guardado deixa de casar
e o ditado morre em silêncio — a ⌥ direita para de responder porque o
`CGEventTap` não é mais criado. Por isso `project.yml` e `tools/release.sh`
assinam com a **mesma** identidade (`Knobler Local Signing`): instalar um build
do `xcodebuild` por cima de um release, ou o contrário, mantém a permissão.

Confira com que identidade a cópia instalada ficou — as duas vias devem imprimir
`Authority=Knobler Local Signing`:

```bash
codesign -dv --verbose=2 /Applications/Knobler.app 2>&1 | grep Authority
```

Se aparecer outra coisa (ex.: `Apple Development: …`, de um build anterior a
esta unificação), a próxima instalação vai derrubar a Acessibilidade uma vez —
reconceda e siga. O procedimento de reset está em
[Troubleshooting](troubleshooting.md#ditado-não-inicia).

## Release

O único escritor da versão é `tools/release.sh`:

```bash
./tools/release.sh patch --dry-run
./tools/release.sh patch
```

O dry-run ainda valida e compila, mas não commita, cria tag nem publica. O
release real exige branch com upstream, `gh` autenticado, tap Homebrew e
working tree sem mudanças nas fontes protegidas. Leia
[`VERSIONING.md`](../VERSIONING.md) antes de publicar.

O clone canônico do tap é o do `brew` (`brew --repo luccas-silveira/knobler`) —
é onde o script bumpa o cask quando `KNOBLER_TAP_DIR` não está setada. **Não
clone o tap em outro lugar**: um clone paralelo não aparece na busca do script,
e foi assim que os caveats reescritos na 0.10.0 ficaram fora do ar, commitados
num clone que o release nunca tocou.

## Site

O site (knobler.appzoi.com.br) vive em `site/` (Astro) e lê versão, link de
download, novidades e docs técnicos do repo a cada build.

```bash
cd site && npx astro dev          # servidor local
node --test site/tests/*.test.mjs # testes (também rodam no tools/check.sh)
site/deploy.sh --dry-run          # builda e lista o que subiria, sem enviar
```

O `tools/release.sh` chama `site/deploy.sh` depois de publicar o release. Se o
deploy falhar, o release segue e o script só avisa.

## Checklist antes de entregar

- código gerado não foi editado à mão;
- build Debug passou;
- self-checks relevantes passaram;
- snapshots foram regenerados e inspecionados quando houve mudança visual;
- relay foi testado quando a mudança toca `relay/`;
- docs e `CHANGELOG.md` refletem o comportamento novo;
- nenhuma chave, token ou dado pessoal entrou no commit.
