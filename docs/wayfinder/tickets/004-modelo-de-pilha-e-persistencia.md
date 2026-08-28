# 004 — O modelo de pilha e a persistência

Map: [Shelf de arquivos — empilhamento, ordem e saída](../map-shelf-de-arquivos.md)
Type: `wayfinder:task`
Status: fechado
Assignee: claude
Blocked by: 003

## Pergunta

A shelf hoje é `[URL]` — uma lista plana de caminhos, gravada em `shelfItems`
no UserDefaults como array de strings. Uma prateleira que mistura itens soltos
e pilhas não cabe nessa forma.

O que este ticket entrega:

1. **O tipo** que representa uma entrada da shelf, sabendo ser um arquivo só ou
   um conjunto. A capacidade continua **8 entradas**, e uma pilha ocupa uma.
2. **A persistência** — como isso vai pro UserDefaults, e o que acontece com a
   prateleira de quem já tem `shelfItems` gravado no formato antigo. Migrar ou
   descartar é decisão deste ticket.
3. **O que quebra junto**: `tools/shelfdropcheck.swift` lê o modelo, e a receita
   de captura da imagem da prateleira nos docs escreve `shelfItems` via
   `defaults` — trocar o formato invalida as duas. A skill `snapshot-ui` tem a
   receita.

Nada de UI aqui. As três frentes da fase 3 constroem sobre este modelo, e é por
isso que ele vem sozinho.

## Resolução

**O tipo, a persistência e a migração entregues; zero UI, como o ticket pedia.**
A prateleira continua se comportando exatamente como antes — nada no app
constrói uma entrada com mais de um arquivo, e é essa regra que torna cada call
site adaptado provadamente idêntico ao de hoje.

`ShelfEntry` é uma struct com `[URL]`, em `Knobler/ShelfOrdem.swift`, e não um
enum de dois casos: o enum obrigaria um `switch` em cada consumidor só pra
reconstituir "os arquivos desta entrada", e `urls.count > 1` dá o discriminante
de graça. A identidade é derivada do conteúdo e **não** persiste — a grade já era
`id: \.self` sobre a URL, então isso é o status quo. Nenhum arquivo novo, logo
nenhum registro manual em `tools/notchview-fontes.txt` nem em `tools/check.sh`,
e nenhum `xcodegen generate`.

A persistência ficou na **mesma chave** `shelfItems`, agora `[[String]]` nativo
do plist — não JSON, pra receita de captura da prateleira continuar escrevível
com `defaults write`. A leitura discrimina pelo tipo do objeto cru, no
precedente do `NotchSectionOrder.sanear`.

**A migração inverte, e isso apaga um custo que o 003 tinha aceitado.** Nenhuma
release contém o 003, então todo `shelfItems` gravado em máquina de usuário está
na ordem antiga; ler, inverter e regravar significa que ninguém vê a prateleira
com a idade trocada. `CHANGELOG.md` e a entrada do 003 no mapa foram corrigidos,
que afirmavam o custo.

A peça que quase passou batido: **`didSet` não roda em atribuição dentro do
`init`**. Sem uma gravação explícita ali, a migração ficaria só em memória e o
array plano seria relido e reinvertido a cada lançamento.

`tools/shelfordemcheck.swift` cresceu pra 29 asserções: as regras de ordem do
003 na forma nova, capacidade contando vagas, dedupe entre entradas, round-trip
da persistência, migração do formato plano, filtro de arquivo que sumiu e lixo
no UserDefaults. **Ele falha contra o código de antes** — compilado contra o
`ShelfOrdem.swift` anterior dá 78 erros, porque a assinatura de `inserir` mudou e
o tipo não existia.

**Correção ao enunciado:** o ticket diz que `tools/shelfdropcheck.swift` lê o
modelo. Não lê — ele só exercita `ShelfDrop`, `LinkBrowser` e os conversores, e
não precisou de uma linha.

`./tools/check.sh` fecha em **39 checks verdes**, `./tools/snapshot.sh` regenera
e o build Debug do app passa. **Nada disso prova a tela**: a prateleira não
renderiza offscreen, e ver a pilha no app rodando é o 009.
