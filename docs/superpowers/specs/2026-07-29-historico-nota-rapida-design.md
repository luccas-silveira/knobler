# Histórico de notificações + Nota rápida — design

Data: 2026-07-29

Duas features independentes que compartilham o notch expandido e por isso saíram
no mesmo desenho. Podem ser implementadas em qualquer ordem; não se tocam além
de ambas mexerem no `expandedContent`.

---

## 1. Histórico de notificações (24 h)

### O problema

Notificação passa e some. Quem estava de costas pra tela perde o card do deploy
que terminou, do webhook que chegou, do lembrete que disparou. Não existe "o que
eu perdi nos últimos minutos".

### Armazenamento

`NotificationHistory: ObservableObject` singleton, injetado no ambiente do jeito
que o `Shelf` já é.

```swift
final class NotificationHistory: ObservableObject {
    static let shared = NotificationHistory()
    @Published private(set) var items: [NotchNotification] = []   // mais recente primeiro

    func record(_ n: NotchNotification) {
        guard !items.contains(where: { $0.id == n.id }) else { return }  // multi-monitor
        if let wid = n.webhookID { items.removeAll { $0.webhookID == wid } }
        items.insert(n, at: 0)
        items.removeAll { $0.date.timeIntervalSinceNow < -86_400 }
    }
}
```

Fica **fora** do `NotchViewModel` porque existe um view model por tela: lá dentro
o histórico seria copiado por monitor e cada cópia podaria sozinha.

Três decisões embutidas:

- **Sem disco.** Reiniciou o app, zerou. `NotchNotification` carrega `NSImage` e
  `AXUIElement`, nenhum dos dois serializável — persistir exigiria um DTO
  paralelo. Notificação é efêmera por natureza; o preço não paga.
- **`webhookID` repetido substitui.** Mesma regra do `enqueue`: uma barra de
  progresso que atualiza 40 vezes é uma linha no histórico, não 40.
- **Poda na escrita.** Sem timer. A lista só muda quando algo entra, então
  podar no `record` basta — o pior caso é ver um item de 24 h e 1 min se nada
  chegou desde então.

Ponto de entrada: uma chamada a `record()` dentro de `NotchViewModel.enqueue`.
Escopo = tudo que virou card: banner do sistema interceptado, card de webhook,
lembrete disparado e atividade da API local.

### Gesto: puxão longo, numa passada só

`handleScroll` (`KnoblerApp.swift:633`) hoje guarda um `scrollActed: Bool` que
congela a decisão na primeira ação do gesto. O eixo vertical passa a ser uma
função pura do acumulador — fica menos código que hoje e o puxão longo cai de
graça:

```swift
enum ScrollTarget { case closed, expanded, history }

// ponytail: alvo é função do acumulado, não uma máquina de estados
static func verticalTarget(accumY: CGFloat) -> ScrollTarget? {
    if accumY > 120 { return .history }
    if accumY > 24  { return .expanded }
    if accumY < -24 { return .closed }
    return nil
}
```

Com o histórico **já aberto** essa função nem é consultada: o monitor entrega o
evento à lista (ver a seção seguinte).

- Puxar 120 pt sem soltar os dedos vai de fechado direto ao histórico, passando
  visualmente pelo card.
- Recuar os dedos **dentro do mesmo gesto** desfaz: o alvo recalcula a cada
  delta, então 130 pt seguido de recuo pra 30 pt volta ao card.
- `scrollActed` continua existindo, só que apenas para o eixo horizontal
  (pular faixa / trocar de tela), que segue com a semântica de ação única.

Limiar de 120 pt: 5× o de abrir. Fica acima do overshoot típico de um scroll
casual de duas linhas e abaixo de um flick deliberado.

### Fechar não é gesto

Com o histórico aberto, o monitor **deixa o scroll vertical passar**
(`return event`) para a `ScrollView` do SwiftUI rolar a lista de verdade.

Fechar é tirar o mouse — o mesmo hover-out que já fecha o notch. A alternativa
(scroll pra cima fecha) exigiria rastrear o offset da lista pra distinguir
"rolar pro topo" de "fechar", que é o único jeito de acomodar as duas coisas no
mesmo eixo. Não vale o rastreamento.

### UI

- **Alcinha de descoberta**: `Capsule` de 28 × 3 pt, `.white.opacity(0.25)`, no
  rodapé do card aberto. É a única dica de que há mais coisa embaixo — o gesto
  escolhido não se anuncia sozinho.
