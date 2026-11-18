# Verificação — card de pergunta do Claude

Tela existente mudando (card `.question` do notch), uma direção, no estilo atual. Tipo de
tela: Operar. Modo direto. Servido em `http://127.0.0.1:8766/index.html`.

Respostas deduzidas: o sistema visual é o do `DESIGN.md` do projeto (preto puro, escada de
opacidade do branco, SF Pro, raio 8), então não houve busca de estilo nem de referências
externas, e nenhuma cor de destaque entrou. VARIACAO 2, MOVIMENTO 3, DENSIDADE 7.

O Chrome DevTools MCP não existe nesta sessão: CSS computado, contraste e rolagem lateral
foram lidos pelo Playwright (`getComputedStyle`), com as cores compostas sobre o preto.

## Rodada 1

Prints: `r1-375.png`, `r1-1440.png`. Console sem erro nem aviso.

- A caixa de texto do preview saía torta: as linhas tinham comprimentos diferentes.
  Corrigido (as linhas são preenchidas até a mesma largura).
- As teclas da legenda (⏎ ⇥ ← →) saíam minúsculas na fonte monoespaçada. Trocadas para a
  fonte do sistema com dígitos tabulares.
- A legenda quebrava em duas linhas na pergunta múltipla com abas. "⇥ escrever" saiu da
  legenda (a tecla já aparece dentro do campo) e o espaço entre itens caiu de 12 para 8.
- Descrição da opção marcada: 3,9:1 sobre o fundo de 25%. Corrigido para a tinta de 85%.

## Rodada 2

Prints: `r2-375.png`, `r2-1440.png`, `r2-estado-preview.png`, `r2-estado-revisita.png`,
`r2-reduced-motion-longo.png`. Console sem erro nem aviso. Sem rolagem lateral em 375
(scrollWidth 375) nem em 1440. Todas as legendas em uma linha (16 px de altura).

Interação conferida no card vivo pelo teclado: ⌃⌥K dá o teclado, ↓ move o destaque, `1`
responde e pula para a próxima pendente, `2` e espaço marcam na múltipla.

Contraste medido (texto sobre o fundo efetivo):

| Par | Razão |
|---|---|
| descrição, linha normal | 7,67 |
| descrição, linha em destaque | 6,69 |
| descrição, linha marcada | 8,06 |
| origem e aba pendente (tinta 50%) | 5,28 |
| legenda | 7,85 |
| botão Confirmar | 10,41 |

| Alarme do detector | Veredito |
|---|---|
| `undersized-ui-text` (68), `tiny-text` (4) | refutado: o notch usa os tamanhos do app (`DESIGN.md` §3, 10 a 15 pt), mostrado em tamanho real, igual aos mockups de 2026-11-04 e 2026-11-10 |
| `text-overflow` em `span.r` | refutado: é a resposta resumida da aba, com reticências de propósito |
| `cramped-padding` (só em 375) | refutado: em tela de celular o notch é reduzido por `zoom` para caber; no tamanho real a linha tem 8 px de respiro |

## Rodada 3

Pedido do usuário na parada do mockup: o preview tem de ficar sempre inteiro à vista.

Prints: `r3-375.png`, `r3-1440.png`, `r3-estado-preview.png`, `r3-estado-preview-largo.png`.
Console sem erro nem aviso. Sem rolagem lateral em 375 (scrollWidth 375) nem em 1440.

- O preview deixou de rolar e de cortar: o card alarga até caber a linha mais comprida do
  maior preview da pergunta (até 836 pt), a altura é a do maior preview, e quando nem assim
  cabe ao lado das opções ele desce para baixo delas; por último a letra encolhe, com piso de
  8 pt. Medido nos dois exemplos: `scrollWidth ≤ clientWidth` e `scrollHeight ≤ clientHeight`.
- O preview empilhado encolhia 10 px na altura. Corrigido.
- Em 375 a página ganhava rolagem lateral (scrollWidth 444): as colunas dos pares cresciam
  com o card e o card encolhia antes de ser medido. Corrigido; os cards em par voltaram ao
  tamanho real em 1440.

| Alarme do detector | Veredito |
|---|---|
| `undersized-ui-text` (73), `tiny-text` (4), `text-overflow`, `cramped-padding` (3, só em 375) | refutados como na rodada 2 |
| `em-dash-overuse` (44) | refutado: são os traços da moldura do preview em texto, não pontuação |

### Piso

| Id | Resultado |
|---|---|
| SLOP-02, SLOP-10, SLOP-11, SLOP-21, SLOP-22, SLOP-44, SLOP-46, SLOP-49 | passou |
| SLOP-37 | passou: ícones de traço único (visto e ✕); as teclas são texto |
| TIP-01, TIP-22 | passou: fonte do sistema, sem fonte importada |
| TIP-12 | passou na página (16 px, entrelinha 1,55); dentro do notch vale o tamanho do app |
| TIP-20, TIP-21 | passou |
| COR-02 | passou, com uma exceção: o hover do botão Confirmar usa um valor de opacidade direto |
| COR-12, COR-13, COR-15, COR-16 | passou: destaque tem contorno além do fundo; marcada tem visto ou caixa preenchida |
| COR-18 | não se aplica: o notch só existe em preto |
| LAY-03, LAY-22, LAY-31 | passou |
| LAY-26 | passou nos botões da página (44 px); dentro do notch vale o alvo do app de mesa (linha de opção ≥ 40 px, aba 22 px) |
| MOV-02, MOV-03, MOV-05, MOV-09, MOV-10, MOV-23 | passou: troca de aba em `transform` e `opacity`; com movimento reduzido vira fade de 150 ms |
| UX-01 | parcial: padrão, hover/destaque, foco, pressionado, desabilitado e marcado desenhados; carregando, erro e sucesso não existem neste card (responder fecha o card) |
| UX-08, UX-15, UX-16 | não se aplica: o card não valida nada |
| UX-14 | refutado: o campo "Outra resposta" usa placeholder como hoje; o rótulo acessível está no `aria-label` |
| UX-26 | passou: Confirmar é a única ação primária |
| UX-11, UX-12 | não se aplica: cancelar devolve a pergunta ao terminal, nada se perde |
| UX-20 | passou: é o objetivo da mudança |
