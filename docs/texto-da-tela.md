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

1. No acionamento cada monitor é fotografado: a tela **congela** e o que você
   lê é exatamente o que viu.
2. A foto aparece escurecida com cursor em mira. Arraste: a área selecionada
   fica clara e mostra a medida em pontos.
3. Soltar confirma. `Esc` ou clique direito cancelam; clique sem arrasto (ou
   seleção com menos de 4 pt num lado) também cancela, sem aviso.
4. A seleção fica presa ao monitor onde o arraste começou.

Avisos no notch: **Texto copiado** (com o começo do texto), **Nenhum texto
encontrado** (clipboard intacto) e **Não consegui ler a tela** (falha de
captura ou de reconhecimento; o motivo vai pro log, categoria `TextoDaTela`).

Trocar de monitor com a seleção aberta cancela.

## Permissão

Precisa de **Gravação de tela**. O primeiro acionamento mostra o balão do
sistema; a concessão só vale depois de relançar — use o **Sair e Reabrir** que
o próprio macOS oferece. Se você recusar, os acionamentos seguintes abrem os
Ajustes do Sistema no painel certo.

**Limitação:** no macOS 15+ o sistema reapresenta de tempos em tempos um alerta
pedindo pra reconfirmar a captura de tela por apps que não usam o seletor do
sistema. Não há como evitar sem um entitlement da Apple.

## Código

- `Knobler/TextoDaTela.swift` — parte pura: recorte em pixels, OCR, resumo
  (coberta por `tools/textodatelacheck.swift`).
- `Knobler/SelecaoDeTela.swift` — camada de seleção, um painel por monitor.
- `Knobler/TextoDaTelaServico.swift` — coordenador e `PluginServico` da peça.

Referência de mecanismo: Vorssaint (GPL-3.0), só leitura — nenhum trecho
copiado ou adaptado.
