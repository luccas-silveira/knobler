# Seções fixadas no card aberto

Data: 2026-08-03

## Problema

Hoje o card aberto só mostra uma seção se ela tem conteúdo agora
(`NotchSectionState.hasContent`). Quem quer a Nota rápida, o Pomodoro ou o
Espelho sempre à mão não tem como: a seção some quando está vazia, e a faixa de
ícones some junto.

## Solução

Um ajuste por seção — "fixar" — que faz a seção aparecer no card mesmo sem
conteúdo. As 9 seções podem ser fixadas; o usuário decide. Padrão: nenhuma
fixada (comportamento atual, sem migração).

## Modelo

`AppSettings.notchSectionsFixadas: Set<NotchSection>`, persistida em
UserDefaults na chave `notchSectionsFixadas` como array de `rawValue`. Leitura
descarta `rawValue` desconhecido (mesma postura defensiva do `sanear` da ordem);
não completa nada, porque um conjunto vazio é um estado legítimo.

`NotchSectionOrder.ordenar` ganha o parâmetro `fixadas: Set<NotchSection>`. A
única mudança de lógica é o filtro de visibilidade:

```swift
let visiveis = ordemBase.filter {
    porSecao[$0]?.hasContent == true || fixadas.contains($0)
}
```

Promoção por evento, desempate pela ordem-base e trava da nota ficam intactos.
Uma fixada vazia não tem `lastEvent` recente, então cai naturalmente na posição
da ordem-base — que é o comportamento pedido: a ordem dos Ajustes vale ao pé da
letra, com ou sem conteúdo.

## Foco inicial

`NotchViewModel.recalcularSecoes` passa a escolher como foco a primeira seção
**com conteúdo**, caindo na primeira da lista só quando nenhuma tem. Sem isso,
fixar a Música faria o card abrir em "Nada tocando" toda vez que a Música fosse
a primeira da ordem. A ordem visual não muda — só qual seção nasce em foco.

O foco pendente (`focoPendente`) e a trava da nota continuam vencendo essa
escolha, como hoje.

## Estados vazios

Fixar só faz sentido se a seção vazia desenha algo. Quatro não desenham:

| Seção | Hoje sem conteúdo | Passa a mostrar |
|---|---|---|
| `atividade` | `if let a` → nada | Ícone + "Nenhuma atividade" |
| `pomodoro` | `if let p` → nada | Botão "Iniciar Pomodoro" |
| `espelho` | exige `mirrorOn` | `mirrorButton` ("Ligar espelho"), já existente |
| `musica` | "Nada tocando", mas só quando atividade/shelf/espelho estão vazios | "Nada tocando" sempre que a seção for renderizada |
| `link` | `WKWebView` sem URL → área em branco | Ícone + "Nenhum link copiado" enquanto não há URL carregada |

`shelf`, `historico`, `nota` e `mensagens` já têm estado vazio adequado.

As alturas por seção (`NotchView`, linhas ~100-108) valem para o estado cheio. O
estado vazio usa a mesma altura da seção: manter uma altura só evita um segundo
eixo de casos e o card já é curto.

## Ajustes

No painel Notch, a `List` de ordenação existente ganha um pin por linha — um
`Toggle` com estilo de botão (`pin.fill` / `pin.slash`) à direita do `Label`.
Nenhuma tela nova; o `.onMove` continua funcionando.

Texto de apoio da seção passa a mencionar o pin, em uma frase.

## Check

`tools/sectionordercheck.swift` ganha dois casos:

1. seção fixada e sem conteúdo aparece na posição da ordem-base;
2. seção não fixada e sem conteúdo continua fora.

Compila os mesmos arquivos de hoje; nenhuma entrada nova em `tools/check.sh`.

## Fora de escopo

- Fixar no notch **fechado** (indicadores da barra) — outra feature.
- Travar uma seção no topo ignorando a promoção por evento.
- Expor as fixadas no `GET /status` ou na API local.
