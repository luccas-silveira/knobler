# Padrão de versionamento do Knobler — design

**Data:** 2026-07-20
**Status:** aprovado (design), pendente de plano de implementação
**Autor:** sessão Claude Code

## Contexto e problema

O Knobler tinha **dois contadores de versão rodando em paralelo**, que diziam
números diferentes para a mesma pergunta ("que versão é essa?"):

1. **Versão pública (release/Homebrew)** — `v0.1.0 → v0.2.0 → v0.2.1 → v0.2.2`.
   É o que `tools/release.sh <versão>` publica: build → assina ad-hoc → zip →
   GitHub Release (cria a tag `vX`) → bumpa o cask. Já segue SemVer *na prática*,
   mas **sem regra escrita** de quando subir cada dígito.
2. **Versão interna de "sessão/feature"** — `v0.1 → v0.17`. Rótulos informais no
   HANDOFF/MEMORY, um por feature (v0.13 = formatação IA, v0.17 = AirPods). Não é
   SemVer, não tem release, não taga nada.

**A colisão:** a feature "v0.17" (AirPods) nem foi publicada, enquanto o cask
público está em "v0.2.2". Os dois contadores divergem semanticamente.

**Lacunas adicionais:**
- `project.yml` carrega `MARKETING_VERSION: "0.0.0"` fake — a versão real só
  existe no argumento do `release.sh` e nas releases do GitHub.
- Não há `CHANGELOG.md`.
- As tags só existem no remoto (`gh release create`); `git tag -l` local vazio,
  então `git describe` não funciona.

## Decisões (fechadas com o usuário)

1. **Um número canônico só: o SemVer do release.** O contador "vN de sessão" é
   **aposentado** — HANDOFF e MEMORY passam a citar a versão de release.
2. **Regra de bump: SemVer 2.0.0** com a convenção pragmática de 0.x na fase
   atual ("o que for SOTA").
3. **Fonte da verdade: a git tag `vX.Y.Z`**, com `project.yml` espelhando a
   última release. **Só o `release.sh` escreve o número.**
4. **Enforçar o padrão no `release.sh`** — a ferramenta impõe, o padrão não
   drifta por disciplina manual.

## O padrão

### Esquema — Semantic Versioning 2.0.0

Formato `MAJOR.MINOR.PATCH`. Tag `vMAJOR.MINOR.PATCH`.

### Regras enquanto pré-1.0 (MAJOR = 0, fase atual)

| Dígito | Sobe quando… | Exemplos do histórico |
|---|---|---|
| **MINOR** `0.X.0` | feature/capacidade nova de usuário | AirPods no notch, formatação IA, Pomodoro |
| **PATCH** `0.x.Y` | fix, crash-fix, polish, ajuste de UI/snapshot, bump de dependência | crash do `installTap`, progresso streaming |
| **MAJOR** | travado em `0` até o critério de 1.0 | — |

Enquanto pré-1.0, uma **quebra da API HTTP local** entra num MINOR, mas é
**marcada explícita no CHANGELOG** com `⚠ BREAKING`.

### Corte do 1.0.0

Quando app + API HTTP local forem considerados estáveis o bastante para que
quebrá-los mereça um sinal "grande". De 1.0 em diante vira **SemVer estrito**:
quebra de API/comportamento → MAJOR, feature nova → MINOR, fix → PATCH.

### Builds de dev entre releases (opcional / stretch)

Build fora do `release.sh` mostra `X.Y.Z+<shortsha>` (build metadata do SemVer),
para ser rastreável ao commit. **Marcado como stretch** — o núcleo é apenas que o
`project.yml` mostre a última versão real, não `0.0.0`. Pode cair do plano.

## `release.sh` — comportamento enforçado

Uso mantém retrocompat: `./tools/release.sh <versão> [--dry-run]`. Novo:
aceita também `./tools/release.sh <major|minor|patch>` para **auto-computar** a
próxima versão a partir da última tag.

Fluxo novo (adições em **negrito**):

1. Descobrir a **última versão** via `git tag --list 'v*' --sort=-v:refname` (ou
   `gh release list` como fallback). Sem tags → primeira release.
