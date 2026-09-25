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

Links desses docs para arquivos fora da lista: vão para `/recursos/<slug>`
quando o assunto tem página; senão, para o arquivo no GitHub
(`github.com/luccas-silveira/knobler/blob/master/...`). Imagens de
`docs/images/` citadas nos docs são copiadas no build.

## Mapa do site

- `/` — hero com o notch em ação, botão **Baixar** com a versão, link
  secundário para Homebrew; recursos agrupados; chamada para instalar.
- `/recursos/<slug>` — uma página por recurso, texto escrito à mão para
  leigo, com screenshot. Lista inicial: os 21 itens de "Usar as features" em
  `docs/index.md`, agrupados na home.
- `/instalar` — download, passo a passo do Gatekeeper com imagens (o app não
  é notarizado), permissões (Acessibilidade e demais) e a alternativa
  `brew install --cask`.
- `/novidades` — uma entrada por versão do `CHANGELOG.md`. Onde existe
  `Knobler/Novidades/<versão>.html` (texto para leigo, com as imagens de
  `Knobler/Novidades/midia/`), ele substitui o texto do CHANGELOG.
- `/docs/<slug>` — as quatro referências técnicas lidas do repositório.
- `404`.

## Imagens

Toda página de recurso tem screenshot. Avisos, Lembretes da Apple, texto da
tela e preview de link reaproveitam PNGs de `Snapshots/` ou
`Knobler/Novidades/midia/`. Conta-gotas e espelho de câmera são capturados à
mão no app real, com aviso ao usuário antes (mexe na máquina dele).

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

## Publicação

`site/deploy.sh`: build e `rsync -az --delete dist/ root@147.79.87.179:/var/www/knobler-site/`
(raiz lida no nginx do servidor em 2026-09-25).

O `tools/release.sh` roda `site/deploy.sh` depois do `gh release create`.
Falha no deploy do site só avisa; não desfaz a release do app.

## Decisões do grill

- **A5** — publicação por `rsync` para `/var/www/knobler-site`. Motivo: raiz lida no nginx do servidor; nada estava versionado.
- **A6** — `release.sh` publica o site sozinho; falha só avisa. Motivo: o site parou 13 versões atrás por depender de lembrar.
- **A1** — `/novidades` usa o texto de `Knobler/Novidades/` onde existe, CHANGELOG no resto. Motivo: texto já escrito para leigo.
- **A4** — conta-gotas e espelho capturados à mão antes de publicar. Motivo: não existe imagem nenhuma deles.
- **A2** — links para docs fora da lista vão para a página de recurso ou para o GitHub. Motivo: 8 links quebrariam.
- **A3** — `/instalar` é a ajuda do leigo (Gatekeeper e permissões); troubleshooting fica técnico. Motivo: o guia começa em bash.
- **A7, A8, A9, A10** — só confirmam a spec. A9 fixa o caminho do Gatekeeper: Ajustes > Privacidade e Segurança > "Abrir Mesmo Assim" (o Control-clique não funciona desde o macOS 15).
