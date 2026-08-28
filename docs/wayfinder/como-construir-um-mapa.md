# Como construir um mapa do wayfinder

Um mapa mal construído não dá erro. Ele dá um grafo torto, uma fila que ninguém segue e uma
pergunta re-discutida três sessões depois. Este documento é a **lógica**; o formato — o que o
parser do painel lê — está em [TRACKER.md](TRACKER.md), e é leitura obrigatória antes desta.

Escrito em 2026-08-17 no repositório `evolution`, a partir de uma sessão inteira de acerto no
mapa "Escolher o número de saída na automação", e trazido para cá no mesmo dia. Cada regra abaixo tem o erro concreto que a gerou; nenhuma é preferência
de estilo. Quando uma regra citar um caso, o caso é real e está nos arquivos deste diretório.

## O grafo é o teste do mapa

O painel desenha os tickets em faixas: uma faixa por fase, de cima para baixo, com os
`Blocked by` como setas. **Se o desenho fica feio, o mapa está errado** — não o desenho. Três
sintomas e o que cada um denuncia:

| O que se vê | O que está errado |
|---|---|
| Um ticket que existe some do desenho | Ele está fora da tabela de fases |
| Um ticket sumiu ao ser fechado | Alguém o tirou da tabela ao fechar; ele volta para a fase onde foi feito |
| Nós flutuando sem seta nenhuma | O mapa não pensou a sequência; ninguém depende de ninguém |
| Setas longas cruzando o desenho | `Blocked by` listando bloqueio transitivo |
| Uma diagonal descendo o mapa inteiro, um nó por fase | A fila foi encadeada ticket a ticket, e cada fase ficou com um id só |
| Setas de lado, ligando vizinhos dentro da mesma faixa | A mesma corrente, dentro da fase: `Blocked by` apontando para quem só vem antes na ordem |

**Cada seta deve descer exatamente uma fase — nem mais, nem menos.** Quando pula, uma de duas
coisas é verdade: o bloqueio é redundante, ou a fase está errada. Quando não desce nenhuma, ligando
dois tickets da mesma faixa, é sempre a primeira: quem vem antes na fila não é quem trava, e a
tabela já diz a ordem.

O reflexo certo diante de um salto é **subir o pai**, não empurrar o filho para baixo. Ticket que
pode começar hoje pertence à primeira fase, e é isso que a fase diz: o que já dá para pegar. Foi
assim nos dois casos que geraram esta regra — o `004` deste repositório subiu para a fase 1, e no
mapa de templates a medição e as quatro sessões independentes acabaram na mesma faixa, porque é
verdade que qualquer uma delas pode ser a próxima.

Exceção existe, mas é declarada em código, no `saltosAceitos` do teste, com o motivo no mapa. Uma.
Não sete.

## Fechar não move nem apaga

O ticket fechado **continua na tabela**, na fase em que foi feito. É essa tabela, e só ela,
que posiciona o desenho: tirar o id de lá ao fechar apaga o ticket da tela e reembaralha o
mapa que todo mundo já conhecia. Fechar muda a cor do marcador e mais nada.

Pela mesma razão, nenhum outro campo entra no posicionamento: `Status`, `Assignee` e o
próprio `Blocked by` decidem a cor e a coluna do board, nunca a faixa.

## Fase é o que acontece junto

De dois a quatro ids por fase desenham uma árvore. Um id por fase desenha um fio comprido e
joga a largura da tela fora.

Daí sai uma proibição: **não encadeie os abertos, um bloqueando o próximo, para a fronteira
mostrar um de cada vez.** Isso é preferência disfarçada de impedimento, e ela se escreve no
desenho como a diagonal longa. Quem diz a ordem é a fase; o `Blocked by` diz o impedimento
real.

## `Blocked by` é só o pai direto

Bloqueio transitivo não se lista. O ticket 007 daquele mapa nasceu com
`Blocked by: 003, 004, 005, 006` e desenhava quatro curvas longas atravessando o grafo. Só
`006` bastava: o 006 já espera o 004 e o 005, e o 005 espera o 003. Mesma semântica, um quarto
das setas, e o desenho vira árvore.

