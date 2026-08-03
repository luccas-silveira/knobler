# Preview de link

Arraste um link do navegador pro notch: a página abre **dentro do card**, sem
janela e sem barra de navegador.

## Como usar

- **Arrastar um link** (da barra de endereços, de um link numa página, ou um
  texto selecionado que seja só uma URL) → o card abre na seção **Link** com a
  página carregada.
- **Colar um link**: com a seção **Link** em foco e nenhuma página aberta, o
  card mostra uma barra de endereço já focada. ⌘V, Enter, e a página abre.
  `exemplo.com` sem `https://` também vale.
- O link **não** entra na prateleira. Ela é pra arquivo que você vai usar
  depois, e um atalho por link espiado empurraria pra fora o que estava lá (a
  capacidade é 8). Um `.webloc` que venha do Finder, esse sim, abre aqui pelo
  clique-direito → **Abrir no notch**.
- Cabeçalho do card, da esquerda pra direita: **voltar**, título da página,
  **abrir no navegador padrão** e **fechar**.

O gesto de voltar (dois dedos pra direita) funciona dentro da página, como no
Safari.

## O que o card faz por baixo

**A página vê uma janela de desktop.** O card tem 736 pt de largura útil, e
nessa medida quase todo site cai no breakpoint mobile — o layout que você
conhece some. Então a página é renderizada numa viewport de **1280 px CSS** e
encolhida por zoom (0,575). O desenho original fica preservado; o texto fica
proporcionalmente menor, que é o preço.

**Nunca há barra de rolagem horizontal.** Um `overflow-x: hidden` é injetado no
elemento raiz de cada página. O corte é só no `html`: carrossel interno que rola
sozinho continua funcionando.

**O card é 16:9** — 736×414 — e mais largo que as outras seções (780 pt contra
430). Ele volta ao tamanho normal quando você foca outra seção.

## Duas mecânicas do notch que mudam aqui

- **O card não recolhe** enquanto o link está aberto, mesmo com o mouse fora.
  É a mesma trava que segura o card enquanto você digita na nota rápida — sem
  ela, o card fugiria assim que você tirasse o mouse pra ler.
- **O scroll vertical é da página**, não do notch. Mesmo tratamento que a seção
  Histórico já tinha: com o link em foco, rolar rola o site em vez de fechar o
  card. O eixo horizontal continua trocando de seção.

## Teclado

Com a seção Link em foco, o notch aceita teclado: dá pra buscar, logar e
preencher formulário dentro da página. **⌘C, ⌘V, ⌘X e ⌘A** funcionam — o app não
tem barra de menus (é `LSUIElement`), então esses atalhos passam por um monitor
próprio, ativo só enquanto o preview está aberto.

Enquanto isso, o que você digita vai pro notch e não pro app de trás. Sair da
seção (ou fechar o preview) devolve o teclado na hora. **Esc** fecha o preview.

## Limites conhecidos
- **Uma página por vez, uma tela por vez.** O `WKWebView` é único (criar um por
  monitor faria N cópias carregando a mesma coisa) e o preview pertence à tela
  onde estava o ponteiro quando você soltou o link.
- **Fora do harness de snapshot.** `WKWebView` é uma `NSView` real e não
  renderiza offscreen — a seção Link não tem PNG em `Snapshots/`, como as
  outras views que dependem de janela de verdade (ver `CLAUDE.md`).
- Sessão persistente: site logado continua logado entre aberturas.
