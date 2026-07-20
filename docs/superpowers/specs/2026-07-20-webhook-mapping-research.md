# Webhooks configuráveis — pesquisa (de-risk pré-plano)

**Data:** 2026-07-20 · **Alimenta:** `2026-07-20-webhook-mapping-design.md` → plano
**Método:** R1 (editor SwiftUI, opus) + R2 (prior art UX, haiku), focado.

## Achado decisivo

**O `TextSelection` do SwiftUI (ler/inserir no cursor de um `TextField`) é macOS 15+.**
Nosso deployment target é **14.2** → não existe. Logo, o editor de mapeamento **precisa**
de um `NSViewRepresentable` sobre **`NSTextView`** (não `NSTextField` — o `NSTextView` é
dono da própria seleção e a preserva ao perder o foco). Isso é o único nó técnico real; o
resto é conhecido.

## R1 — Editor lado-a-lado (código carregador)

Arquitetura: `HSplitView` — esquerda = N campos `CursorTextView` (wrapper AppKit) com um
**`InsertionRouter` compartilhado**; direita = `JSONTreeView` cujo tap na folha chama
`router.insert("{{\(path)}}")`. Três gotchas load-bearing:
1. **Folha da árvore usa `.onTapGesture`, NÃO `Button`** — `Button` rouba o first-responder
   do `NSTextView` (perde o cursor). `onTapGesture` sobre `Text` não.
2. **O router NÃO limpa o campo ativo no `textDidEndEditing`** — guarda o "último focado",
   pra o tap na árvore (que tira o foco) ainda achar onde inserir.
3. **Comprimentos em UTF-16** (`(str as NSString).length`) — `NSRange`/`selectedRange` são
   UTF-16; `string.count` quebra com emoji/acento composto.

```swift
enum TemplateField: Hashable { case title, body, url, icon, id }

final class InsertionRouter: ObservableObject {
    fileprivate weak var active: CursorTextView.Coordinator?
    func insert(_ text: String) { active?.insertAtCursor(text) }
}

struct CursorTextView: NSViewRepresentable {
    @Binding var text: String
    let fieldID: TemplateField
    let router: InsertionRouter
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false   // não estragar {{ }}
        tv.allowsUndo = true
        tv.font = .preferredFont(forTextStyle: .body)
        tv.string = text
        context.coordinator.textView = tv
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView, tv.string != text else { return }
        let sel = tv.selectedRange()
        tv.string = text
        tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CursorTextView; weak var textView: NSTextView?
        init(_ p: CursorTextView) { parent = p }
        func textDidChange(_ n: Notification) { parent.text = textView?.string ?? "" }
        func textDidBeginEditing(_ n: Notification) { parent.router.active = self }
        // NÃO limpar no textDidEndEditing (senão o tap na árvore não acha o campo)
        func insertAtCursor(_ s: String) {
            guard let tv = textView else { return }
            tv.window?.makeFirstResponder(tv)
            let sel = tv.selectedRange()
            guard tv.shouldChangeText(in: sel, replacementString: s) else { return }
            tv.textStorage?.replaceCharacters(in: sel, with: s)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: sel.location + (s as NSString).length, length: 0))
        }
    }
}
```

Árvore JSON: modelar num enum `JSONValue` (preserva tipo; **Bool vem como `NSNumber`** →
distinguir com `CFGetTypeID(n) == CFBooleanGetTypeID()`; **ordem de chaves não é preservada**
por `JSONSerialization` → ordenar por chave). `DisclosureGroup` recursivo, construindo o
dot-path (`a.b.0.c`); folha usa `.onTapGesture`. (R2: **expandir por padrão**, mostrar
**tipo + valor de amostra** por nó, tooltip com o path.)

```swift
indirect enum JSONValue { case string(String), number(Double), bool(Bool), null
    case array([JSONValue]); case object([(key:String, value:JSONValue)])
    static func from(_ a: Any) -> JSONValue {
        switch a {
        case let s as String: return .string(s)
        case let n as NSNumber:
            return CFGetTypeID(n)==CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let arr as [Any]: return .array(arr.map(JSONValue.from))
        case let d as [String:Any]: return .object(d.sorted{$0.key<$1.key}.map{(key:$0.key, value:.from($0.value))})
        default: return .null } }
}
```

Preview ao vivo: templates em `@State`, render `{{path}}`→valor numa função chamada no
`body` → **reativo por construção** (sem Combine). Motor: regex `\{\{\s*([^}]+?)\s*\}\}`,
substitui de trás pra frente; path dot-notation com índice de array; ausente → vazio.
(Reimplementar em Swift ~20 linhas pro preview local; o relay tem o mesmo motor em JS pra
o envio real.)

`insertText` vs `replaceCharacters`: usar `shouldChangeText` + `replaceCharacters` +
`didChangeText` (caminho documentado, com Undo). `NSTextView` sempre dentro de
`scrollableTextView()`.

Fontes: developer.apple.com (TextSelection [15+], NSViewRepresentable, FocusState, Cocoa
Text Architecture), Apple Forums 768930.

## R2 — Prior art (o que copiar)

Convergência (Zapier/n8n/Make/GHL): **árvore de dados sempre visível** + **clique/insert** +
**preview ao vivo ao lado**. Refinamentos a adotar (baratos):
- **Árvore expandida por padrão** (não colapsar arrays); **tipo + valor de amostra** por nó
  (`email: "a@b.com"`); tooltip com o path completo.
- **`{{ }}` cru** (texto), **sem pills** na v1 — versionável, simples; pills são polish futuro.
- Preview do resultado **ao lado, ao vivo** (n8n), contra o `lastPayload` capturado.
- Erro comum a evitar: usuário não achar campo aninhado → a árvore expandida + (futuro) uma
  busca resolvem. Campo faltando → vazio (já é o nosso motor).

Fora de escopo v1 (R2 confirma como polish): pills visuais, autocomplete no `{{`, busca na
árvore, validação "did you mean". Adicionar depois se incomodar.

Fontes: help.zapier.com, docs.n8n.io, help.make.com, ideas.gohighlevel.com, developer.cisco.com/meraki.

## Refinamentos que atualizam a spec

1. Editor de mapeamento: **wrapper AppKit `NSTextView` + `InsertionRouter`** (não SwiftUI
   `TextField` — `TextSelection` é 15+). Folha da árvore = `.onTapGesture` (não `Button`).
2. Árvore: **expandida por padrão**, tipo+valor por nó, tooltip do path.
3. `{{ }}` cru, sem pills/autocomplete/busca na v1 (polish).
4. Motor de template reimplementado em Swift (~20 linhas) pro preview local; JS no relay pro envio.
