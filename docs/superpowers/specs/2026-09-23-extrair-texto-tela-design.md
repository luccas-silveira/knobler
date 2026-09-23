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

- Atalho global configurável nos Ajustes; padrão ⌃⇧T (vale só com a peça ligada).
- Ícone na ponta direita da faixa de seções do notch expandido (`sectionStrip`),
  separado dos ícones de seção; clicar fecha o notch e abre a seleção. Só aparece com a
  peça ligada. Disparo via closure no `NotchViewModel` (padrão `onPomodoroX`), sem
  arrastar tipo novo pra `tools/notchview-fontes.txt`.
- Item "Extrair texto da tela…" no menu Ferramentas da barra de menus, ao lado do
  conta-gotas.

## Fluxo

1. Acionou: cada monitor é fotografado na resolução nativa (tela congelada).
2. Uma janela por monitor, acima de tudo (inclusive notch e apps em tela cheia), mostra
   a foto levemente escurecida; cursor em mira.
3. Arrastar desenha o retângulo com a medida (L × A) ao lado; dentro dele a foto aparece
   sem escurecer.
4. Soltar confirma. Esc ou clique direito cancela.
5. A camada fecha; o retângulo é recortado da foto do monitor onde o arraste começou
   (seleção presa a esse monitor).
6. Reconhecimento de texto local (Vision, nível preciso, correção de idioma sempre ligada, pt-BR e
   en-US).
7. Texto encontrado: vai pro `NSPasteboard.general`; notch mostra "Texto copiado" com o
   começo do texto.
8. Nada encontrado: notch mostra "Nenhum texto encontrado"; clipboard intacto.

## Componentes

- **Camada de seleção** — janelas por monitor, desenho do retângulo, teclado/mouse.
  Devolve o retângulo em coordenadas globais da tela, ou nada (cancelado).
- **Leitor de tela** — captura um retângulo e devolve as linhas de texto. Sem UI.
- **Coordenador** — liga atalho/botão, camada, leitor, clipboard e aviso no notch.
  Instância única (não uma por monitor), nascida como **peça** (`Knobler/Plugin.swift`,
  `PluginRegistry.todos`): desligada, não registra atalho nem pede permissão.

## Atalho

Reusa `Vendor/MonitorControl/KeyboardShortcuts.swift` (Carbon, gravador pronto em
`MonitoresView.swift:217-222`). Hoje `Monitores.stop()` chama `removeAllHandlers()` e
mataria o atalho novo: ganha `removeHandlers(for: Name)` no vendor (anotado em
`Vendor/PROVENANCE.md`) e os Monitores passam a remover só os nomes deles. A peça faz o
mesmo ao desligar.

## Permissão

Gravação de tela vira caso novo de `Permission` no painel de Permissões existente. Sem
ela, acionar abre os Ajustes do Sistema no painel certo em vez de falhar calado.

A concessão só vale após relançar; o "Sair e Reabrir" do próprio macOS cobre isso — sem
botão próprio. No macOS 15+ o sistema reapresenta periodicamente um alerta de
reconfirmação para captura sem o seletor do sistema; inevitável sem entitlement da Apple.
Documentar a limitação na doc do recurso.

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

## Decisões do grill

Dossiê: `docs/superpowers/research/2026-09-23-extrair-texto-tela-research.md`.

- **A6** — vira peça, não recurso fixo. Motivo: `docs/architecture.md:43-70`; só quem
  liga vê o pedido de Gravação de Tela e o alerta periódico.
- **A1** — tela congelada antes da seleção. Motivo: o texto lido é o que a pessoa viu;
  dispensa excluir a própria camada da captura. Padrão do Vorssaint/CleanShot/Shottr.
- **A5** — ícone na ponta da faixa de seções + item no menu Ferramentas. Motivo: o notch
  não tem fileira de ferramentas; seção inteira seria peso pra um botão.
- **A2** — aceito o alerta periódico do macOS 15+. Motivo: sem alternativa com
  assinatura local; a função antiga de captura é obsoleta no 15.
- **A3** — sem botão "Reabrir" próprio. Motivo: o macOS já oferece "Sair e Reabrir"; o
  próximo acionamento cobre quem recusar.
- **A4** — `removeHandlers(for:)` no vendor, Monitores removem só os seus. Motivo:
  `Monitores.swift:107` apagaria o atalho novo.
- **A8** — correção de idioma sempre ligada, sem chave. Motivo: uso principal é texto
  corrido; o usuário dispensou a opção.
- **A7, A9, A10** — só confirmaram a spec.
- **Atalho padrão** — ⌃⇧T. Motivo: livre no macOS; a peça nasce desligada.
