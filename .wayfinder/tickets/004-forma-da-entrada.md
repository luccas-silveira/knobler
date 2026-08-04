# Forma da entrada: assistente guiado ou painel incrementado

- map: ../map.md
- label: wayfinder:prototype
- status: closed
- assignee: sessão 2026-08-04
- blocked-by: —

## Question

O primeiro perfil deve nascer por um assistente de passos (criar → escolher
preset → copiar link → esperar o primeiro POST → confirmar o mapa → pronto),
ou o painel e o sheet atuais devem ser incrementados até o fluxo ficar óbvio
sem assistente?

Restrição dura: `PRODUCT.md` proíbe "painel denso de dev-tool", e a janela de
Ajustes é um `Form` `.grouped`. Um assistente é mais janela e mais estado; o
painel incrementado é diff menor mas pode não guiar ninguém.

Fazer protótipos rápidos das duas formas pra reagir. Notar que o editor usa
`HSplitView` e portanto não renderiza no harness de snapshot — protótipo tem
que ser avaliado no app rodando (`--ajustes=webhooks`).

## Resolução — 2026-08-04

**Assistente de passos.** O primeiro perfil nasce num assistente; o painel e o
sheet continuam sendo o lar de quem já tem perfil.

Protótipo executável das duas formas: `.wayfinder/prototypes/004-forma-da-entrada.swift`
(autônomo, `swiftc -O -o /tmp/proto004 … && /tmp/proto004`; args opcionais
`[forma 0|1] [passo 0..4] [sheet 0|1]` pra abrir direto num estado). Não faz
parte do app — o editor real usa `HSplitView` e não renderiza no harness.

Passos prototipados: **Nome → Serviço → Link → Primeiro envio → Mapa**, com a
trilha visível no topo, "Continuar" travado enquanto o primeiro POST não chega,
e saída pro editor completo já no passo do mapa.

### Por que A e não B

- O passo do link é o único lugar honesto pras **ressalvas dos researches**
  (workflow do GHL tem corpo customizável; ClickUp não manda nome de tarefa;
  Notion não manda URL). Na forma B a linha do perfil é estreita e o sheet já
  está cheio — não sobrou lugar sem virar painel denso.
- A espera pelo primeiro POST é um **estado**, não um campo. No assistente ela é
  uma tela; no painel vira uma faixa que compete com o resto da linha.
- O `Form .grouped` de Ajustes continua intocado, então a proibição de
  "painel denso de dev-tool" do `PRODUCT.md` fica satisfeita por construção.

### O que sobreviveu da forma B (entra junto, é diff pequeno)

Prototipado em `PainelView`/`SheetMapear` e vale independente do assistente:

- Legenda da linha do perfil passa de "Campos mapeados" para **estado**:
  "Esperando o primeiro envio" / "Último webhook há 3 min".
- Banner de **mapa sugerido** no topo do painel esquerdo do sheet, com "Desfazer".
- As quatro fontes de payload viradas para cima como **menu** ("Dados: Ao vivo ▾"),
  não como segmented — quatro segmentos estouram a largura do painel direito
  (confirmado no protótipo) e leem como dev-tool.
- Dica de rodapé "Clique num valor para inserir no campo em foco".

### Dependência declarada

O conteúdo dos passos **Serviço** e **Link** é o preset. A decisão de forma está
tomada, mas **006 (o que um preset é / onde vive) tem que fechar antes** de
implementar esses dois passos: se o preset não for receita editável
(instrução + sugestão de mapa + ressalva), o passo do link fica sem conteúdo.

O passo **Primeiro envio** depende de 007 (árvore ao vivo): sem push ou polling
o assistente não sabe que o POST chegou.
