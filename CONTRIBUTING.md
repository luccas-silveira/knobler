# Contribuindo

Leia primeiro [README](README.md), [arquitetura](docs/architecture.md) e o
[guia de desenvolvimento](docs/development.md). O projeto é um app macOS
nativo; mudanças pequenas que preservam as fronteiras existentes são
preferíveis a uma camada nova de abstração.

## Fluxo

1. Crie uma branch a partir do estado atual.
2. Reproduza o comportamento ou leia o doc da feature antes de editar.
3. Faça a menor mudança que resolve o problema.
4. Atualize docs e `CHANGELOG.md` quando o comportamento público mudar.
5. Rode o checklist de [`docs/development.md`](docs/development.md).
6. Abra um PR descrevendo comportamento, validação e permissões envolvidas.

## Regras do repositório

- `project.yml` é a fonte do projeto; nunca edite `Knobler.xcodeproj` à mão.
- Arquivo Swift novo exige `xcodegen generate` antes do build.
- Dependências novas precisam de justificativa, licença/proveniência e impacto
  no binário.
- Mudanças de UI exigem `./tools/snapshot.sh` e inspeção dos PNGs.
- Não coloque tokens, chaves, dumps de áudio, imagens pessoais ou dados de
  webhook no commit.
- O projeto ainda não possui test target Swift; use self-checks standalone,
  build, snapshots e os testes do relay conforme a área alterada.
- `./tools/check.sh` roda todos os self-checks de uma vez e é o mesmo comando da
  CI (`.github/workflows/ci.yml`) — rode antes de abrir PR. Self-check novo
  precisa entrar nesse script.

## Commits

Use mensagens curtas e imperativas no estilo Conventional Commits já usado no
histórico, por exemplo:

```text
feat: add activity cancellation endpoint
fix: preserve ask answers across pages
docs: document local API lifecycle
```

Não faça bump de versão nem crie tag manualmente. O release é responsabilidade
de `tools/release.sh`; veja [`VERSIONING.md`](VERSIONING.md).

## Pull request

Inclua:

- resumo do problema e da solução;
- arquivos ou boundaries afetados;
- comandos de validação e resultado;
- screenshots para mudanças visuais;
- impacto em permissões, dados locais, rede ou compatibilidade HTTP.

Se a mudança alterar uma decisão arquitetural, atualize
[`docs/architecture.md`](docs/architecture.md) e adicione/atualize uma spec em
`docs/superpowers/specs/`.
