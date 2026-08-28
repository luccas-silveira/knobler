# Medição 001 — O que os destinos devolvem quando aceitam o arraste

Método: nove arrastes sintéticos, cada um dirigido por
`tools/sondaarraste/main.swift`, que **compila o arquivo real**
`Knobler/ShelfThumbnailDragView.swift` em vez de copiar o código — o que um
destino responde depende inteiramente da forma do pasteboard que `startDrag`
escreve, então uma cópia à mão mediria outra coisa. A sonda põe a miniatura numa
janela em posição conhecida, posta os eventos de mouse de uma thread separada
(`beginDraggingSession` roda um laço de eventos aninhado na main, e de lá não dá
pra postar), e anota duas linhas por arraste: o contexto pedido em
`sourceOperationMaskFor` e a operação devolvida em
`draggingSession(_:endedAt:operation:)`.

Feito em 2026-08-28, no macOS 26 Tahoe da máquina de desenvolvimento. Cada
destino teve a posição da janela **confirmada imediatamente antes** do arraste —
a primeira tentativa no Mail mediu outra janela porque a de composição tinha se
movido, e o número saiu errado.

A coluna "chegou" é verificada por fora, não pelo callback: `ls` na pasta de
destino, título da aba do Chrome escrito pelo `drop` da página, nome da janela
do VS Code, captura de tela da composição do Mail.

## A tabela

| # | Destino | Arquivo | Operação devolvida | Chegou? |
|---|---|---|---|---|
| 01 | Finder, pasta aberta | imagem `.png` | `copy` (raw 1) | sim |
| 02 | Finder, pasta aberta | texto `.txt` | `copy` (raw 1) | sim |
| 04 | Chrome, área de soltura de uma página local | imagem `.png` | `copy` (raw 1) | sim, `dataTransfer.files` com o nome certo |
| 05 | Chrome, mesma área | texto `.txt` | `copy` (raw 1) | sim |
| 06 | VS Code (Electron), área do editor | texto `.txt` | `copy` (raw 1) | sim, o arquivo abriu numa aba |
| 07 | Lixeira, no Dock | texto `.txt` | `none` (raw 0) | não, e o original ficou intacto |
| 08 | Solto sem destino nenhum | imagem `.png` | `none` (raw 0) | não |
| 09 | Mail, corpo de uma composição | imagem `.png` | `copy` (raw 1) | sim, embutida — a mensagem foi a 1,1 MB |
| 10 | Alvo de soltura **dentro do próprio app** | imagem `.png` | `copy` (raw 1) | sim |

## O que a tabela responde

**A operação separa aceitar de recusar, em todos os casos medidos.** Sete
destinos aceitaram e os sete devolveram `copy`; dois recusaram e os dois
devolveram `none`. Nenhuma divergência: nenhum destino devolveu `copy` sem o
arquivo chegar, e nenhum devolveu `none` tendo aceitado. A regra "o item sai da
shelf em qualquer arraste bem-sucedido" tem base para funcionar.

**A Lixeira recusa.** Com só `.copy` anunciado ela devolve `none` e não aceita o
arquivo. Levar o item pra Lixeira exigiria anunciar `.delete`, o que este mapa
não faz. O comportamento é consistente, não é um falso negativo — mas significa
que arrastar da shelf pra Lixeira não é um gesto que funcione hoje.

**O arraste que termina dentro do próprio app é indistinguível do que sai.** É o
achado que muda o desenho: um alvo de soltura dentro da mesma janela devolve
`copy`, exatamente igual ao Finder. E o contexto pedido em
`sourceOperationMaskFor` **não** ajuda a separar — a sequência é a mesma nos nove
arrastes (`dentro-do-app` e depois `fora-do-app`, no começo da sessão), porque o
AppKit pergunta pelos dois contextos antes de saber onde a soltura vai cair.

A consequência é direta para o ticket 007: empilhar arrastando uma miniatura
sobre outra devolveria `copy`, e a remoção do ticket 005, escrita ingenuamente,
apagaria o item que só mudou de lugar. O 005 precisa de outro sinal — o ponto de
soltura comparado com o quadro da janela do notch, ou uma marca posta pelo
próprio alvo interno.

## O que não foi medido

**Slack não está instalado nesta máquina.** A classe Electron foi medida pelo VS
Code, que é Electron, mas não é o mesmo app e não prova o Slack.

**A Mesa (Desktop) não foi medida em separado** — é o mesmo destino Finder das
linhas 01 e 02, e soltar lá encheria a Mesa do usuário de arquivo de teste.

**Nenhum destino que aceite e devolva `none` foi encontrado**, o que é o
resultado esperado mas não é prova de que ele não exista: nove arrastes não
varrem o sistema.

## Duas ressalvas sobre a tabela

O pasteboard é escrito como `item.setString(url.absoluteString, forType: .fileURL)`
— uma URL em texto sob `public.file-url`, não a representação canônica de
arquivo. Tudo o que está na tabela é condicional a essa forma; mudar o
pasteboard pode mudar o que os destinos respondem.

A sonda arrasta de uma janela comum. O app de verdade arrasta de um `NSPanel`
nonactivating com um monitor global de mouse. Nada indica que isso mude a
resposta do destino, mas não foi medido.

## Verificação

```bash
xcrun swiftc -swift-version 5 \
  Knobler/ShelfThumbnailDragView.swift tools/sondaarraste/main.swift \
  -o /tmp/sondaarraste
/tmp/sondaarraste <arquivo> <x> <y> <rótulo>   # x,y em coordenadas CGEvent
cat /tmp/knobler-arraste-001.log
```

A instrumentação mora na **sonda**, não no app: `ThumbSondado` herda de
`DragThumbView` e só acrescenta o registro, então o Knobler que o usuário roda
não escreve log de arraste nenhum. O único vestígio no código de produção é que
`DragThumbView` deixou de ser `final`, com o comentário dizendo por quê.
