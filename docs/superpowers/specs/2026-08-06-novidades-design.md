# Página de novidades — design

Data: 2026-08-06
Estado: spec aprovada no brainstorming; pendente pesquisa e grill.

## Problema

O Knobler é `LSUIElement` e cresce por release: v0.24.0 fechou onze peças de
marketplace, e nada disso chega a quem já tinha o app instalado. O único canal
hoje é o `CHANGELOG.md`, técnico demais pra ensinar alguém a usar, e o wizard de
boas-vindas (`Onboarding.swift` + `OnboardingView.swift`), que é texto puro em
SwiftUI, sem imagem, versionado por um `Int` desligado do SemVer.

O que falta é uma página de verdade — texto, print, vídeo curto e tutorial —
que abra sozinha quando a versão sobe e demonstre o que chegou.

## Decisão de forma

A janela é um `WKWebView` com HTML local, não SwiftUI. O motivo é o conteúdo:
figura com legenda, vídeo em loop, passo numerado e botão de ação são baratos em
HTML/CSS e caros em SwiftUI, e o conteúdo muda a cada release enquanto a moldura
não muda nunca. O app já embarca `WKWebView` (Link Preview), então não entra
dependência nova.

O custo aceito: a janela não entra no `tools/snapshot.sh` (`WKWebView` não
renderiza offscreen — vala já documentada no `CLAUDE.md`), e passam a existir
dois vocabulários de estilo no projeto.

## Arquitetura

### Janela

`NovidadesWindow` — uma `NSWindow` com o `WKWebView` ocupando tudo. Abre em três
situações:

1. **Primeiro launch de uma versão nova** — comparação de `MARKETING_VERSION`
   com `novidades.versaoVista`. Pega update pelo Updater, por `brew upgrade` e
   por download manual, e dispara uma vez só por versão.
2. **Menu da barra (◐) → "Novidades…"** — abre com o histórico completo, sem
   gravar versão vista. Substitui o item "Boas-vindas…" de hoje.
3. **`Knobler --novidades`** — mostra tudo e **não** grava a versão vista, pra
   capturar print sem queimar o estado da máquina. Mesmo contrato do
   `--boas-vindas` atual.

### Carga do conteúdo

Nada de `file://`. Um `WKURLSchemeHandler` registra o esquema
`knobler://novidades/…` e serve tudo do bundle: shell, corpos das versões e
mídia. Três ganhos numa decisão:

- `fetch` entre fragmentos funciona sem `allowFileAccessFromFileURLs`;
- mídia relativa carrega sem `allowingReadAccessTo` numa pasta do disco;
- o WebView nunca ganha acesso a arquivo nenhum fora do que o handler entrega.

`decidePolicyFor navigationAction`: `knobler://` segue; `http`/`https` vai pro
`NSWorkspace.shared.open` e cancela na WebView; qualquer outro esquema é
bloqueado.

### Catálogo e estado

`Knobler/NovidadesCatalogo.swift` — arquivo **sem dependência de SwiftUI nem
`AppSettings`**, mesmo motivo do `Onboarding.swift`/`CalendarAviso.swift`: o gate
precisa compilá-lo isolado com `swiftc`.

Responsabilidade única: dada a versão instalada e a versão vista, devolver a
lista de páginas a exibir, mais nova primeiro. Comparação por componentes
inteiros (`0.9.0` < `0.10.0`), nunca lexicográfica — o `Updater.swift` já tem
`versionComponents`/`isNewer`; a pesquisa decide se reusa ou duplica (o gate
compila isolado, e arrastar o `Updater` inteiro pro harness é caro).

Chave nova: `novidades.versaoVista` (String SemVer).

Migração da chave antiga `onboarding.versao` (`Int`):

| Estado antigo | Vira | Vê |
|---|---|---|
| ausente (instalação limpa) | grava versão atual | só `boas-vindas.html` |
| `0` ou legado `false` | `"0.0.0"` | `boas-vindas.html` |
| `1` | `"0.0.0"` | `boas-vindas.html` |
| `2` (viu o wizard atual) | `"0.24.0"` | novidades da 0.25 em diante |

Instalação limpa **não** recebe o histórico acumulado junto da boas-vindas: a
primeira impressão fica curta.

### Ponte de ações

Um `WKScriptMessageHandler` só, nome `app`. O JS manda `{acao, alvo}`; o Swift
casa contra um enum fechado e ignora silenciosamente o que não casar:

- `abrirAjustes(painel)` — os painéis já aceitos pela flag `--ajustes=`
- `instalarPeca(PluginID)` — `plugins.instalar(_:)`
- `abrirCard` — abre o card do notch