2. **Resolver a versão-alvo:** se veio `major|minor|patch`, computa a partir da
   última; se veio `X.Y.Z` explícito, usa. **Validar que é SemVer bem-formada e
   estritamente maior que a última tag** — senão, aborta (impede reuso ou
   retrocesso).
3. Exigir árvore limpa nas fontes (já existe) **e uma entrada `## [X.Y.Z]` no
   CHANGELOG** (ou uma seção `## [Unreleased]` para consumir).
4. **Bumpar `MARKETING_VERSION` e `CURRENT_PROJECT_VERSION` no `project.yml`** para
   `X.Y.Z`, **renomear `## [Unreleased]` → `## [X.Y.Z] - <data>` no CHANGELOG**, e
   **commitar** ("release: vX.Y.Z") em `master`.
5. Build Release desse commit (fluxo atual de assinatura/zip mantido).
6. **Criar a tag anotada local `vX.Y.Z`** nesse commit e **push da tag**.
7. `gh release create vX.Y.Z` usando **`--notes-file` com a seção do CHANGELOG**
   (em vez da nota genérica "Knobler vX").
8. Bumpar o cask (sed version+sha — mantido).
9. **Push de `master`** (o commit de bump) + push do tap (mantido).

Guards mantidos: `gh` autenticado, tap presente, `--dry-run` não publica nada,
bump idempotente do cask.

> **Nota CFBundleVersion:** `CURRENT_PROJECT_VERSION` idealmente é um build number
> monotônico, mas hoje o `release.sh` já usa o mesmo `X.Y.Z` para os dois. Mantemos
> igual por simplicidade (app de distribuição para amigos); revisitar só se o
> Homebrew/notarização reclamar. `// ponytail:` no script.

## `CHANGELOG.md` (formato Keep a Changelog)

Raiz do repo. Uma seção por release, mais uma `## [Unreleased]` no topo.
Grupos: `Added` / `Changed` / `Fixed` (+ `⚠ BREAKING` quando aplicável). É o
destilado público do que hoje mora no HANDOFF, e a fonte das notas do release.

```
# Changelog

## [Unreleased]

## [0.2.2] - 2026-07-20
### Fixed
- Progresso streaming do --download-model no brew install.
...
```

## Migração (uma vez)

1. `git fetch --tags` — trazer as 4 tags (`v0.1.0..v0.2.2`) para local.
2. `project.yml`: `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` `"0.0.0"/"0"` →
   `"0.2.2"` (última release shipada).
3. Criar `CHANGELOG.md` com as entradas retroativas `0.1.0 → 0.2.2` reconstruídas
   do HANDOFF, e uma seção `## [Unreleased]` para o trabalho dos AirPods.
4. Criar `VERSIONING.md` na raiz com este padrão em forma curta (referência viva).
5. `CLAUDE.md`: adicionar seção curta apontando para `VERSIONING.md` e a regra de
   bump, para futuras sessões seguirem.
6. HANDOFF/MEMORY: parar de usar "vN de sessão"; a próxima release dos AirPods é
   **0.3.0**.

## Arquivos afetados

- `tools/release.sh` — fluxo enforçado (itens acima).
- `project.yml` — versão real em vez de `0.0.0`.
- `CHANGELOG.md` — **novo**.
- `VERSIONING.md` — **novo**.
- `CLAUDE.md` — ponteiro curto para o padrão.

## Fora de escopo (YAGNI)

- Stamping `+<shortsha>` em build de dev (stretch; pode cair).
- Build number monotônico separado do MARKETING_VERSION.
- Assinatura Developer ID / notarização (decisão de distribuição, não de versão).
- CI/GitHub Actions para release (o `release.sh` local basta hoje).

## Validação

- `bash -n tools/release.sh` + `--dry-run` (não publica).
- `ruby -c` do cask permanece válido.
- Teste de guarda: passar uma versão ≤ última tag deve abortar; passar `patch`
  deve computar `0.2.3`.
- `git describe --tags` funciona após a migração.
- Próxima release real (`0.3.0`, AirPods) exercita o fluxo ponta a ponta.
