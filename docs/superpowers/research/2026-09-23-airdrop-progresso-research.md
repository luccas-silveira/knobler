# Pesquisa — AirDrop: progresso, módulo e card

Spec: `docs/superpowers/specs/2026-09-23-airdrop-progresso-design.md`

## Achados

### A1 — Não há fonte pública de que o sharingd publique `NSProgress` do arquivo recebido
- Fonte: `NSProgress.h` do SDK (linhas 452–476, `addSubscriber` disponível desde 10.9, não depreciado); https://developer.apple.com/forums/thread/707882 ; https://forum.soundflow.org/-11445/monitor-airdrop-progress
- Contradiz a spec: parcial (a spec assume que funciona)
- Pergunta: a barra de recebimento depende de um teste ao vivo (script assinando ~/Downloads + AirDrop do iPhone). Fazemos esse teste antes de planejar, ou planejamos com fallback indeterminado?

### A2 — Envio não tem progresso por API; AX da janela do sharingd é não documentado
- Fonte: `NSSharingService.h` sem símbolo de progresso; zero uso de `sharingd` no repo; padrão AX reaproveitável em `NotificationInterceptor.swift:78-88,206-212`
- Contradiz a spec: parcial
- Pergunta: aceitar que o envio pode continuar sem % se o axdump da janela não mostrar indicador?

### A3 — Esconder o alerta sem fechar: sem nenhuma fonte; erro ali interrompe a transferência
- Fonte: `docs/notifications.md:28-32`; `NotificationInterceptor.swift:133-137`
- Contradiz a spec: parcial
- Pergunta: vale o risco de mexer no alerta vivo, ou o alerta fica sempre e aceitamos a duplicação?

### A4 — Nome do aparelho não tem API; só texto do alerta via AX
- Fonte: pesquisa externa (nenhuma API); axdump registrado mostra só "AirDrop, Recebendo uma foto"
- Contradiz a spec: sim ("Recebendo de <par>")
- Pergunta: aceitar mostrar o par só quando o texto do alerta trouxer, senão "Recebendo por AirDrop"?

### A5 — Card não tem campo de miniatura; ações locais não têm roteamento; ações não persistem
- Fonte: `NotchNotification.swift:34-42,59-67`; `KnoblerApp.swift:1215-1230`
- Contradiz a spec: parcial
- Pergunta: botões Abrir/Finder/Prateleira só no card vivo (histórico só revela, como hoje)?

### A6 — Duração só existe 5 s (sem ação) e 30 s (com ação)
- Fonte: `NotchViewModel.swift:458-460,650-651`
- Contradiz a spec: sim (10 s)
- Pergunta: card com botões passa a ficar 30 s como qualquer card acionável, sem duração nova?

### A7 — Miniatura via QuickLook vira ícone "proibido" no snapshot
- Fonte: `ShelfPreview.swift:170-173`; `ShelfThumbnailDragView.swift:92-97`
- Contradiz a spec: parcial
- Pergunta: reusar `ShelfPreview.thumbnail(of:)` pra miniatura do card (funciona no snapshot)?

### A8 — Progresso de atividade é anel, não barra
- Fonte: `NotchView.swift:677,906,1157-1180`; `NotchViewModel.swift:10-17`
- Contradiz a spec: parcial ("barra")
- Pergunta: usar o anel com % já existente em vez de desenhar uma barra nova?

### A9 — Mover arquivos quebra caminhos explícitos
- Fonte: `tools/check.sh:94`; `tools/notchview-fontes.txt:43,44,78`; `tools/sharingcheck.swift:9`. `project.yml:15-17` usa glob, pasta nova entra sozinha.
- Contradiz a spec: não (só custo)

### A10 — Docs afirmam o contrário do que a feature entrega
- Fonte: `docs/shelf.md:143-150`; `KnoblerApp.swift:157-159`; `docs/notifications.md:28-36`
- Contradiz a spec: não (atualizar docs no plano)

## Fila do grill

1. A1 — teste ao vivo do recebimento antes do plano? (trava A3, A4)
2. A3 — mexer no alerta vivo ou deixar?
3. A2 — envio sem % aceitável?
4. A4 — par só quando disponível?
5. A8 — anel em vez de barra?
6. A6 — 30 s em vez de 10 s?
7. A5 — ações só no card vivo?
8. A7 — miniatura via `ShelfPreview.thumbnail`?

## Teste ao vivo (2026-09-23, vídeo do iPhone, ~5 s)

- **A1 confirmado**: `addSubscriber(forFileURL: ~/Downloads)` recebeu `PUBLISH` com
  `NSProgressFileURLKey=…/IMG_5708.MOV` e `NSProgressFileOperationKindReceiving`,
  30 atualizações de `fractionCompleted` de 0.001 a 1.000, depois `UNPUBLISH`.
- **Alerta durante**: `desc="AirDrop, Recebendo um vídeo"`, tem `AXProgressIndicator`,
  ações só Mostrar Detalhes/Fechar. **Nenhum nome de aparelho/pessoa** (A4: par
  indisponível no recebimento).
- **Alerta ao fim**: vira `desc="AirDrop Concluído, Recebido: um vídeo"` com botões
  Mostrar no Finder / Abrir / Fechar. A transferência já acabou nesse ponto.

## Teste ao vivo do envio (Finder → iPhone, mesmo vídeo, 2 rodadas)

- `addSubscriber` em ~/Downloads: **zero** publicações no envio. Sem % por essa via.
- Janela `AXWindow title="AirDrop"` no processo **de quem compartilha** (aqui o
  Finder): `AXStaticText "Como Luccas Silveira"`, e por destino um
  `AXButton desc="iPhone (2)"` → `"iPhone (2), Enviando"` → `"iPhone (2), Enviado"`.
  O anel de progresso ao redor do aparelho fica dentro de `AXOpaqueProviderGroup`,
  sem valor legível. Conclusão A2: envio dá **destino + fase**, não %.