Escreva no corpo do ticket que os outros valem por transitividade. É a linha que impede
alguém de "consertar" a lista de volta.

## A cadeia tem que ser verdade, não enfeite

Ticket órfão é sinal de que ninguém pensou a sequência. Mas a cura não é inventar dependência
para o desenho fechar. No mapa citado, `001 → 002 → {003, 004}` é história literal: o 002 só
existiu porque o 001 derrubou a premissa, e o 003 e o 004 só puderam ser escritos depois de o
002 escolher o mecanismo. Se a frase "o filho não podia começar antes de o pai fechar" não for
verdadeira, não escreva a seta.

Bloqueador fechado não segura ninguém: o painel calcula LIVRE por bloqueador **resolvido**,
não por lista vazia. Então registrar a história real não trava a fronteira.

## O número do ticket é a ordem de fazer

Quando a ordem muda, renumere. Uma lista cuja numeração não bate com a fila obriga quem lê a
manter duas ordens na cabeça.

O custo é real e é seu: renomear os arquivos em duas passadas (um diretório temporário evita
colisão), reescrever todo `Blocked by`, todo título `# NNN — `, e todos os links cruzados
entre tickets, mapa e documentos auxiliares. Faça enquanto nada foi commitado e nada de fora
aponta para os ids. Depois disso, o preço sobe e a identidade estável passa a valer mais.

O derivado `001.1` serve para o ticket que nasce colado a outro **sem mexer na fila**. Se ele
virou um passo próprio da rota, é um número inteiro.

## A fase 1 é sempre "o que chega de fato"

Medir a realidade antes de decidir em cima dela. No mapa citado, o grilling travou um
mecanismo inteiro sobre a premissa de que a mensagem de automação chegava ao nosso webhook.
O ticket 001 mediu e ela não chegava. Uma sessão de pesquisa salvou o mapa de entregar uma
spec de algo que não funcionaria.

Se a fase 1 não é medição, pergunte que premissa o mapa está assumindo sem ter olhado.

## O ticket que pode matar o mapa vem antes do que desenha o detalhe

Ordene por risco de invalidar, não por ordem lógica de leitura. "A ação chega na subconta?"
vem antes de "quais campos a ação tem", porque um "não" na primeira joga a segunda fora
inteira. Escreva esse motivo na coluna **Por quê** da tabela — é ela que impede a próxima
sessão de reordenar por conveniência.

## Premissa derrubada abre um ticket de decisão, não uma reescrita silenciosa

Quando a pesquisa mata a premissa de uma decisão já travada, não troque o mecanismo no
caminho. Abra um ticket de decisão que registre, no mesmo arquivo:

1. Qual premissa caiu e como se mediu.
2. As rotas em disputa, cada uma com o custo real.
3. A escolhida, e por quem.
4. **O que sobreviveu** da decisão anterior — quase sempre há três ou quatro decisões que não
   eram sobre o mecanismo e continuam valendo inteiras.
5. O que morreu junto, com os ids dos tickets que fecham por ruína de escopo.

Sem o item 4 a próxima sessão re-discute o que já estava resolvido. Sem o item 5 ficam
tickets abertos respondendo perguntas que não existem mais.

## Decisão de produto é do usuário

Se a pesquisa abre uma rota melhor que a travada num grilling, apresente as duas com o custo
de cada uma e **pergunte**. Trocar sozinho é decidir por ele com informação que ele não viu.
Recomende — não decida.

## Confira como o painel lê, não como você escreveu

`node --test server/ler.test.js src/dados.test.js` testa fixtures. Ele passa igual antes e
depois de você estragar um mapa. A verificação de verdade é carregar o parser sobre os
arquivos reais:

```
cd panel && node -e "
Promise.all([import('./server/ler.js'), import('./src/dados.js')]).then(([{lerTudo},{ticketsDoMapa}]) => {
  const e = lerTudo();
  const ts = ticketsDoMapa(e, 'map-SEU-SLUG');
  const fase = new Map(ts.map(t => [t.id, t.fase]));
  console.log('sem fase (viram faixa órfã):', ts.filter(t => typeof t.fase !== 'number').map(t => t.id));
  console.log('sem cabeçalho:', ts.filter(t => t.faltando.length).map(t => t.id + ' falta ' + t.faltando));
  for (const t of ts) console.log(t.id, 'fase', t.fase, '|', t.estado);
  for (const t of ts) for (const p of t.bloqueadoPor) {
    const salto = fase.get(t.id) - fase.get(p);
    console.log(' ', p, '→', t.id, fase.get(p) + '→' + fase.get(t.id), salto === 1 ? 'ok' : salto === 0 ? 'MESMA FASE' : 'PULA ' + (salto - 1));
  }
});
"
```

Quatro coisas têm que sair limpas: nenhum ticket sem fase, nenhum sem cabeçalho, nenhum
`Blocked by` apontando para id inexistente, nenhum `PULA` e nenhuma `MESMA FASE`. A seta que liga
dois tickets da mesma faixa é o mesmo defeito da que pula, e é a mais fácil de não ver: foi assim
que um mapa inteiro saiu encadeado de lado, com o `Blocked by` de cada ticket apontando para o
vizinho da esquerda, que só vem antes na ordem.

**Isso não depende mais de alguém lembrar de rodar.** `server/ler.test.js` faz as três
checagens de forma sobre os arquivos reais, e o `pre-commit` do projeto o executa:

- seta que pula fase — bloqueio transitivo, ou fase errada;
- ticket fora da primeira fase **sem nenhum pai** — o bloco que flutua sem nada entrando nele;
- ticket fora da última fase que **não destrava ninguém** — a ponta solta.

As três já tinham sido escritas aqui em prosa e reincidiram assim mesmo, em dois mapas
diferentes. Prosa não segura regra de forma; o teste segura.

A exceção legítima existe, e é declarada em código, não tolerada em silêncio: o teste tem dois
conjuntos, `saltosAceitos` e `pontasAceitas`, e o que não está lá dentro reprova. Pôr uma entrada
custa escrever o motivo no mapa e a linha no teste — deliberadamente mais caro do que corrigir a
fase, que é o que resolve quase todo caso.

`pontasAceitas` nasceu do mapa com **dois desfechos**: quando o mapa entrega duas coisas que sobem
separadas, dois tickets não destravam ninguém, e inventar a seta entre eles mentiria sobre a ordem.
`saltosAceitos` continua vazio nos dois repositórios, e o caso que o criou é instrutivo — salto que
insiste costuma ser fase errada esperando um corte.

## As seções do mapa fazem trabalho diferente

- **Destino** — o que existe quando o mapa fecha, e o que ele explicitamente não faz.
- **Notas** — as decisões travadas, cada uma com o porquê em uma frase. Separe as que
  sobrevivem a uma troca de mecanismo das que dependem dele; quando a premissa cair, essa
  separação é o que você vai querer ter escrito.
- **Ordem de execução** — a tabela. A coluna Por quê é obrigatória.
- **Decisões até aqui** — uma linha por ticket fechado, com o número medido dentro. Linha sem
  número é opinião.
- **Ainda não especificado** — em escopo, sem nitidez para virar ticket. É o que impede a
  pergunta de virar ticket cedo demais e travar a fila.
- **Fora de escopo** — além do destino, **com o motivo**. Sem o motivo, alguém devolve o item
  ao escopo na sessão seguinte.

## Número medido ou nada

"A maioria das mensagens" não é achado; "101 das 185" é. Documento de medição com contagem
errada é pior que documento sem contagem, porque ele é citado. Na sessão que gerou estas
regras, uma varredura filtrou por `conversationProviderId` **não nulo** em vez de igualdade
com o id certo, e três documentos saíram com o número errado antes de alguém conferir.

Se um número não puder ser refeito por um comando escrito em `## Verificação`, ele não deveria
estar no documento.

