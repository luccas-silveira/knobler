# Backlog de UX

Levantado em 2026-09-23 a partir da leitura do código e dos PNGs de
`Snapshots/`, sem uso real do app. Cada item diz o problema, a evidência e a
direção. Quando um item virar trabalho, ele passa pelo `spec-flow` e ganha link
para a spec.

Já existe e ficou de fora: a notificação para enquanto o cursor está sobre ela
(`NotchViewModel.holdNotification`), o app abre sozinho no login
(`SMAppService`) e a barra de menus já tem os controles do Pomodoro.

---

## Fácil (horas)

Feitos em 2026-09-23: 1, 2, 3, 5, 7 e 8. O 4 e o 6 ficaram como explicado em cada um.

### 1. Dica e rótulo de acessibilidade em todo botão só de ícone

Há 17 `.help(` e 17 `accessibilityLabel` no app inteiro. O VoiceOver lê a
maior parte dos controles do notch como "botão", e quem não reconhece um ícone
não tem onde descobrir o que ele faz.

Direção: todo `Button` cujo rótulo é só `Image(systemName:)` ganha `.help` e
`.accessibilityLabel` com o mesmo texto em pt-BR.

### 2. Área de clique dos ícones de seção e do × da prateleira

Os ícones de seção na base do card têm uns 14 pt (`NotchView.swift:944`,
`:975`), e o × de cada item da prateleira é menor ainda e fica colado no
arquivo. A Apple recomenda pelo menos 28 pt de alvo no macOS.

Direção: manter o desenho e ampliar só a área que recebe o clique
(`.frame` maior + `.contentShape(Rectangle())`).

### 3. Contraste dos ícones de seção inativos

Em `Snapshots/foco-musica.png` os ícones de sincronizar e da bandeja quase somem
no fundo preto.

Direção: subir a opacidade dos inativos até um contraste de 3:1 contra o fundo
(mínimo WCAG para elementos gráficos).

### 4. Fontes fixas (adiado)

Os estilos semânticos do SwiftUI não crescem com o tamanho de texto do sistema
num app de Mac: trocar `size: 9` por `.caption2` só mudaria o desenho, sem
ganho de acessibilidade. Fica para quando houver um ajuste de tamanho de texto
no próprio app.

Texto original: que ignoram o tamanho de texto do sistema

22 ocorrências de `.font(.system(size: 8…10))`.

Direção: trocar pelos estilos semânticos (`.caption`, `.caption2`, `.footnote`).
Onde o layout do notch não aguentar texto maior, limitar com
`.dynamicTypeSize(...DynamicTypeSize.large)` em vez de fixar o tamanho.

### 5. Desfazer o "Limpar" e o × da prateleira

`Shelf.swift:192` chama `shelf.clear()` direto, sem confirmação nem desfazer.
O × remove um item do mesmo jeito.

Direção: guardar a lista removida e mostrar "Desfazer" por uns 5 s no lugar do
botão. Sem diálogo de confirmação: desfazer atrapalha menos que perguntar antes.

### 6. Nomes iguais entre Ajustes e vitrine de plugins (não era problema)

O app já usa "Alertas programados" e "Notificações externas" nos dois lugares
(`Plugin.swift`). Só o índice da doc dizia "Webhooks", e foi corrigido.

Texto original:

O painel "Alertas programados" corresponde ao plugin "Lembretes", e
"Notificações externas" corresponde a "Webhooks". A pessoa procura por um nome
e acha o outro.

Direção: escolher um nome por feature e usar em `SettingsView`, `Plugin.swift`,
na doc e nas Novidades.

### 7. Redução de movimento em todas as transições

`accessibilityReduceMotion` é lido em 3 arquivos (`NotchShell`, `NotchView`,
`AirPodsViews`). As trocas de seção e outras animações do card não respeitam a
preferência.

Direção: com a preferência ligada, trocar deslize e mola por fade curto.

### 8. Vibração do trackpad em ações de encaixe

Nenhum uso de `NSHapticFeedbackManager` no projeto.

Direção: `.alignment` ao trocar de seção pelo gesto de rolagem e
`.levelChange` ao soltar um arquivo na prateleira.

