# Pesquisa 002 — Shelfs de arquivos do macOS

Levantamento feito em **2026-08-28**. Consultei, nesta ordem: as páginas oficiais
de Yoink (site, help, tips, notas de versão), Dropover (site, FAQ, Pro Tips,
notas da 5.2.5), Dropzone 4 (blog e fórum de suporte da Aptonic) e Unclutter
(página do painel Files); as descrições e as notas de versão da Mac App Store via
`itunes.apple.com/lookup`; as reviews da Mac App Store via o feed RSS
`itunes.apple.com/us/rss/customerreviews` (100 reviews de Yoink, 50 de Dropover,
50 de Dropzone 4 — o feed devolveu 0 entradas para Unclutter e para Dropzone 5);
a resenha da Macworld sobre o Yoink; **o próprio bundle do Yoink 3.7.6**, baixado de `eternalstorms.at/dl/Yoink.zip` e lido com `strings` nos `.nib` e `.strings` de preferências; e o código-fonte de **OpenYoink**, um clone
open-source de shelf com Dynamic Island, clonado e lido localmente.

Duas limitações a registrar de saída: **o reddit.com não é acessível pela
ferramenta de busca deste ambiente** (`400 — domains not accessible to our user
agent`), então nenhuma afirmação abaixo vem de r/macapps; e o feed RSS da App
Store devolve, no máximo, as reviews mais recentes da loja dos EUA — os números
citados são sempre sobre esse recorte, com o denominador nomeado.

Onde a resposta não apareceu em fonte primária, está escrito **não encontrado**.
Não deduzi nada do comportamento provável.

## As três perguntas obrigatórias

