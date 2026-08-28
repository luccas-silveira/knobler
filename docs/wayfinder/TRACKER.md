# Tracker do wayfinder — markdown local

A skill `wayfinder` pergunta onde o mapa, os tickets, o bloqueio e a fronteira moram
fisicamente, e manda consultar o documento do tracker. É este.

Aqui eles moram em arquivos markdown dentro de `docs/`, e o painel em `panel/` lê esses
arquivos e desenha o estado. O formato abaixo não é preferência de estilo: é o contrato que
`panel/server/ler.js` interpreta. Fugir dele não dá erro — dá ticket invisível, órfão ou
torto na tela.

Escrito em 2026-08-14, a partir do parser e dos onze tickets já escritos.

## Onde as coisas moram

O mapa é `docs/wayfinder/map-<slug>.md`. O prefixo `map-` é obrigatório e o slug só aceita
minúscula, número e hífen.

Os tickets são `docs/wayfinder/tickets/<NNN>-<slug>.md`. Qualquer pasta dentro de
`docs/wayfinder/` cujo nome comece com `tickets` é varrida, então `tickets-arquivados/`
também entraria na conta.

Só o que está dentro de `docs/` é lido. O painel recusa caminho de fora, inclusive symlink
que aponte para fora.

## O mapa

Título `# Mapa: Nome do mapa`. O prefixo `Mapa: ` some na exibição. Se o nome terminar em
parêntese, o conteúdo dele vira subtítulo — serve para quando o nome não cabe no chip da
tela.

Em qualquer lugar do corpo, `Aberto em 2026-08-13`. Sem essa linha o mapa fica sem data e
cai para o fim da ordenação.

Para fechar, uma linha contendo `**Fechado em 2026-08-13`. Os dois asteriscos fazem parte
do que o parser procura.

As seções são as cinco da skill: Destino, Notas, Decisões até aqui, Ainda não especificado,
Fora de escopo. Duas convenções nasceram do uso e valem manter.

**Ordem de execução**, uma seção extra entre Notas e Decisões até aqui, com a fila dos
tickets abertos e o motivo da ordem. Existe porque o `Blocked by` mostra o que trava, não o
que se decidiu fazer primeiro entre coisas igualmente livres.

A fila precisa estar numa tabela, senão a tela não a enxerga. A primeira célula começa com
o número da fase e um ponto; a segunda traz os ids em negrito:

```
| Fase | Tickets | Por quê |
|---|---|---|
| 1. O que ainda não foi medido | **011** subagente como redutor | … |
| 2. O corte que custa capacidade | **003** quais plugins saem | … |
```

Fase agrupa o que acontece junto; a ordem dentro da fase é a ordem das células.

**Esta tabela é a única coisa que posiciona o gráfico.** A faixa horizontal é a fase, a
coluna é a ordem das células, e nada mais entra na conta: nem `Blocked by`, nem `Status`,
nem `Assignee`. As linhas vêm do `Blocked by` e são desenhadas sempre, do mesmo jeito, sem
olhar estado.

Ticket fora da tabela não aparece no gráfico. Continua no board, na busca e na linha do
tempo. Assim a tela nunca inventa posição que o mapa não escreveu.

Este documento é o formato. **A lógica de montar um mapa que não sai torto está em
[como-construir-um-mapa.md](como-construir-um-mapa.md)**, e é leitura obrigatória antes de
escrever mapa ou ticket: o que fazer de cada fase, por que `Blocked by` é só o pai direto,
por que o fechado nunca sai da tabela, e como conferir o resultado pelo parser em vez de
pelo olho.

**Decisões até aqui não é uma linha por ticket**, na prática. Virou um parágrafo curto com o
achado em negrito, porque o índice serve para decidir se vale abrir o ticket, e "resolvido"
não ajuda nessa decisão. O que o mapa não pode fazer é repetir o conteúdo: o detalhe mora no
ticket, e o mapa aponta.

## O ticket

Título `# 001 — Quebra do piso da sessão`. O número de três dígitos e o travessão dão
identidade ao ticket; sem eles o id vira os três primeiros caracteres do nome do arquivo e o
título passa a ser a linha toda.