- **Lista**: capada em 260 pt de altura com scroll interno. Cada linha traz hora
  (`10:32`), nome do app, título e corpo truncado em uma linha. **Sem ícone de
  app**: ele viria de `NSWorkspace.icon(forFile:)`, que o `CLAUDE.md` lista como
  não renderizável no `ImageRenderer` offscreen — o cenário de snapshot viraria
  o ícone de "proibido". Texto também lê melhor numa lista densa.
- **Clique** reusa o `onNotificationAction` / `openURL` que o card já tem.
- **Vazio**: "Nada nas últimas 24 h".
- `zoneHeight` do `handleScroll` precisa acompanhar a altura maior do card com
  histórico, senão o cursor sai da zona do gesto no meio da lista.

---

## 2. Nota rápida

### O problema

Anotar três palavras (um telefone, um nome, o número do chamado) hoje custa abrir
um app. A nota morre em minutos, mas o custo de guardá-la é de coisa permanente.

### Estado

```swift
final class QuickNote: ObservableObject {
    static let shared = QuickNote()
    @Published var active = false { didSet { if !active { text = "" } } }
    @Published var text = ""
    @Published var editing = false      // campo com foco de teclado
}
```

Singleton pelo mesmo motivo do histórico: uma nota, N telas. Desligar apaga —
o `didSet` é a regra de fim de vida inteira. Sem timer de expiração, sem Ajuste
de intervalo, sem persistência: reiniciou o app, a nota se foi.

### Ativação pelo menu

Um `NSMenuItem` "Nota rápida" com `state = active ? .on : .off`, dentro do
`menuNeedsUpdate` que já reconstrói o menu a cada abertura por causa do Pomodoro.

Ligar também chama `setExpandedDirect(true)`: a nota aparece na hora, sem exigir
que o usuário vá com o mouse até o notch.

### Conteúdo

Quando `active`, o `expandedContent` mostra **só** o `TextEditor` — toma a tela
como o Pomodoro e o espelho já tomam. Fundo transparente, SF Pro,
`.focused($noteFocused)` com autofoco na abertura.

**Texto simples, não rich text.** Negrito e itálico exigiriam
`NSAttributedString` e uma barra de formatação para uma nota que vive minutos.

### Teclado

`panel.allowsKeyboard = active` pela mesma assinatura Combine que o card de
pergunta usa (`KnoblerApp.swift:740`). Como o `NotchWindow` é `nonactivating`,
digitar na nota **não** tira o foco do app da frente.

### Hover

`NotchViewModel.setHover(false)` ganha uma guarda: `guard !QuickNote.shared.editing`.

- Campo com foco + mouse sai → **fica aberto**. Digitar nunca é interrompido.
- Esc solta o foco; a partir daí o mouse-out fecha normalmente.
- A nota continua **ligada** e volta com o texto no próximo hover. Só o
  interruptor do menu apaga.

---

## Testes

`tools/check.sh` (14 checks hoje) ganha o 15º, `quicknotecheck`, com dois
`selfCheck()`:

**`NotificationHistory.selfCheck()`**
- poda de 24 h remove o vencido e mantém o de 23 h;
- `webhookID` repetido substitui em vez de empilhar;
- ordem mais-recente-primeiro;
- `record` do mesmo `id` duas vezes (multi-monitor) grava uma só.

**`verticalTarget` — tabela do gesto**
| accumY | alvo |
|---|---|
| 30 | `.expanded` |
| 130 | `.history` |
| 130 → recuo pra 30 | `.expanded` |
| −30 | `.closed` |
| 10 | `nil` (ruído) |

`QuickNote` — um `didSet` de três linhas — não ganha teste. YAGNI vale pra teste
também.

## Validação visual

- **Histórico**: lista pura, entra em `tools/snapshot.sh` normalmente. Adicionar
  o cenário e o `NotificationHistory.swift` à lista manual de arquivos do script.
- **Nota**: `TextEditor` depende de `NSView` real e vira o ícone de "proibido" no
  `ImageRenderer` offscreen, igual ao `TextField` do `AskCardView`. Fica **fora**
  do harness; screenshot manual do app rodando, salvo em `docs/images/`, como os
  painéis de Ajustes.

## Fora de escopo

Sem persistência em disco (nenhuma das duas), sem busca no histórico, sem rich
text, sem timer de expiração da nota, sem ações nas linhas do histórico além do
clique que o card já faz.

Adicionar quando: alguém perder algo importante num restart (histórico em disco)
ou a lista passar de umas 40 linhas (busca).
