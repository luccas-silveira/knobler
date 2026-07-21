# Now playing universal — pesquisa

**Data:** 2026-07-21 · Insumo pro plano de implementação do design homônimo.

## Fonte: mediaremote-adapter (ungive)

- Repo: <https://github.com/ungive/mediaremote-adapter> · **BSD 3-Clause** ·
  último release **v0.7.6 (2026-05-11)** — ativamente mantido.
- **Testado no macOS 26** (issue #13, fechada). O bloqueio do 15.4+ é
  contornado porque `/usr/bin/perl` reporta bundle ID `com.apple.perl` e
  processos `com.apple.*` têm o entitlement do MediaRemote.
- ⚠️ README avisa: "still in development", pode haver breaking change em
  minor. **Pinar a tag v0.7.6.**

## CLI (o contrato inteiro)

```
/usr/bin/perl <adapter.pl> <MediaRemoteAdapter.framework> COMANDO
```

| Comando | Uso no Knobler |
|---|---|
| `stream` | fonte contínua (JSON por linha) |
| `get` | debug/checagem pontual |
| `send N` | 0 Play · 1 Pause · 2 Toggle · 4 Next · 5 Prev · **6 Toggle Shuffle** |
| `seek MICROS` | não usamos (barra é só exibição) |
| `test` | exit 0 = adapter funcional → **health check no launch** |

Flags do `stream` que interessam:

- `--debounce=N` (ms) — evita rajadas de eventos; MewNotch usa sem debounce,
  mas temos tint de capa que custa; usar ~100 ms.
- `--no-diff` — desliga o modo diff. **Não usar**: diff é mais barato; o
  parser faz merge (ver formato).
- `--no-artwork` existe caso a capa pese demais (não é o caso).

### Formato do stream

Uma linha = `{"type":"data","diff":bool,"payload":{...}}`.

- `diff=false` → payload é o estado completo (substitui tudo).
- `diff=true` → só campos alterados; **chave ausente ≠ null**; chave presente
  com `null` → remover o campo. Merge sobre o último estado completo.
- Payload: `bundleIdentifier`, `parentApplicationBundleIdentifier` (ex.:
  Safari pai de uma aba), `playing`, `title`, `artist`, `album`, `duration`,
  `elapsedTime`, `timestamp`, `playbackRate`, `shuffleMode`, `repeatMode`,
  `artworkData` (base64) + `artworkMimeType`, e mais.
- Posição na UI = `elapsedTime + (now - timestamp) × playbackRate`.

### Pegadinhas conhecidas (issues)

- **#23 (aberta):** o stream imprime um payload **vazio** primeiro — ignorar
  payload sem `bundleIdentifier`/`title` em vez de limpar o card.
- **#38 (aberta):** race de registro no startup do stream — eventos logo após
  o launch podem se perder; o primeiro payload completo corrige. Não
  contornar por ora.
- **#28 (aberta):** `duration` pode vir **Infinity** (live streams) — tratar
  como "sem duração" (esconder barra de progresso).
- `artworkData` chega **atrasado** em relação ao resto dos metadados — o card
  deve renderizar sem capa e atualizar quando ela chegar (hoje já é assim,
  o download do Spotify também era assíncrono).
- Fechada mas ilustrativa: aba do Chromium fechada não travava mais o stream
  (#15) — corrigida na versão pinada.

## Obtenção do framework (vendoring)

Os releases do GitHub **não têm binário** (source only). Duas rotas:

1. **Build local a partir do source pinado** *(escolhida — supply chain limpa)*:
   ```bash
   git clone --branch v0.7.6 https://github.com/ungive/mediaremote-adapter
   cd mediaremote-adapter && mkdir build && cd build && cmake .. && cmake --build .
   ```
   Sai `MediaRemoteAdapter.framework` (universal x86_64+arm64). Commitar o
   framework compilado + `mediaremote-adapter.pl` em `Knobler/Vendor/` com um
   `PROVENANCE.md` (tag, comando, data).
2. Copiar o binário que o MewNotch commitou no repo dele — descartada
   (binário de terceiro sem procedência).

`project.yml`: os dois entram como **Resources** (o framework não é linkado;
quem o carrega é o perl). Sem embed/sign phase no build de dev. ⚠️ Para
distribuição assinada (cask/release.sh): codesign do bundle com `--deep` ou
assinar o framework aninhado antes — anotar no plano como passo do release,
não do dev loop.

## Referência de integração real: MewNotch

`MewNotch/Utils/Helpers/Media/NowPlaying.swift`
(<https://github.com/monuk7735/mew-notch>) — mesmo desenho que o spec prevê:

- `Process` com `/usr/bin/perl [adapter.pl, frameworkPath, "stream"]`, pipe
  no stdout, leitura linha a linha, decode JSON.
- Comandos = `Process` one-shot `["send", "\(id)"]` (enum `MRCommand` com os
  IDs da tabela acima).
- Ícone/nome do app de origem via
  `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` — bônus
  barato se quisermos mostrar de onde vem o som.
- Validação de que o desenho funciona em produção: MewNotch e BoringNotch
  usam esse motor desde o 15.4.

## Decisões que a pesquisa fecha pro plano

1. Pinar **v0.7.6**, build local via cmake, artefatos commitados em
   `Knobler/Vendor/` + `PROVENANCE.md`.
2. `stream --debounce=100` com parser de diff (merge, ausente≠null).
3. Health check com `test` no launch: exit ≠ 0 → não inicia a fonte, loga,
   card fica vazio (degradação do spec).
4. Shuffle = `send 6`; estado vem de `shuffleMode` no stream.
5. Ignorar payload inicial vazio (#23); `duration` infinita → sem barra (#28).
6. Barra de progresso continua só exibição — `seek` fica fora do escopo.