---

## Médio (1 a 2 dias)

Feitos em 2026-09-23: 9, 10, 11 e 12 (o 11 pela alternativa: o card só cresce enquanto está aberto).

### 9. Atalho global para abrir o notch e navegar por teclado

Hoje o card só abre com o mouse. Atalho global existe só no Monitores e no
Texto da tela (`KeyboardShortcuts`, já no projeto).

Direção: atalho configurável que abre o card, setas ou Tab entre seções, Esc
para fechar. O trabalho real é o foco de teclado num painel `nonactivating`:
ver as notas do `MEMORY.md` sobre foco e janela chave.

### 10. Abrir só com clique ou ajustar a sensibilidade do hover

Os tempos são fixos (`NotchPresentation.swift:68`: abre em 0,18 s, fecha em
0,30 s). Quem passa o cursor pelo topo da tela a caminho das abas do navegador
abre o card sem querer.

Direção: opção em Ajustes › Notch com "Passar o mouse" / "Clicar" e, no modo
hover, um controle de atraso.

### 11. Altura travada enquanto o card está aberto

Cada seção tem uma altura (`NotchView.currentSize`). Trocar de seção faz o card
encolher e o conteúdo pular embaixo do cursor. A correção de 2026-09-23 só
estendeu o atraso de fechar; o salto continua.

Direção: ao abrir, fixar a altura da maior seção visível e só recalcular ao
fechar. Alternativa mais barata: animar a mudança só quando a altura cresce.

### 12. Ajustes agrupados e com busca

São 12 painéis numa lista plana, misturando sistema (Geral, Permissões),
features (Ditado, Pomodoro) e integrações (Webhooks, Mensagens).

Direção: seções na barra lateral (Sistema, Features, Integrações) e
`.searchable` filtrando por painel e por rótulo de opção.

### 13. Estados vazio, de erro e sem permissão iguais em todas as seções

Agenda e Lembretes cobrem os quatro estados (ver `Snapshots/agenda-*`,
`lembretes-*`). As outras seções não foram conferidas.

Direção: um componente só de estado vazio/erro, e todo "sem permissão" com o
botão que abre o ajuste certo do sistema.

### 14. Prateleira: arrastar vários e Quick Look

Direção: seleção múltipla com arrasto em grupo para fora e pré-visualização
com a barra de espaço (`QLPreviewPanel`).

### 15. Respeitar o modo Foco do macOS

O Foco só aparece ligado ao Pomodoro. Com um Foco do sistema ativo, o notch
continua mostrando tudo.

Direção: silenciar cards de notificação durante o Foco, com exceção para o
que a pessoa marcar como importante nas regras de notificação.

---

## Difícil (1 semana ou mais)

### 16. Notch inteiro navegável pelo VoiceOver

Vai além dos rótulos do item 1: ordem de leitura, anúncio ao trocar de seção
(`NSAccessibility.post`) e anúncio de notificação nova sem roubar o foco.

### 17. Tour dos gestos no primeiro uso

O onboarding cobre as permissões e não a interação. Nada na interface revela
que dá para rolar para trocar de seção ou arrastar arquivo para a prateleira.

Direção: três ou quatro passos mostrados no próprio notch depois do onboarding,
reabríveis pelo menu da barra.

### 18. Reordenar e esconder seções direto no card

Hoje a ordem se configura nos Ajustes (`NotchSectionOrder`).

Direção: modo de edição no card (clique longo nos ícones de seção) com arrastar
para reordenar e botão para esconder.

### 19. Tela cheia em Split View e janelas quase cheias

Split View não é detectado como tela cheia, porque nenhuma das duas janelas
cobre a tela sozinha. Limite conhecido, marcado com `// ponytail:` em
`KnoblerApp.swift`.

### 20. Ações nas notificações de outros apps

Acionar um botão do banner exige o `AXUIElement` vivo, e o interceptor fecha o
banner para o notch substituí-lo. Sem meio-termo pela Acessibilidade; só com
integração específica por app. Já registrado em `docs/IDEIAS.md`.