Nenhuma string vira chamada arbitrária, nenhum `eval`, nenhum caminho de arquivo
atravessa a ponte.

## Conteúdo

### Estrutura no bundle

```
Knobler/Novidades/
  shell.html        moldura, índice lateral, rodapé
  estilo.css        um só, com modo escuro
  pagina.js         monta o documento a partir das versões pendentes; ponte
  boas-vindas.html  corpo da primeira abertura
  0.25.0.html       corpo de uma release
  midia/            PNG e MP4 referenciados pelas páginas
```

Cada arquivo de versão contém **só o corpo** — sem `<html>`, `<head>` ou
`<style>`. Vocabulário fechado:

```html
<section class="feature">
  <h2>Título da feature</h2>
  <p>O que ela faz e por que existe.</p>
  <figure>
    <video src="midia/ditado.mp4" autoplay loop muted playsinline></video>
    <figcaption>Segure ⌥ direita pra falar.</figcaption>
  </figure>
  <ol class="tutorial">
    <li>…</li>
  </ol>
  <button data-acao="abrirAjustes" data-alvo="ditado">Abrir Ajustes → Ditado</button>
</section>
```

### Mídia

Pasta própria, só o que as páginas referenciam. Copiar `docs/images/` inteiro
está descartado: são 14 MB em 41 PNGs, a maioria sem uso na página.

PNG pro que é estático; MP4 H.264 curto (3–5 s, `autoplay loop muted
playsinline`) pro que é gesto — segurar ⌥ direita, arrastar arquivo pra
prateleira. Print que já existe em `docs/images/` entra como **cópia**: bundle
assinado não aceita symlink.

### Régua editorial

A página ensina a **começar** — o primeiro uso, com a ação embutida no botão — e
linka `docs/` pro resto. O que virar referência completa está no lugar errado.

## O que sai

`OnboardingView.swift`, o versionamento por `Int` do `Onboarding.swift` e o
`tools/onboardingcheck.swift` são aposentados. Os dois passos de hoje viram
seções do `boas-vindas.html`, com print no lugar das linhas de ícone. O
encadeamento pro painel **Ajustes → Permissões** ao fechar a janela continua
exatamente como está.

`docs/onboarding.md` vira `docs/novidades.md`, cobrindo a boas-vindas e a página
de atualização.

## Gates

Dois checks novos em `tools/check.sh` (a lista canônica; check fora dela a CI não
vê):

**`tools/novidadescheck.swift`** — compila o `NovidadesCatalogo` isolado e
assere:

- comparação SemVer por componente: `0.9.0` < `0.10.0`
- ordem decrescente na saída
- as quatro linhas da tabela de migração
- instalação limpa não recebe histórico

**`tools/novidadeshtmlcheck.mjs`** — varre `Knobler/Novidades/*.html` e falha se:

- o nome do arquivo de versão não for SemVer válido
- algum `src` apontar pra mídia inexistente em `midia/`
- algum `data-acao` estiver fora do enum
- algum `data-alvo` de `instalarPeca` não for um `PluginID` real

**`tools/release.sh`** — `minor` aborta sem `Knobler/Novidades/<versão>.html`;
`patch` passa sem.

## QA visual

Fora do `tools/snapshot.sh`. A receita é a das boas-vindas: build, rodar de
`/Applications` ou `~/Applications`, `Knobler --novidades`, achar o `windowID` em
`CGWindowListCopyWindowInfo`, `screencapture -o -l<id>`. Vira comentário em
`docs/novidades.md`.

## Processo

`CLAUDE.md` ganha a regra: **feature nova escreve a seção do HTML junto da
entrada do CHANGELOG**, não no fim do ciclo de release.

## Fora de escopo

- Página remota ou hospedada no site (offline deixa de funcionar; o site passa a
  ter que acompanhar o ritmo do app)
- Geração automática a partir do `CHANGELOG.md`
- Notificação/selo de novidade no ícone da barra de menus
- i18n: o app é pt-BR, a página também

## Riscos conhecidos

1. **Print desatualizado.** Nenhum gate compara a mídia com a UI real. É o mesmo
   risco que `docs/images/` já corre, e o `novidadeshtmlcheck` só garante que o
   arquivo existe.
2. **Peso do bundle.** MP4 por feature acumula release a release. A pesquisa
   deve estimar o teto e decidir se páginas muito antigas saem do bundle.
3. **Dois vocabulários de estilo.** A janela HTML não herda o visual do resto do
   app automaticamente; manter parecido é trabalho manual no `estilo.css`.
