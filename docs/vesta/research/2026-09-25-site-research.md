# Pesquisa — site

Spec: `docs/vesta/specs/2026-09-25-site-design.md`

## Achados

### A1 — O app já tem, por versão MINOR, um texto de novidades escrito para leigo
- Fonte: `Knobler/Novidades/0.35.0.html:1-14`, `Knobler/NovidadesCatalogo.swift:20` (0.25.0 a 0.35.0)
- Contradiz a spec: parcial (spec gera `/novidades` só do `CHANGELOG.md`)
- Pergunta: `/novidades` usa esse texto amigável onde existe e o CHANGELOG técnico no resto, ou só o CHANGELOG?

### A2 — Os 4 docs técnicos linkam 8 arquivos fora da lista
- Fonte: `docs/local-api.md:224,235,264`, `docs/webhooks.md:110`, `docs/plugins.md:27`, `docs/troubleshooting.md:243,305`
- Contradiz a spec: parcial
- Pergunta: link para doc que não está no site vira link para `/recursos/<slug>` quando houver, e texto simples quando não houver (ex.: `relay-operacao.md`, `development.md`)? O build quebra em link não resolvido.

### A3 — `troubleshooting.md` é escrito para dev (começa em bash)
- Fonte: `docs/troubleshooting.md` início
- Contradiz a spec: parcial (público 1 não usa Terminal)
- Pergunta: fica como referência técnica e a página `/instalar` cobre os problemas de leigo (Gatekeeper, permissões)?

### A4 — 6 das 21 features não têm imagem na doc; 2 não têm imagem nenhuma
- Fonte: `docs/images/`, `Snapshots/`; sem imagem: avisos, apple-reminders, link-preview, color-picker, texto-da-tela, mirror. Nada existe para color-picker e mirror.
- Contradiz a spec: sim (toda afirmação provada por screenshot)
- Pergunta: captura manual das duas antes de publicar, ou essas páginas saem sem imagem na primeira versão?

### A5 — Deploy não está versionado; o relay vai por rsync para o mesmo VPS
- Fonte: `docs/superpowers/plans/2026-07-20-webhook-mapping-relay.md:470`, `docs/relay-operacao.md:20-23`; o repo do site não tem script
- Contradiz a spec: não (spec deixou em aberto)
- Pergunta: a raiz do nginx para `knobler.appzoi.com.br` precisa ser lida no servidor antes de escrever `site/deploy.sh`. Posso entrar por ssh em `root@147.79.87.179` só para ler a config?

### A6 — `release.sh` não conhece o site
- Fonte: `tools/release.sh:128-130, 197, 237-241`
- Contradiz a spec: não
- Pergunta: ao publicar versão, o `release.sh` roda o deploy do site sozinho (site nunca atrasa, mas release passa a depender do servidor) ou só imprime o comando?

### A7 — Reaproveitável do site antigo
- Fonte: `knobler-site/src/components/NotchShape.astro`, `CodeBlock.astro`, `scripts/dark-screenshots/run.sh:11-24` (gera screenshots escuros do código real), `src/data/features.ts:17-197` (23 textos, rascunho), `DESIGN.md`, `PRODUCT.md`
- Contradiz a spec: não. Registro; `changelog.ts` manual morre.

### A8 — CI tem node, mas o Astro 7 pede node ≥ 22.12 e `npm ci` precisa de rede
- Fonte: `.github/workflows/ci.yml:24-25`, `tools/check.sh:44-48,179-184`
- Contradiz a spec: não. Se o runner tiver node antigo, `actions/setup-node` com 22.

### A9 — Desde o macOS 15, o atalho "Control-clique > Abrir" não libera mais app sem notarização
- Fonte: https://developer.apple.com/news/?id=saqachfa (ago/2024) — o caminho é Ajustes do Sistema > Privacidade e Segurança > "Abrir Mesmo Assim"
- Contradiz a spec: não. O passo a passo de `/instalar` usa só esse caminho; as imagens precisam ser capturadas num Mac com o alerta na tela.

### A10 — Referências visuais
- Fonte: apple.com (produto flutuando, título curto, dois botões em pílula), developer.apple.com (preto, SF Pro, cartões por tema)
- Contradiz a spec: não. Confirma a direção "página de produto da Apple" do `PRODUCT.md` atual. Pesquisa externa ampla pulada: não há API externa incerta na spec além do Gatekeeper.

## Fila do grill

1. A5 — acesso ao servidor para ler o nginx (trava A6)
2. A6 — release publica o site sozinho?
3. A1 — fonte da página de novidades
4. A4 — features sem imagem
5. A2 — destino dos links para docs fora da lista
6. A3 — onde mora a ajuda para leigo
