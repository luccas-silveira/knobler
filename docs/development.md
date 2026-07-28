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
xcodegen generate
xcodebuild -project Knobler.xcodeproj -scheme Knobler \
  -configuration Debug build
```

Para um build Release isolado:

```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler \
  -configuration Release -derivedDataPath /tmp/knobler-dd build
```

O app produzido fica em
`/tmp/knobler-dd/Build/Products/Release/Knobler.app`.

## Checks rápidos

Self-check do domínio Ask:

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/AskModels.swift Knobler/AskFeature.swift \
  tools/askcheck.swift -o /tmp/askcheck
/tmp/askcheck
```

Self-check do binário instalado ou compilado:

```bash
/Applications/Knobler.app/Contents/MacOS/Knobler --selfcheck
```

Checks puros adicionais:

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/Wire.swift tools/wirecheck/main.swift -o /tmp/wirecheck
/tmp/wirecheck

xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/AirPodsBattery.swift tools/airpods_selfcheck.swift \
  -o /tmp/airpods-selfcheck
/tmp/airpods-selfcheck
```

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

## Instalação local do build

```bash
ditto /tmp/knobler-dd/Build/Products/Release/Knobler.app \
  /Applications/Knobler.app
open -a /Applications/Knobler.app
```

Se substituir uma cópia em uso, encerre o app antes.

⚠️ **Instalar um build do `xcodebuild` derruba a Acessibilidade.** O TCC ancora
a permissão na assinatura do binário: o `xcodebuild` assina com a identidade de
desenvolvimento do Xcode (`Apple Development: …`), enquanto o `tools/release.sh`
assina com `Knobler Local Signing`. Sobrescrever uma cópia com a outra troca a
identidade, o `csreq` guardado pelo TCC deixa de casar e o ditado morre em
silêncio — a ⌥ direita para de responder porque o `CGEventTap` não é mais
criado.

Confira com que identidade a cópia instalada ficou:

```bash
codesign -dv --verbose=2 /Applications/Knobler.app 2>&1 | grep Authority
```

Para manter a permissão estável entre instalações, instale sempre pela mesma
via. Se a Acessibilidade cair, o procedimento de reset está em
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

## Checklist antes de entregar

- código gerado não foi editado à mão;
- build Debug passou;
- self-checks relevantes passaram;
- snapshots foram regenerados e inspecionados quando houve mudança visual;
- relay foi testado quando a mudança toca `relay/`;
- docs e `CHANGELOG.md` refletem o comportamento novo;
- nenhuma chave, token ou dado pessoal entrou no commit.
