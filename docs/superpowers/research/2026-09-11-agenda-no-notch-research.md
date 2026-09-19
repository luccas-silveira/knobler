# Pesquisa — Agenda no notch

Spec: `docs/superpowers/specs/2026-09-11-agenda-no-notch-design.md`

## Achados

### A1 — A ordem salva já aceita seções novas
- Fonte: `Knobler/NotchSectionOrder.swift:64`, `Knobler/NotchViewModel.swift:158`.
- Contradiz a spec: não. Reutilizar ordenação e não emitir promoção para Agenda.

### A2 — Cada monitor cria um ViewModel
- Fonte: `Knobler/KnoblerApp.swift:1149`.
- Contradiz a spec: não. Ligar consulta e estado inicial na criação de cada monitor.

### A3 — O countdown tem chave própria e consulta apenas uma janela curta
- Fonte: `Knobler/CalendarCountdown.swift:99`.
- Contradiz a spec: não. Publicar a agenda antes do guard da preferência.

### A4 — EventKit exige nova consulta e ordenação explícita
- Fontes: https://developer.apple.com/documentation/eventkit/retrieving-events-and-reminders
  e https://developer.apple.com/documentation/eventkit/updating-with-notifications
- Contradiz a spec: não. Refazer a consulta em mudanças, verificar autorização e
  filtrar sobreposição usando limites locais do dia, sem somar 86400 segundos.
- A documentação não garante precisamente a inclusividade dos extremos; o filtro
  semiaberto e os testes definem a regra da agenda.

### A5 — Harnesses não compilam o AppDelegate
- Fonte: `tools/main.swift:24`, `tools/notchview-fontes.txt:1`.
- Contradiz a spec: não. A view abre permissões por callback e registra fontes novas.

## Fila do grill

Nenhum achado contradiz a spec. As escolhas técnicas seguem os padrões existentes;
nenhuma nova decisão de produto é necessária além do desenho aprovado.
