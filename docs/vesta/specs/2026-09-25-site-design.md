# Site do Knobler — reformulação

## Objetivo

Refazer do zero, visual e estrutura, o site `knobler.appzoi.com.br`. Hoje ele
parou na v0.22.0; o app está na v0.35.2.

Sucesso: um usuário de Mac que não é dev entende o que o app faz no primeiro
fold, baixa, passa pelo Gatekeeper sem ajuda e concede as permissões. Quem já
usa acha a referência técnica. E o site não envelhece de novo: versão,
download e changelog vêm do repositório a cada build.

## Público

1. Usuário de Mac em geral, sem Terminal.
2. Dev/usuário avançado, que prefere Homebrew e quer API, webhooks e plugins.
3. Quem já usa o app e procura como fazer algo ou resolver um problema.

## Restrições

- Só pt-BR.
- Continua em Astro, sem framework de UI.
- Cada afirmação sobre o app é provada por screenshot real (`tools/snapshot.sh`
  ou captura manual, conforme a skill `snapshot-ui`).
- Identidade herda o `DESIGN.md` do app: SF Pro, preto absoluto, cor vinda do
  conteúdo, geometria do notch como motivo. Anti-referências do `PRODUCT.md`
  atual do site continuam valendo (nada de template SaaS).

## Onde mora

Pasta `site/` dentro do repositório do app. O repositório `knobler-site` é
arquivado depois do primeiro deploy do novo site.

O build lê do disco, sem rede:

- `CHANGELOG.md`: versão atual (primeira entrada `## [X.Y.Z]`) e a página de
  novidades.
- `docs/local-api.md`, `docs/webhooks.md`, `docs/plugins.md`,
  `docs/troubleshooting.md`: referência técnica, por uma lista explícita de
  arquivos. Nada fora da lista é publicado (specs, handoffs e backlog ficam
  de fora).

## Mapa do site

- `/` — hero com o notch em ação, botão **Baixar** com a versão, link
  secundário para Homebrew; recursos agrupados; chamada para instalar.
- `/recursos/<slug>` — uma página por recurso, texto escrito à mão para
  leigo, com screenshot. Lista inicial: os 21 itens de "Usar as features" em
  `docs/index.md`, agrupados na home.
- `/instalar` — download, passo a passo do Gatekeeper com imagens (o app não
  é notarizado), permissões (Acessibilidade e demais) e a alternativa
  `brew install --cask`.
- `/novidades` — gerada do `CHANGELOG.md`.
- `/docs/<slug>` — as quatro referências técnicas lidas do repositório.
- `404`.

## Download

URL montada da versão lida no build:
`https://github.com/luccas-silveira/knobler/releases/download/vX.Y.Z/Knobler-X.Y.Z.zip`.
O `release.sh` gera exatamente esse nome.

## Testes

- Build do site falha se a versão não for encontrada no `CHANGELOG.md` ou se
  um arquivo da lista de docs sumir.
- Um check em `tools/check.sh` roda o build do site e confere que a versão do
  HTML gerado é a do `CHANGELOG.md` e que o link de download aponta pra ela.
- Links internos quebrados quebram o build.

## Em aberto para a pesquisa

- Como o site chega hoje ao servidor 147.79.87.179 (nginx). A spec só exige
  que a publicação seja um comando único e documentado.
- Se o `release.sh` publica o site sozinho ou só lembra de publicar.
