# Mapa: Shelf de arquivos — empilhamento, ordem e saída

Aberto em 2026-08-28

## Destino

A shelf do notch rodando no app com três mudanças: **empilhamento** (um drop de
vários arquivos vira uma entrada só, e dá pra empilhar à mão arrastando um item
sobre outro), **ordem** (o mais novo entra na esquerda, o mais antigo cai pela
direita) e **saída** (o item some da prateleira quando é arrastado pra fora com
sucesso).

Este mapa **carrega a execução**, por decisão do usuário: fecha com o app rodando
e as três mudanças verificadas na tela, não com uma spec pra outra sessão
executar.

Fora do destino: mexer no arquivo original do usuário, e qualquer mudança na
conversão de arquivos ou no preview de link que a shelf hospeda hoje.

## Notas

Domínio: `Knobler/Shelf.swift` (store, capacidade 8, drop delegate, a linha de
itens), `Knobler/ShelfThumbnailDragView.swift` (a miniatura AppKit e o monitor
de mouse que inicia o arraste), `Knobler/ShelfDrop.swift`, `tools/shelfdropcheck.swift`.

Skills a consultar: `snapshot-ui` antes de qualquer captura da shelf — a imagem
`docs/images/expanded-shelf.png` é tirada no app rodando e **mexer nela pede
autorização do usuário**. `impeccable` no ticket da pilha expandida.

Decisões que sobrevivem a qualquer troca de mecanismo:

- A shelf guarda o **caminho do original**, sem cópia. Nada neste mapa move,
  renomeia ou apaga arquivo do usuário.
- O arraste pra fora anuncia **só `.copy`**. Anunciar `.move` faria um arraste
  comum pro Finder mover o arquivo de verdade; o usuário escolheu a rota que não
  corre esse risco.
- O arraste pra fora anuncia só `.copy` **mesmo sabendo que Yoink, Dropover e
  Unclutter movem por padrão** (semântica do Finder, ⌥ copia). Medido no 002 e
  mantido: a rota que não mexe no arquivo do usuário foi escolha deliberada, não
  desconhecimento.
- Itens soltos e pilhas **convivem** na mesma linha. Pilha ocupa uma vaga das 8.
- Arrastar uma pilha leva os N arquivos juntos, e a pilha inteira sai da shelf.

Decisões que dependem do mecanismo e caem junto com ele:

- A remoção ao arrastar dispara pelo retorno de `draggingSession(_:endedAt:operation:)`.
  Se a medição do ticket 001 mostrar que os destinos não distinguem aceitar de
  recusar, a regra "sai em qualquer arraste bem-sucedido" precisa de outra base.
- A pilha expandida toma o card inteiro em grade porque `ScrollView` não é uma
  opção conhecida aqui. É escolha travada, não medida.

## Ordem de execução

| Fase | Tickets | Por quê |
|---|---|---|
| 1. O que ainda não foi olhado — **fechada** | **001** o que os destinos devolvem · **002** o que as outras shelfs fazem · **003** o mais novo na esquerda | O 001 pode matar a saída ao arrastar inteira, então vem antes de qualquer código dela. O 003 é a mudança menor e independente: entrega valor sozinho e fixa a semântica de ordem que o modelo de pilha vai herdar. |
| 2. As duas bases | **004** modelo de pilha e persistência · **005** o item sai ao ser arrastado pra fora | Nada do empilhamento se constrói antes do modelo de dados, e a saída é o mecanismo que a pilha vai reusar. |
| 3. O empilhamento em si | **006** um drop de vários vira uma pilha · **007** empilhar e desempilhar à mão · **008** a pilha expandida | Três frentes independentes sobre a mesma base, tocáveis em paralelo. |
| 4. A prova | **009** as três mudanças no app rodando | O destino é o app rodando; até aqui nada foi visto na tela de verdade. |

## Decisões até aqui

- [001 — O que os destinos devolvem quando aceitam o arraste](tickets/001-o-que-os-destinos-devolvem.md)
  — **a operação separa aceitar de recusar: 7 aceites, 7 `copy`; 2 recusas, 2
  `none`, zero divergência** em nove arrastes sintéticos (Finder, Chrome, VS
  Code/Electron, Mail, Lixeira, soltura no vazio). A regra do 005 tem base. Mas
  **o arraste que termina dentro do próprio app também devolve `copy`**, e o
  contexto de `sourceOperationMaskFor` não separa os dois — a remoção precisa de
  outro sinal, senão apaga o item que o 007 acabou de empilhar. A Lixeira recusa
  com só `.copy` anunciado. Detalhe e método em
  [medicao-001](medicao-001-o-que-os-destinos-devolvem.md).