Ticket derivado, que nasceu de outro e precisa ficar do lado dele, usa `001.1`. Ordena entre
`001` e `002`.

Depois do título, uma linha em branco e cinco campos colados, sem linha em branco entre
eles, **dentro das primeiras 14 linhas do arquivo**:

```
Map: [Dieta de tokens do setup](../map-custo-de-tokens.md)
Type: `wayfinder:task`
Status: aberto
Assignee: —
Blocked by: 008
```

`Map` precisa conter o link no formato exato `(../map-<slug>.md)`. É por ele que o ticket
acha o mapa; escrito de outro jeito, o ticket fica órfão.

`Type` é a chave de máquina. São seis — `research`, `prototype`, `grilling`, `task`,
`measure`, `fix` — e o painel traduz para PESQUISA, PROTÓTIPO, DECISÃO, TAREFA, MEDIÇÃO e
CONSERTO. Os dois últimos nasceram do uso aqui e foram devolvidos para a skill em
2026-08-14. Tipo fora da tabela de `panel/src/dados.js` aparece cru na tela, o que é o
sinal de que ou o tipo está errado ou a tabela precisa da linha.

`Status` é `aberto` ou `fechado (2026-08-14)`. **A data não é enfeite**: é ela que põe o
ticket na linha do tempo. Fechar sem data tira o ticket de lá e ele vira omissão contada no
topo da tela.

`Assignee: —` é não reivindicado. Qualquer outro valor é a reivindicação, e é o que faz
sessão concorrente pular o ticket.

`Blocked by` aceita ids por vírgula, ou `—` quando não há dependência. Prosa entre
parênteses é ignorada, então `Blocked by: — (001 fechado em 2026-08-05)` conta como
destravado. O travessão manda.

Quatro campos são obrigatórios: `Map`, `Type`, `Status`, `Blocked by`. Faltando um, o ticket
é marcado como **sem cabeçalho** e sai do cálculo da fronteira, em vez de mentir que está
livre. `Assignee` é o único opcional.

O corpo abre com `## Pergunta`. Ao resolver, acrescenta-se `## Resolução` no próprio ticket,
e `## Verificação` quando existe um jeito de refazer a conta.

## Documento auxiliar

Ticket cujo trabalho gera uma medição longa não engorda o ticket: escreve
`docs/wayfinder/medicao-<NNN>-<slug>.md` e linka de dentro da `## Resolução`.

Esses arquivos **não têm cabeçalho de campos** — abrem com `# Medição 009 — Título` e um
parágrafo de método. Não são tickets, são anexos.

O painel classifica por prefixo do nome: `medicao-`, `pesquisa-`, `backlog-` e `baseline-`
ganham rótulo próprio. Prefixo fora dessa lista cai como documento genérico.

## Wayfinding operations

**Criar o mapa.** Escrever `map-<slug>.md` com as seções da skill e a linha `Aberto em`.

**Criar tickets.** Dois passos, sempre. Primeiro os arquivos com `Blocked by: —`; depois,
numa segunda passada, os bloqueios. Id precisa existir antes de ser referenciado.

**Reivindicar.** Trocar `Assignee: —` pelo nome, **antes** de qualquer trabalho.

**Bloquear.** Listar ids em `Blocked by`. Isso decide o estado do ticket — bloqueado ou
livre — e nada mais: o lugar dele no gráfico vem da tabela de fases, só dela.

Houve uma variação em uso — encadear os abertos, cada um bloqueando o próximo, para a
fronteira mostrar um de cada vez. **Não faça mais.** Era preferência disfarçada de
impedimento, e no gráfico virava a diagonal longa que atravessa todas as fases. A ordem já
está na tabela; o `Blocked by` fica para o que trava de verdade, e aponta para a fase
anterior.

A mesma corrente aparece deitada, e é a mais fácil de não ver: cada ticket apontando para o
vizinho da esquerda, dentro da própria fase. Não existe seta dentro de uma faixa — a única
exceção é o derivado `010.1`, que fica na fase do pai por definição. Quem escreve mapa confere
isso com `npm test --prefix panel`, que lê os arquivos reais e reprova seta que pula fase, seta
deitada, ticket sem pai acima e ponta que não destrava ninguém.

