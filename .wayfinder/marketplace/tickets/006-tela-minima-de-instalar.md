# A tela mínima de instalar e desinstalar

- map: ../map.md
- label: wayfinder:prototype
- status: closed
- assignee: claude (sessão 2026-08-04)
- blocked-by: — (003 fechado)

## Question

A loja está fora do escopo, mas o piloto precisa de **alguma** porta pra ligar e
desligar a peça — senão não dá pra provar nada, nem pro usuário nem pro gate.

- **O mínimo que serve.** Uma lista em Ajustes com nome, descrição e um botão?
  Um painel novo ("Plugins"/"Extras") ou uma seção dentro do painel Geral?
- **O que a linha mostra** quando o plugin está desligado — nome e descrição
  vindos da declaração de 003, e mais o quê (ícone? o que ele adiciona ao notch?).
- **Desinstalar avisa?** Se a feature tem dado guardado (histórico, lembretes
  salvos), o botão precisa dizer o que vai acontecer — e isso depende de 007.
- **Essa tela sobrevive à loja de verdade?** Se ela for jogada fora quando a loja
  chegar, faz o mais burro possível. Se for a base da vitrine, o protótipo já
  desenha pensando nisso. Decidir qual dos dois — e a resposta preguiçosa
  provavelmente é "a mais burra possível".

O protótipo vira `.wayfinder/marketplace/prototypes/006-tela-de-plugins.swift`.
⚠️ Lembrar do que não renderiza no harness offscreen (`ScrollView`, `TextField`
— ver `CLAUDE.md`).

## Resolução (2026-08-04)

Protótipo em
[`prototypes/006-tela-de-plugins.swift`](../prototypes/006-tela-de-plugins.swift):
compila, roda asserções e **renderiza um PNG** (`/tmp/006-tela-de-plugins.png`)
— num ticket de vitrine, sem imagem não dá pra reagir.

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  .wayfinder/marketplace/prototypes/006-tela-de-plugins.swift \
  -o /tmp/telaplugins && /tmp/telaplugins
```

**A tela é uma vitrine em grade num painel próprio de Ajustes.** Sete decisões,
todas do dono (as marcadas ✋ foram contra a recomendação — registrado de
propósito, com o custo que trazem):

1. **Painel próprio "Plugins"** na barra lateral de Ajustes, não seção do Geral.
   São 11 peças (a lista dominaria o Geral), e quando o Pomodoro for
   desinstalado o painel "Pomodoro" some da mesma barra — causa e efeito no
   mesmo lugar. Custo: uma linha no `enum SettingsPane` + uma tela.
2. ✋ **Grade de cards, não lista de linhas.** A recomendação era a lista estilo
   App Store (ícone, nome, frase, botão pílula) por ser App Store legítima sem
   exigir arte; o dono quis vitrine. Custo aceito: cada peça precisa de capa, e
   três peças (Preview de Link, Nota rápida, Conversão de arquivo) **ainda não
   têm nome de produto** — o protótipo inventou nome e frase pras três, e isso
   é provisório (segue como névoa no mapa).
3. **A capa é o símbolo SF da própria ficha da peça sobre degradê da cor dela.**
   Símbolo e cor já estão na ficha de 003 e nos painéis de Ajustes: **zero arte
   nova, zero arquivo novo**, 11 capas prontas hoje. Descartadas ilustração por
   peça (11 desenhos a manter) e screenshot da feature (quebra a cada mudança de
   UI, e três peças não têm seção no notch pra fotografar). A ficha entrega a
   capa, então trocar por ilustração depois é uma linha.
4. ✋ **As 4 de fábrica aparecem na vitrine**, com rótulo "Incluído" e sem ação.
   A recomendação era mostrar só os 11 (card que não desinstala não faz nada, e
   a fronteira de 002 fica borrada). Custo aceito: as 4 de fábrica passam a
   precisar de nome, descrição, símbolo e cor — mas só isso, uma lista
   decorativa à parte (`Catalogo.fabrica`), **sem `nascer` e sem `PluginID`**.
   Elas não nascem nem morrem, então não entram no registro de peças.
5. **Duas seções fixas: "Incluído no Knobler" e "Plugins".** Sem categorias
   temáticas (inventaria taxonomia com 2–3 itens por categoria) e, sobretudo,
   **sem separar por "instalado"/"disponível"**: nessa forma o card **pula de
   lugar** no instante do clique e a pessoa perde de vista o que fez. O card
   fica parado; só o botão muda. Tem asserção provando isso.
6. **Três estados de botão**, e é a única regra da tela — `Vitrine.estado(de:)`
   lê a lista de ids instalados de 005 e devolve `incluido` / `instalar` /
   `abrir`. O **⋯ com "Desinstalar"** só existe em peça instalada, escondido
   como na App Store.
7. **`ABRIR` é sempre vivo** em peça instalada — a convenção da Apple é que
   item instalado tem botão que faz algo, **nunca um rótulo cinza morto tipo
   "INSTALADO"**. Muda só o alvo: peça **com painel** abre o painel dela em
   Ajustes; peça **sem painel** (Espelho, Anotação, Nota rápida, Preview de
   Link, Conversão) **abre a própria feature** — o Espelho acende a câmera, a
   Nota rápida abre a nota. Isso dá trabalho novo: as cinco precisam de um
   ponto de entrada programático.

**Sobrevive à loja de verdade?** Sim, e é por isso que ela cabe aqui: a tela lê
tudo da ficha da peça e da lista de ids. Quando a loja chegar, a vitrine ganha
destaque/categoria em cima e essa grade continua embaixo — é o caminho que a
própria App Store faz.

**O que este ticket NÃO decidiu** (de propósito): se desinstalar **avisa** antes
("isso apaga seus 40 lembretes"). É o ticket 007. O ⋯ é só o lugar onde esse
aviso vai morar.

Acabamento anotado pra execução: a área útil do painel é ~496pt (720 da janela
menos 224 da barra lateral), logo **2 colunas**; no app a grade é
`LazyVGrid` dentro de `ScrollView` — o protótipo usa `HStack` na mão só porque
`ScrollView` não renderiza no `ImageRenderer` offscreen.
