# Versionamento do Knobler

O Knobler segue [Semantic Versioning 2.0.0](https://semver.org/lang/pt-BR/).
**Uma versão canônica só**: o SemVer da release, materializado na git tag
`vX.Y.Z`. Não existe mais "vN de sessão" — HANDOFF e MEMORY citam a versão de
release.

## Regra de bump

Fase atual: **pré-1.0** (`MAJOR = 0`).

| Dígito | Sobe quando… |
|---|---|
| **MINOR** `0.X.0` | feature ou capacidade nova de usuário |
| **PATCH** `0.x.Y` | fix, crash-fix, polish, ajuste de UI/snapshot, bump de dependência |
| **MAJOR** | travado em `0` até o corte do 1.0 (abaixo) |

Enquanto pré-1.0, uma **quebra da API HTTP local** (`127.0.0.1:4477`) entra num
MINOR, mas **marcada com `⚠ BREAKING`** na entrada do CHANGELOG.

### Corte do 1.0.0

Quando app + API HTTP local forem estáveis o bastante para que quebrá-los mereça
um sinal "grande". De 1.0 em diante, **SemVer estrito**: quebra de
API/comportamento → MAJOR, feature → MINOR, fix → PATCH.

## Fonte da verdade

- **Canônico**: a git tag `vX.Y.Z` (criada pelo `release.sh`).
- `project.yml` (`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`) **espelha** a
  última release — não editar à mão.
- **Só o `tools/release.sh` escreve o número.** Um escritor, zero drift.

## Como lançar

Escreva as mudanças em `## [Unreleased]` no [CHANGELOG.md](CHANGELOG.md)
(grupos `Added`/`Changed`/`Fixed`) enquanto desenvolve. Para publicar:

```bash
./tools/release.sh patch          # ou minor / major — auto-computa a partir da última tag
./tools/release.sh 0.3.0          # ou versão explícita
./tools/release.sh patch --dry-run  # valida + builda + zipa, sem publicar
```

O `release.sh` valida que a versão é SemVer e **estritamente maior** que a última
tag, exige entradas em `## [Unreleased]`, então: renomeia `## [Unreleased]` →
`## [X.Y.Z] - <data>` no CHANGELOG, bumpa o `project.yml`, commita
(`release: vX.Y.Z`), builda/assina/zipa, cria a **tag anotada local**, publica no
GitHub Release (notas = seção do CHANGELOG), bumpa o cask e dá push de tudo.