**Achar a fronteira.** Não há query: o painel já mostra. Fronteira é ticket aberto,
destravado e com `Assignee: —`. Na tela, a coluna LIVRE.

**Fechar.** Escrever `## Resolução` no ticket, mudar para `Status: fechado (AAAA-MM-DD)` e
acrescentar o parágrafo em Decisões até aqui no mapa, linkando o ticket. O id continua na
tabela de Ordem de execução, na fase onde estava.

**Ruir de escopo.** Fechar o ticket e deixar uma linha em Fora de escopo, com o motivo. Não
entra em Decisões até aqui: fronteira de escopo não é passo da rota.

## O que quebra sem avisar

Cabeçalho abaixo da linha 14. O parser para de procurar ali.

Link do `Map` fora do formato `(../map-<slug>.md)`, que deixa o ticket órfão.

`Status: fechado` sem data, que tira o ticket da linha do tempo.

Título sem o número de três dígitos, que estraga o id e faz o `Blocked by` dos outros deixar
de encontrá-lo.

## Para levar a outro projeto

Não se leva mais à mão. Basta o projeto ter este arquivo em `docs/wayfinder/`: um hook de
início de sessão vê o `TRACKER.md`, traz o `panel/` da fonte e sobe o servidor, e o endereço
aparece na sessão seguinte. Sem `TRACKER.md`, nada acontece — projeto que não usa wayfinder
não ganha painel nem processo.

O que continua sendo do projeto: o `CLAUDE.md` apontando para este documento, o
`map-<slug>.md`, e o `git config core.hooksPath panel/hooks` se quiser o `pre-commit`. Nada
disso o hook faz por você, e o `core.hooksPath` ele nunca fará — ver abaixo.

O porquê e as consequências estão na [ADR-0012](../decisions/0012-painel-por-projeto.md).

### O caminho manual, para quem quer um painel versionado próprio

Painel que o git do projeto rastreia é dono de si: o hook sobe o servidor e não copia nada
por cima. É o caso deste repositório e o do `evolution`. Quem quiser esse arranjo faz o que
está abaixo — que é o procedimento real usado em 2026-08-14, menos os passos que morreram.

1. Copiar `panel/` sem o `node_modules`, e rodar `npm install` no destino.
2. Varrer o `panel/README.md` atrás de número e nome do repositório de origem. Contagem de
   documentos e referência a design system viajam junto e passam a mentir no destino.
3. Copiar este `TRACKER.md` para `docs/wayfinder/`.
4. Apontar o `CLAUDE.md` do projeto para ele, em duas linhas. Sem esse ponteiro a próxima
   sessão não sabe que o documento existe e volta a improvisar o formato.
5. Instalar o hook: `git config core.hooksPath panel/hooks`. **Isto desliga os hooks de git
   que o projeto já tem**, porque `core.hooksPath` substitui o diretório inteiro, não
   acrescenta a ele. É por isso que o hook automático não executa este passo: ele não tem
   como saber o que estaria desligando.
6. Criar o `map-<slug>.md` e rodar o teste. Zero ticket já é um estado válido.

Um passo saiu da lista: trocar a marca em `src/app.jsx` e `index.html`. O nome do projeto
passou a ser lido da raiz apontada e servido junto com o resto, então cada painel mostra o
nome certo sem ninguém editar nada.

O que não viaja: os documentos de `docs/`, que são do projeto de origem.

## Como verificar

```
npm test --prefix panel
```

Falha se qualquer ticket estiver com cabeçalho incompleto ou usar um `Type` que a tela não
sabe traduzir.

Não precisa lembrar de rodar: o `pre-commit` em `panel/hooks/` roda sozinho quando o commit
toca `docs/` ou `panel/`, e barra o commit se quebrar. Ele não vem instalado — `core.hooksPath`
é configuração local do clone:

```
git config core.hooksPath panel/hooks
```

Para ver: `cd panel && npm run dev`, em `http://localhost:4700`. A tela recarrega sozinha
quando um arquivo de `docs/` muda.
