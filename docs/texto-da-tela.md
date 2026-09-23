# Texto da tela

## O que faz

Copia o texto de qualquer coisa visível — imagem, vídeo pausado, PDF escaneado,
interface que não deixa selecionar. Você arrasta sobre a área, o texto
reconhecido vai pro clipboard e o notch confirma. O reconhecimento é local
(Vision, nível preciso, correção de idioma sempre ligada, pt-BR e en-US).

É uma peça (Ajustes › Plugins) e nasce **desinstalada**: só quem instala vê o
pedido de Gravação de tela.

## Como acionar

- Atalho global **⌃⇧T** — configurável em Ajustes › Geral › Texto da tela.
- Ícone de texto com mira (`text.viewfinder`) na ponta direita da faixa de seções do notch expandido.
- Menu da barra › Ferramentas › **Extrair texto da tela…**

## Como funciona

A seleção é a do próprio macOS, a mesma do ⌘⇧4 (`screencapture -i`): o
cursor vira mira, você arrasta sobre o texto e solta. Nada congela nem escurece,
funciona em qualquer monitor, e `Esc` ou clique sem arrasto cancelam sem aviso.

Avisos no notch: **Texto copiado** (com o começo do texto), **Nenhum texto
encontrado** (clipboard intacto) e **Não consegui ler a tela** (falha de
captura ou de reconhecimento; o motivo vai pro log, categoria `TextoDaTela`).

## Permissão

Precisa de **Gravação de tela**. O primeiro acionamento mostra o balão do
sistema; a concessão só vale depois de relançar — use o **Sair e Reabrir** que
o próprio macOS oferece. Se você recusar, os acionamentos seguintes abrem os
Ajustes do Sistema no painel certo.

**Limitação:** no macOS 15+ o sistema reapresenta de tempos em tempos um alerta
pedindo pra reconfirmar a captura de tela por apps que não usam o seletor do
sistema. Não há como evitar sem um entitlement da Apple.

## Código

- `Knobler/TextoDaTela.swift` — parte pura: OCR e resumo
  (coberta por `tools/textodatelacheck.swift`).
- `Knobler/TextoDaTelaServico.swift` — coordenador e `PluginServico` da peça.

Referência de mecanismo: Vorssaint (GPL-3.0), só leitura — nenhum trecho
copiado ou adaptado.