| | Yoink 3.7.6 | Dropover 5.2.5 | Dropzone 4 (Drop Bar) | Unclutter 2.2.18 | OpenYoink (open-source) |
|---|---|---|---|---|---|
| **1. Empilhamento** | **Automático** (e desligável: caixa "Combine multiple files to a stack"). "Multiple files dragged to Yoink at once are condensed into a Stack" ([App Store](https://apps.apple.com/us/app/yoink-better-drag-and-drop/id457622435)). Desempilha com um botão ao lado da pilha ([Macworld](https://www.macworld.com/article/216280/yoink_offers_a_shelf_for_temporarily_stashing_files_and_content.html)) — no bundle, os comandos "Split up Stack", "Merge Selected Items to a Stack" e "Merge all Items to a Stack". **Tirar um arquivo só:** o texto de ajuda do próprio app diz *"If you need one particular file inside a Stack, you can split it up"* — ou seja, **não dá**: desmancha a pilha inteira. | **Não se aplica no mesmo formato**: o contêiner é a *shelf* inteira, e um drop de N arquivos vira N itens dentro dela ([Pro Tips #8](https://dropoverapp.com/tips)). Não encontrei pilha dentro da shelf. **Tirar um arquivo só:** sim, ⌘-clique seleciona itens individuais e arrasta só eles. | **Manual.** "You can combine files in Drop Bar into stacks so they travel together by dragging files in Drop Bar onto each other" ([Aptonic](https://aptonic.com/blog/introducing-floating-drop-bar-in-dropzone-4)); a pilha pode ser nomeada ([blog](https://aptonic.com/blog/drop-bar-improved-with-stack-naming-and-reordering)). **Tirar um arquivo só de dentro de uma pilha: não encontrado.** | **Não tem pilha.** O painel Files é uma lista de arquivos ([Unclutter Files](https://unclutterapp.com/panels/files/)). | **Manual.** `ShelfStore.makeStack(from:)` junta a seleção; `unstack(_:)` desfaz e devolve os filhos na posição da pilha. **Tirar um arquivo só:** sim — `ShelfActionRunner` filtra `stack.children` pela seleção do filho, e `ShelfItemCard` expande a pilha para seleção múltipla. |
| **2. Ordem** | **Não encontrado.** Nem o site, nem os tips, nem as notas de versão dizem em que ponta o item novo entra, nem o que acontece ao soltar de novo um arquivo que já está lá. | **Não encontrado.** A doc só diz que dá para "reorder files directly on the shelf" ([site](https://dropoverapp.com/)). | **Não encontrado** para a ponta de entrada. A reordenação manual existe: "the ability to reorder items in Drop Bar by dragging them around inside the Dropzone grid" ([blog](https://aptonic.com/blog/drop-bar-improved-with-stack-naming-and-reordering)). | **"Newest items appear at the top, but you can also rearrange them your way"** ([Unclutter Files](https://unclutterapp.com/panels/files/)). Único caso documentado. | **Medido no código:** `add(_:at:)` usa `index ?? items.count` — o item novo vai para o **fim** da lista, salvo posição explícita de drop. Não há deduplicação por caminho: soltar de novo cria uma segunda entrada. |
| **3. Saída** | **Sai por padrão, e é opção.** "Dragging an item off the shelf removes the item from the shelf" ([Macworld](https://www.macworld.com/article/216280/yoink_offers_a_shelf_for_temporarily_stashing_files_and_content.html)); a caixa **"Remove items when dragged out"** existe (medida no `preferences.nib` do bundle 3.7.6, aba Advanced, ligada a `values.autoRemoveAfterDrag`). **Copiar vs. mover:** segue o Finder — ⌥ força cópia, ⌘ força movimento ([site oficial](https://eternalstorms.at/yoink/mac/)). | **Sai por padrão, e virou opção na 5.2.5:** "Added an option to keep shelves open after dragging items out, available in Settings under Shelf Interaction" (notas da 5.2.5). ⇧ durante o arraste também mantém a shelf ([Pro Tip #10](https://dropoverapp.com/tips)). **Distingue copiar de mover explicitamente:** "the file is moved by default on macOS. To copy the file instead, hold the Option key" ([FAQ](https://dropoverapp.com/faq)); volume diferente copia; ⌘ força mover; "Always copy items when dragging out" em Settings → Shelf Interaction → Advanced. | **Sai por padrão, com trava por item:** "Dragging items out of Drop Bar and dropping them into another app should remove them from Drop Bar unless they have been locked" ([fórum Aptonic, 2024-09-04](https://forums.aptonic.com/topic/602/dragged-out-items-not-being-removed-from-stack/)). Copiar vs. mover: não encontrado em fonte oficial. | **Modelo diferente:** o arquivo é *movido de verdade* para o armazenamento do app. "Like in Finder, the default operation when you drop files is MOVE"; ⌥ copia, ⌘⌥ cria alias ([Unclutter Files](https://unclutterapp.com/panels/files/)). | **Fica por padrão.** `DragOutRemovalPolicy` tem `keep`/`remove`/`ask`, e o dicionário de defaults registra `.keep`. |

## Por ferramenta

### Yoink (Eternal Storms, 3.7.6, one-time €9,99)

Empilhamento automático é uma decisão de produto antiga e anunciada na própria
descrição da loja: *"Multiple files dragged to Yoink at once are condensed into a
Stack, making it easy to drag them out together"*. A Macworld, na resenha da
versão que introduziu o recurso, descreve os dois lados: *"an option to display a
dragged group of files as a single stack in the shelf; you can then drag that
stack elsewhere to move all the files together. A button next to a stack lets you
manually split the stack into its individual items."* Ou seja: pilha automática
no drop, desempilhamento manual por botão, e a pilha inteira arrasta junto.

A mesma resenha responde a saída sem ambiguidade: *"Dragging an item off the
shelf removes the item from the shelf, but you can also remove an item by
clicking the X button next to its icon — the original item (in the Finder) is
unaffected."* A remoção é o padrão, mas existe a caixa "Remove items when dragged
out" na aba Advanced das Preferências para desligá-la. Além disso o app guarda
histórico do que saiu: o site oficial diz que um *long-press* no atalho global
serve para *"recall files you previously moved out of Yoink"* — a rede de
segurança que torna a remoção agressiva aceitável.

Copiar vs. mover: o site é explícito — *"When dragging files out of Yoink, it
behaves the same way as Finder when it comes to moving or copying files"*, com ⌥
para forçar cópia e ⌘ para forçar movimento. Yoink **não** anuncia só `.copy`.

Reviews (100 mais recentes da loja dos EUA, coletadas em 2026-08-28): 85 de 5
estrelas, 7 de 4, 1 de 3, 3 de 2 e 4 de 1. Das 8 reviews de 1–3 estrelas, **3
reclamam de sincronização entre macOS e iOS** (a mais dura: "No iCloud Sync
between macOS and iOS"), 2 reclamam de bug funcional (arquivos que aparecem como
pastas; "Files stuck in Yoink, won't come out"), 1 do diálogo de boas-vindas
repetido e 1 de a janela bloquear a tela.

### Dropover (Tappable, 5.2.5, free + IAP one-time)

Dropover não empilha dentro da shelf: a **shelf é a unidade**, e você cria várias.
O Pro Tip #8 mostra o modelo — *"hold Command while clicking items to select them
individually… After selecting multiple items, you can drag only those files out of
the shelf"*. Seleção múltipla substitui a pilha.

A saída é a decisão mais informativa deste levantamento. Historicamente, arrastar
para fora fecha a shelf; até a versão 5.2.5 a única saída era segurar ⇧ (*"Hold
Shift while dragging items out to keep the shelf open afterward. This is useful
when you want to drag the same items to multiple places"* — Pro Tip #10). As notas
da 5.2.5 registram a mudança: *"Added an option to keep shelves open after
dragging items out, available in Settings under Shelf Interaction."* Ou seja: a
remoção automática incomodou o suficiente para virar preferência.

O FAQ é a fonte mais precisa que achei sobre copiar vs. mover em qualquer destas
ferramentas: *"When you drag a file from Finder onto Dropover's shelf, Dropover
only retains a reference to the file. It does not copy or move the file. When you
drag an item from the shelf to your destination, the file is moved by default on
macOS. To copy the file instead, hold the Option key… Files destined for a
different volume or disk will be copied by default. To force a move in this case,
hold the Command key."* E há a preferência "Always copy items when dragging out"
em Settings → Shelf Interaction → Advanced.

Reviews (50 mais recentes, EUA): 45 de 5 estrelas, 1 de 4, 1 de 2, 3 de 1. Das 4
de 1–2 estrelas, **2 são sobre o Dropover Cloud e o suporte** ("Non existing
support"; "Dropover Cloud almost NEVER functions correctly"), 1 sobre o app
morrer sozinho no Sequoia 15.7.1, e **1 é exatamente sobre empilhamento**: *"When
two or more files are moved from the shelf to their desired location, they appear
as a single file. This happens because the files are stacked behind each other
instead of being spread out, making it nearly impossible to separate them unless
you put them back on the shelf and take them out one by one."*

### Dropzone 4 (Aptonic, 4.80.76, assinatura)

Dropzone é uma **grade de ações**; a shelf é um componente dela, o Drop Bar. O
empilhamento é 100% manual: você arrasta um item do Drop Bar sobre outro, e a
pilha pode ganhar nome (⏎ ou botão direito → "Name Stack") e ser reordenada
arrastando dentro da grade.

Sobre a saída, o achado mais relevante veio do fórum oficial e vale para o
ticket 001 deste mapa: em 2024-09-04 um usuário reporta que os itens pararam de
sair do Drop Bar ao serem arrastados. O suporte responde com a regra —
*"Dragging items out of Drop Bar and dropping them into another app should remove
them from Drop Bar unless they have been locked"* — e em 2024-09-06 conclui:
*"I've just tested and found this is a bug with Drop Bar under Sequoia"*,
corrigido na 4.80.20. **A detecção de "o arraste terminou com sucesso" quebrou
numa atualização do macOS numa shelf comercial madura, e ninguém percebeu até o
usuário reportar.** O "lock" por item é o equivalente do Dropzone à opção de
manter.

Reviews (50 mais recentes, EUA): 20 de 5 estrelas, 8 de 4, 2 de 3, 5 de 2, 15 de
1 — de longe a pior distribuição das três. **17 das 50 reviews mencionam
assinatura/mensalidade/aluguel**, e **14 das 20 reviews de 1–2 estrelas** são
sobre o modelo de cobrança, não sobre o produto. É ruído para as três perguntas
obrigatórias, mas é o dado de mercado mais nítido do levantamento.

### Unclutter (2.2.18)

Modelo diferente das outras: não é uma shelf de referências, é um **armazenamento
de verdade**. A página oficial do painel Files diz *"Like in Finder, the default
operation when you drop files is MOVE"*, com ⌥ para copiar e ⌘⌥ para criar alias
— o arquivo original sai do lugar. Por isso as perguntas 1 e 3 quase não se
aplicam: não há pilha, e o item não "sai" ao ser arrastado, porque ele mora ali.

É, porém, a **única fonte oficial que responde a pergunta 2** em qualquer das
ferramentas: *"Newest items appear at the top, but you can also rearrange them
your way."* Mais novo primeiro, com reordenação manual por cima.

O feed de reviews da App Store devolveu 0 entradas para o id 695406827 nas três
páginas consultadas; não tenho números de review para esta ferramenta.

### OpenYoink (open-source, SwiftUI + AppKit, notch/Dynamic Island)

Incluído porque é a única shelf cujo comportamento eu pude **medir em vez de
ler**, e porque o formato — shelf no notch, SwiftUI + AppKit — é o do Knobler.
Do código:

- `ShelfStore.add(_:at:)` e `add(contentsOf:at:)` calculam
  `index ?? items.count`: **item novo vai para o fim**, a não ser que o drop
  indique posição. Não há checagem de caminho repetido em nenhum caminho de
  importação, então **soltar de novo um arquivo já presente cria uma segunda
  entrada**, não promove a existente.
- Empilhamento **manual**: `makeStack(from ids:)` sobre a seleção, `unstack(_:)`
  para desfazer, com `ShelfItem.children` — pilhas e itens soltos convivem na
  mesma lista, exatamente como o mapa 002 propõe.
- Saída: `SettingsStore.DragOutRemovalPolicy` tem três casos, `keep`, `remove` e
  `ask`, e o dicionário de defaults registra **`.keep`** — o padrão de fábrica é
  o item ficar.

## Levantamento amplo

### O que os usuários elogiam

O elogio é a shelf existir, não como ela se comporta. Contei, nos textos das
reviews de 5 estrelas: **0 das 85 de Yoink e 0 das 45 de Dropover mencionam
"stack" ou "pile"**; **0 e 0 mencionam "disappear", "removed from" ou "vanish"**;
e "order/sort/newest/oldest" aparece em 1 das 85 e 2 das 45, nos dois casos fora
do sentido de ordenação da lista. Os doze depoimentos que a própria Dropover
escolheu para a home seguem a mesma linha ("It just works", "Game changer",
"This makes moving files easier than it's ever been"). **As três perguntas deste
mapa são invisíveis quando estão certas e viram review de 1 estrela quando estão
erradas.**

O segundo elogio recorrente é a integração com o macOS: Services, Quick Action,
Share extension, Shortcuts, Quick Look. As quatro ferramentas investem nisso.

### O que os usuários reclamam

Por ordem de peso medido:

1. **Modelo de cobrança** — 17 das 50 reviews de Dropzone 4, e 14 das 20 de 1–2
   estrelas. Não é problema de produto e não afeta o Knobler, mas domina a
   percepção da ferramenta.
2. **Quebra em atualização do macOS** — Dropzone perdeu a remoção-ao-arrastar no
   Sequoia (fórum, 2024-09); uma review de 1 estrela de Dropover ("Stopped
   working after Golden Gate Beta", 2026-07-29) e outra de instabilidade no
   Sequoia. Duas das três ferramentas comerciais têm registro público de
   regressão de drag & drop causada pelo sistema.
3. **Sincronização entre dispositivos** — 3 das 8 reviews de 1–3 estrelas de
   Yoink.
4. **O arraste de vários arquivos chegar empilhado no destino** — 1 review de
   Dropover (2025-10-16). Um caso só, mas descreve exatamente o custo de errar o
   payload de uma pilha, e por isso vale citar.

### O que falta em todas

- **A ordem não está documentada em lugar nenhum.** Quatro ferramentas, e só a
  Unclutter escreve em que ponta o item novo entra. Nenhuma das quatro documenta
  o que acontece ao soltar de novo um arquivo que já está na shelf. Isso não é
  descuido de redação: é sinal de que ninguém tratou isso como decisão.
- **A remoção ao arrastar não convergiu.** Yoink remove com opção de não
  remover; Dropover fechava e ganhou a opção de manter na 5.2.5; Dropzone remove
  a não ser que o item esteja travado; OpenYoink mantém por padrão. **Todas as
  quatro deixam isso configurável.** Nenhuma trata como comportamento fixo.
- **Nenhuma distingue "aceitou" de "recusou" de forma documentada.** Nem o
  Dropzone, que é quem mais chegou perto, sabia que a própria detecção tinha
  quebrado no Sequoia até um usuário reclamar.

### Onde isso encosta nas decisões travadas do mapa

- **Empilhamento automático** (mapa: "um drop de vários vira uma entrada só"):
  Yoink faz exatamente isso; Dropzone e OpenYoink empilham só manualmente;
  Dropover não empilha. **Não há convergência de três ferramentas contra a
  decisão**, mas também não há a favor — a decisão do mapa segue a rota do Yoink,
  que é a mais bem avaliada das quatro.
- **Ordem** (mapa: "mais novo na esquerda"): a única fonte primária que fala do
  assunto, a Unclutter, põe o mais novo primeiro — a favor da decisão. Para as
  outras três, **não encontrado**. O comportamento medido do OpenYoink (item novo
  no fim) é contrário, mas é uma implementação hobby, não uma escolha de produto
  documentada.
- **Saída** (mapa: "o item some ao ser arrastado pra fora com sucesso"): **as
  quatro ferramentas fazem disso uma opção.** Esta é a única convergência real do
  levantamento. Recomendação: manter *sair* como padrão de fábrica — é o que
  Yoink, Dropover e Dropzone entregam de fábrica —, mas não travar o
  comportamento no código sem prever o ponto onde a opção entra.
- **Anunciar só `.copy`** (mapa): as três ferramentas comerciais que documentam o
  ponto — Yoink, Dropover e Unclutter — fazem o oposto e **movem por padrão**,
  seguindo o Finder, com ⌥ para copiar. A decisão do mapa é deliberadamente mais
  conservadora que o mercado; vale saber que ela diverge de três ferramentas
  boas, e que a expectativa de quem vem do Yoink ou do Dropover é mover.

## Fontes

1. [Yoink — site oficial](https://eternalstorms.at/yoink/mac/) — "behaves the same way as Finder"; ⌥/⌘; "recall files you previously moved out of Yoink".
2. [Yoink — Usage Tips](https://eternalstorms.at/yoink/mac/tips/) — os 16 tips; #1 Force Copy/Force Move, #10 Bring back previously removed files.
3. [Yoink — Mac App Store (descrição via itunes lookup, id 457622435)](https://apps.apple.com/us/app/yoink-better-drag-and-drop/id457622435) — "condensed into a Stack".
4. [Yoink — notas de versão](https://updates.eternalstorms.at/notes/YNKMC/) — histórico até 3.7.6 (2026-07-31).
5. Yoink 3.7.6 — bundle baixado de `https://eternalstorms.at/dl/Yoink.zip` em 2026-08-28: `Contents/Resources/en.lproj/preferences.nib` (caixas "Combine multiple files to a stack" / `values.createClusters` e "Remove items when dragged out" / `values.autoRemoveAfterDrag`, aba Advanced) e `Localizable.strings` ("Split up Stack", "Merge all Items to a Stack", e o texto "When you drag multiple files to Yoink, they're turned into a Stack… If you need one particular file inside a Stack, you can split it up").
6. [Macworld — Yoink offers a shelf for temporarily stashing files and content](https://www.macworld.com/article/216280/yoink_offers_a_shelf_for_temporarily_stashing_files_and_content.html) — pilha, botão de split, remoção ao arrastar.
7. [Dropover — site oficial](https://dropoverapp.com/) — recursos, 4.9/5 de 7,7 mil avaliações.
8. [Dropover — FAQ](https://dropoverapp.com/faq) — referência e não cópia; mover por padrão; ⌥ copia; volume diferente copia; "Copy Items to Destination".
9. [Dropover — Pro Tips](https://dropoverapp.com/tips) — #8 seleção múltipla, #9 copy or move, #10 Shift mantém a shelf, #13 esvaziar a shelf.
10. Dropover — notas da versão 5.2.5 (via `itunes.apple.com/lookup?id=1355679052`) — "option to keep shelves open after dragging items out".
11. [Aptonic — Introducing Floating Drop Bar in Dropzone 4](https://aptonic.com/blog/introducing-floating-drop-bar-in-dropzone-4) — empilhar arrastando um item sobre outro; lock.
12. [Aptonic — Drop Bar improved with stack naming and reordering](https://aptonic.com/blog/drop-bar-improved-with-stack-naming-and-reordering) — nomear pilha, reordenar arrastando.
13. [Fórum Aptonic — "Dragged out items not being removed from stack" (2024-09)](https://forums.aptonic.com/topic/602/dragged-out-items-not-being-removed-from-stack/) — a regra da remoção e o bug do Sequoia, corrigido na 4.80.20.
14. [Unclutter — painel Files](https://unclutterapp.com/panels/files/) — "the default operation when you drop files is MOVE"; "Newest items appear at the top".
15. [OpenYoink no GitHub](https://github.com/MuQY1818/OpenYoink) — `OpenYoink/Services/ShelfStore.swift` (inserção, `makeStack`, `unstack`) e `OpenYoink/Settings/SettingsStore.swift` (`DragOutRemovalPolicy`, default `.keep`).
16. Feed RSS de reviews da Mac App Store (EUA), coletado em 2026-08-28: `https://itunes.apple.com/us/rss/customerreviews/page=N/id=<id>/sortby=mostrecent/json` para 457622435 (Yoink, 100 entradas), 1355679052 (Dropover, 50) e 1485052491 (Dropzone 4, 50).