- [002 — O que as outras shelfs fazem que os usuários gostam](tickets/002-o-que-as-outras-shelfs-fazem.md)
  — **as quatro ferramentas fazem da saída uma opção, não uma regra.** Yoink
  (`values.autoRemoveAfterDrag`), Dropover (opção nova na 5.2.5), Dropzone (lock
  por item) e OpenYoink (default `keep`): sair é o padrão de fábrica nas três
  comerciais, mas nenhuma trava o comportamento. **Empilhamento automático é
  minoria** — só o Yoink faz, e ali é caixa desligável; e ele não deixa tirar um
  arquivo de dentro da pilha sem desmanchá-la, que é justamente o que o ticket
  008 entrega. **Ordem não é documentada** por nenhuma das três maiores; a única
  fonte primária é a Unclutter, "Newest items appear at the top", a favor do
  mapa. Detalhe e fontes em
  [pesquisa-002](pesquisa-002-shelfs-do-macos.md).

- [003 — O mais novo na esquerda](tickets/003-o-mais-novo-na-esquerda.md)
  — **a inversão foi no armazenamento, não na exibição**: o índice 0 passou a
  ser o mais novo e o excesso sai pelo fim, e é essa a semântica que o 004
  herda. O motivo é o gate: a shelf não renderiza offscreen, então a única
  metade que um check hermético alcança é o array — pôr a regra na view a
  deixaria sem prova nenhuma. As três regras vivem em `Knobler/ShelfOrdem.swift`
  e `tools/shelfordemcheck.swift` as cobre. O re-arraste compara por `path`
  porque a pasta volta do UserDefaults sem a barra final do Finder, e por URL
  crua duplicaria depois de um restart. O custo que este ticket tinha aceitado —
  ver a prateleira com a idade trocada no primeiro lançamento — **deixou de
  existir**: o 004 migra invertendo, e o 003 nunca chegou a sair numa release.
  **Nada disso prova a tela
  — que o mais novo apareça à esquerda no app rodando é do 009.**

- [004 — O modelo de pilha e a persistência](tickets/004-modelo-de-pilha-e-persistencia.md)
  — **a entrada é uma struct com uma lista de arquivos, e a persistência ficou
  na mesma chave `shelfItems`, agora array de arrays no plist.** Struct e não
  enum de dois casos: o enum obrigaria um `switch` em cada consumidor só pra
  chegar nos arquivos, e "tem mais de um" já é o discriminante. Não é JSON de
  propósito — a receita de captura da prateleira popula a chave com
  `defaults write`, e um blob dentro dela pioraria a receita. **A migração
  inverte o array antigo**, e com isso o custo que o 003 tinha aceitado deixou
  de existir. O dedupe agora vale entre entradas: re-soltar um arquivo que está
  dentro de uma pilha tira ele de lá. `tools/shelfordemcheck.swift` cobre tudo
  em 29 asserções e não compila contra o modelo anterior. Zero UI: nada no app
  ainda constrói entrada com mais de um arquivo, e é isso que torna a adaptação
  dos call sites idêntica ao comportamento de antes.

- [005 — O item sai da shelf ao ser arrastado pra fora](tickets/005-o-item-sai-ao-ser-arrastado-pra-fora.md)
  — **a saída é uma chave em Ajustes › Prateleira, ligada de fábrica**, e não a
  regra fixa que este mapa tinha travado: decisão do usuário, apoiada no 002. O
  sinal que separa o arraste interno do externo é um aperto de mão
  (`ShelfArrasteInterno`), não geometria — o painel do notch tem 700pt de
  largura e vai do topo da tela até o Dock, então um destino no meio da tela
  cairia dentro do frame. Pilha não saía; o 006 tirou essa trava.

- [006 — Um drop de vários vira uma pilha](tickets/006-um-drop-de-varios-vira-uma-pilha.md)
  — **os providers de arquivo do mesmo drop são esperados juntos e viram uma
  entrada só**, com cada callback escrevendo no próprio índice pra capa não sair
  sorteada. A saída da pilha veio no mesmo commit que o pasteboard de N itens —
  separar as duas é perda de dado. O caminho de um arquivo ficou intocado. As
  folhas e o badge da pilha **não têm gate**: a shelf não renderiza offscreen, e
  isso cai no 009.

## Ainda não especificado

- **O backlog do 002.** O que a pesquisa levantou fora das três decisões deste
  mapa está no fim de [pesquisa-002](pesquisa-002-shelfs-do-macos.md) e ainda
  não foi lido pra virar coisa nenhuma.
- **Conversão e AirDrop dentro de uma pilha.** O menu de contexto de hoje
  ("Converter", "Enviar tudo por AirDrop") assume item solto. O que ele faz
  sobre uma pilha só fica nítido depois do 004. O AirDrop já opera sobre
  `entrada.urls`; "Converter" e "Mostrar no Finder" ainda assumem a capa.

## Fora de escopo

- **Mover, renomear ou apagar o arquivo original.** O usuário escolheu a rota
  onde a shelf só esquece o caminho; mexer no arquivo é outra feature, com outro
  risco.
- **Fazer o `ScrollView` funcionar na shelf.** Levantado como saída pra pilha
  expandida e descartado pelo usuário a favor da grade que toma o card. Se um
  dia alguém resolver a vala do `ScrollView`, a capacidade 8 volta à mesa — como
  esforço novo.
