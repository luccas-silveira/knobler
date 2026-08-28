# 002 — O que as outras shelfs fazem que os usuários gostam

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:research`
Status: fechado (2026-08-28)
Assignee: pesquisa
Blocked by: —

## Pergunta

Levantamento amplo das ferramentas de shelf bem avaliadas no macOS — Yoink,
Dropover, Dropzone, Unclutter e o que mais aparecer — com o que os usuários
elogiam e reclamam nas reviews e nos fóruns.

Três perguntas são obrigatórias, porque tocam decisões já travadas neste mapa:

1. **Empilhamento** é automático (todo drop vira pilha) ou manual (o usuário
   junta), e dá pra desempilhar?
2. **Ordem** — item novo entra em que ponta, e o que acontece quando o usuário
   solta de novo um arquivo que já está lá?
3. **Saída** — o item some da shelf ao ser arrastado pra fora, fica, ou é opção?
   Se é opção, qual é o padrão de fábrica?

Se três ferramentas boas convergirem contra alguma decisão deste mapa, isso é
achado, e vira uma linha na resolução com a recomendação — não uma troca
silenciosa.

O resto do levantamento (ideias, reclamações recorrentes, o que falta em todas)
sai junto e vira **Ainda não especificado** no mapa, não ticket.

Saída em `docs/wayfinder/pesquisa-002-shelfs-do-macos.md`, linkada daqui.

## Resolução

[pesquisa-002-shelfs-do-macos.md](../pesquisa-002-shelfs-do-macos.md).

**Empilhamento:** só o Yoink empilha automático, e mesmo lá é caixa desligável; Dropzone e OpenYoink empilham à mão; Dropover não empilha. Tirar um arquivo de dentro da pilha: Yoink não deixa (desmancha inteira), OpenYoink deixa, Dropzone não encontrado.
**Ordem:** não documentada em Yoink, Dropover nem Dropzone; nenhuma das quatro fala do arquivo já presente solto de novo. Só a Unclutter escreve "Newest items appear at the top" — a favor do mapa.
**Saída (o achado):** as quatro fazem disso **opção** — Yoink `values.autoRemoveAfterDrag`, Dropover opção nova na 5.2.5, Dropzone lock por item, OpenYoink default `keep`. Recomendação: manter *sair* como padrão de fábrica, sem travar o comportamento no código.
**Contra o mapa:** Yoink, Dropover e Unclutter movem por padrão (Finder, ⌥ copia), contra o `.copy`-só. Recomendação: manter a rota conservadora — é escolha deliberada do usuário.
