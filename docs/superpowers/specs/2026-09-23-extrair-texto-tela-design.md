# Extrair texto da tela — design

Data: 2026-09-23

## Objetivo

Copiar texto de qualquer coisa visível na tela (imagem, vídeo, PDF escaneado, UI que
não deixa selecionar) com um gesto: seleciona a região, o texto vai pro clipboard, o
notch confirma.

Referência de mecanismo: Vorssaint (`~/Desktop/Projetos/vorssaint-utils`,
`Services/QuickTools/ScreenTextService.swift`). É GPL-3.0 e o Knobler é MIT — **só
leitura**, nenhum trecho copiado ou adaptado.

## Fora de escopo

QR code, histórico de extrações, revisar/editar o texto antes de copiar, extrair das
capturas da prateleira.

## Acionamento

- Atalho global configurável nos Ajustes.
- Botão no notch expandido.

## Fluxo

1. Acionou: uma janela transparente por monitor, acima de tudo (inclusive apps em tela
   cheia), escurece levemente a tela; cursor em mira.
2. Arrastar desenha o retângulo com a medida (L × A) ao lado.
3. Soltar confirma. Esc ou clique direito cancela.
4. A camada fecha; o retângulo é capturado na resolução nativa, sem a camada na imagem.
5. Reconhecimento de texto local (Vision, nível preciso, correção de idioma, pt-BR e
   en-US).
6. Texto encontrado: vai pro `NSPasteboard.general`; notch mostra "Texto copiado" com o
   começo do texto.
7. Nada encontrado: notch mostra "Nenhum texto encontrado"; clipboard intacto.

## Componentes

- **Camada de seleção** — janelas por monitor, desenho do retângulo, teclado/mouse.
  Devolve o retângulo em coordenadas globais da tela, ou nada (cancelado).
- **Leitor de tela** — captura um retângulo e devolve as linhas de texto. Sem UI.
- **Coordenador** — liga atalho/botão, camada, leitor, clipboard e aviso no notch.
  Composto no `AppDelegate`, instância única (não uma por monitor).

## Permissão

Gravação de tela vira caso novo de `Permission` no painel de Permissões existente. Sem
ela, acionar abre os Ajustes do Sistema no painel certo em vez de falhar calado.

## Erros

- Seleção menor que 4 pt em qualquer lado: cancelamento silencioso.
- Acionar com seleção já aberta: ignora.
- Mudança de monitores durante a seleção: cancela.
- Falha de captura ou de reconhecimento: notch mostra "Não consegui ler a tela"; motivo
  vai pro log.

## Testes

Check novo em `tools/`, registrado em `tools/check.sh`:

- conversão retângulo global → pixels da imagem (Retina, monitor com origem negativa);
- descarte de seleção pequena;
- texto do aviso no notch truncado no limite certo;
- reconhecimento sobre imagem gerada com texto conhecido, pelo mesmo caminho do app.

Camada de seleção e captura real: validação manual com o app instalado.
