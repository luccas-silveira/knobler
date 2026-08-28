# 009 — As três mudanças no app rodando

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:task`
Status: aberto
Assignee: claude
Blocked by: 006, 007, 008

## Pergunta

O destino deste mapa é o app rodando, não o código escrito. Até aqui nada foi
visto na tela de verdade — a shelf é uma das seções que **não renderizam
offscreen** no harness de snapshot, então gate verde não prova nada sobre ela.

Subir a build e conferir, na tela:

1. **Ordem** — soltar três arquivos em sequência e ver o último na esquerda;
   soltar de novo o primeiro e ver ele pular pra frente; encher a prateleira e
   ver o mais antigo sair pela direita.
2. **Empilhamento** — soltar cinco de uma vez e ver uma entrada; arrastar um
   item sobre outro e ver a pilha nascer; abrir a pilha, tirar um arquivo,
   desempilhar o resto.
3. **Saída** — arrastar pra fora pro Finder e ver o item sumir da shelf **e o
   arquivo original continuar onde estava**; arrastar pra um destino que
   recusa e ver o item ficar; arrastar dentro da própria shelf e ver que não
   conta como saída.

Fechar com `./tools/check.sh` verde e o CHANGELOG escrito em `## [Unreleased]`,
mais a novidade em `Knobler/Novidades/<versão>.html` — é entrada `Added`, logo
MINOR, e o `release.sh minor` aborta sem ela.

## O que a tela mostrou

Rodado em 2026-08-28, na build Debug, no macOS 26 Tahoe da máquina de
desenvolvimento. Os gestos foram dirigidos por eventos sintéticos
(`CGWarpMouseCursorPosition` mais `mouseMoved`/`Dragged` em passos pequenos, o
mesmo método da medição 001), e **o efeito de cada um foi lido em
`defaults read com.zoi.knobler shelfItems`**, não em pixel de captura: a
prateleira persiste a cada mudança, então o estado é observável de fora com
precisão. As capturas provam o que só existe na tela.

Antes de qualquer medida, duas travas, no espírito do `cortecheck`: um clique
sintético num ícone da faixa de seções tem que trocar o foco (trocou — `musica`
para `nota`, confirmado por `GET /status`), e o `defaults read` tem que refletir
uma mudança feita no app (refletiu). Sem as duas, um harness quebrado passaria
por feature quebrada.

### Passou

| # | Gesto | O que a prateleira ficou |
|---|---|---|
| 1 | Arrastar um item pro Finder | `charlie.txt` chegou na pasta destino e **saiu** da prateleira |
| 2 | Os originais depois disso | os 10 arquivos com o mesmo hash, no mesmo lugar |
| 3 | Arrastar pro vazio da tela | o item **ficou**: `(alfa, bravo)` antes e depois |
| 4 | Arrastar um item sobre outro | `((bravo, alfa))` — uma entrada só, **na posição do de baixo** |
| 5 | Clicar na pilha | a grade abriu, com cabeçalho "‹ 2 arquivos", "Desempilhar" e o ✕ por célula |
| 6 | ✕ numa célula da pilha | sobrou um arquivo, a pilha deixou de ser pilha e **a grade fechou sozinha** |
| 7 | "‹" do cabeçalho | voltou pra linha |
| 8 | "Desempilhar" | `((foxtrot, echo), (golf))` virou `(foxtrot), (echo), (golf)` — soltos, na posição da pilha |

O 4 é o que o 001 tinha marcado como risco: um arraste que termina dentro da
própria prateleira devolve `copy` igual ao Finder, e a regra do 005 escrita
ingenuamente apagaria o item recém-empilhado. **Não apagou** — o `sobreIrma` do
007 segura.

O 5 é a resposta que o 008 deixou pendente: o clique chega pelo `upMonitor`,
mesmo com as NSViews embutidas blindadas pelo hit-testing do SwiftUI.

A miniatura de verdade também apareceu pela primeira vez: onde o harness de
snapshot desenha o ícone de "proibido", a tela mostra a miniatura do QuickLook.

### Não provado, e o motivo é o harness, não o app

**Nenhum drop vindo de fora entrou pela mão sintética.** Isso derruba o item 1
inteiro (ordem: o mais novo na esquerda, o re-arraste subindo, o excesso caindo
pela direita) e a primeira metade do item 2 (um drop de cinco virando uma
pilha).

O que foi eliminado no caminho, e vale registrar pra próxima tentativa:

- A sessão de arraste do Finder **abre** com evento sintético — o fantasma do
  arquivo aparece na captura do meio do gesto. Não é falta de arraste.
- O arraste **saindo** do notch funciona e chega ao Finder (a linha 1 da tabela
  é isso). O motor de eventos serve pros dois sentidos; só a recepção falha.
- O painel do notch tem 700pt e vai do topo até o Dock, então um alvo "no
  Finder" a meia tela cai **dentro** dele. Os primeiros arrastes pra fora
  falharam por isso, não pelo app.
- O card fechado só tem a faixa do notch como área de soltura: soltar 70pt
  abaixo não alcança nada.
- Uma janela que perdeu o foco vai pra trás e a coordenada passa a mirar outro
  app — um arraste acabou pegando uma playlist do Spotify, que abriu o preview
  de link. A medição 001 já tinha escrito essa regra ("cada destino teve a
  posição da janela confirmada imediatamente antes"); ignorá-la custou três
  tentativas.
- Aproximação fina no alvo (últimos 120pt em passos de 3pt) e pouso com 20
  `draggingUpdated` no ponto final **não** resolveram.

Também vale: rodar a build do `DerivedData` faz o app abrir o aviso
"Instalação fora do lugar" e a janela de Ajustes no painel Permissões, que
cobre a tela e atrapalha a medida. A skill `snapshot-ui` já avisa disso para o
`/tmp`; vale pro `DerivedData` igual.

### O que falta, e como fechar

Os três gestos que faltam são drops vindos do Finder, e a mão humana os faz em
menos de um minuto:

1. Soltar três arquivos no notch, um a um, e conferir que o último fica na
   esquerda.
2. Soltar de novo o primeiro dos três e conferir que ele pula pra frente.
3. Selecionar cinco e soltar de uma vez, conferindo que vira **uma** entrada.

O estado depois de cada um se lê com
`defaults read com.zoi.knobler shelfItems`.

A máquina foi restaurada: `shelfItems` de volta ao `()` que estava,
`screenshotsToShelf` de volta a ausente (tinha sido desligado pra um screenshot
não cair na prateleira no meio da medida), `notchSectionOrder` intocado, e o
Knobler de `/Applications` relançado.
