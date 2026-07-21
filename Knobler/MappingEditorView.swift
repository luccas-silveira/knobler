//
//  MappingEditorView.swift
//  Knobler
//
//  Editor de mapeamento lado-a-lado: à esquerda o usuário monta os campos da
//  notificação (title/body/url/id + ícone + som) usando {{caminho}}; à direita a
//  árvore do último payload capturado. Clicar numa folha da árvore insere o
//  {{caminho}} no cursor do campo que estava focado, e o preview atualiza ao vivo.
//
//  Peças load-bearing (ver pesquisa 2026-07-20-webhook-mapping-research.md, R1):
//  - `CursorTextView` (wrapper NSTextView) porque `TextSelection`/cursor do SwiftUI
//    é macOS 15+ e o alvo é 14.2. NSTextView é dono da própria seleção e a preserva
//    ao perder o foco.
//  - Folha da árvore usa `.onTapGesture` (NÃO `Button`) — Button roubaria o
//    first-responder do NSTextView e perderia o cursor.
//  - O `InsertionRouter` NÃO limpa o campo ativo no textDidEndEditing (senão o tap
//    na árvore, que tira o foco, não acha onde inserir).
//  - Comprimentos em UTF-16 ((s as NSString).length) — NSRange é UTF-16.
//

import SwiftUI
import AppKit

// MARK: - Roteamento de inserção no cursor

enum TemplateField: Hashable { case title, body, url, id }

final class InsertionRouter: ObservableObject {
    fileprivate weak var active: CursorTextView.Coordinator?
    func insert(_ text: String) { active?.insertAtCursor(text) }
}

/// Campo de texto AppKit (NSTextView) que preserva a seleção ao perder o foco e
/// expõe inserção no cursor via `InsertionRouter`.
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
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.allowsUndo = true
        tv.font = .preferredFont(forTextStyle: .body)
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.string = text
        context.coordinator.textView = tv
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
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
        var parent: CursorTextView
        weak var textView: NSTextView?
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

// MARK: - Modelo da árvore JSON

indirect enum JSONValue {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    static func from(_ a: Any) -> JSONValue {
        switch a {
        case let s as String: return .string(s)
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let arr as [Any]: return .array(arr.map(JSONValue.from))
        case let d as [String: Any]:
            return .object(d.sorted { $0.key < $1.key }.map { (key: $0.key, value: .from($0.value)) })
        default: return .null
        }
    }

    /// Texto de amostra por nó (folha) — mostrado ao lado da chave na árvore.
    var sample: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .number(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let a): return "[\(a.count)]"
        case .object(let o): return "{\(o.count)}"
        }
    }

    var isLeaf: Bool {
        switch self {
        case .array, .object: return false
        default: return true
        }
    }
}

// MARK: - Árvore recursiva (folha = onTapGesture, insere {{path}})

struct JSONTreeView: View {
    let value: JSONValue
    let path: String                 // dot-path acumulado (ex.: "a.b.0.c")
    let label: String                // chave/índice exibido neste nó
    let router: InsertionRouter

    var body: some View {
        switch value {
        case .object(let pairs):
            DisclosureGroup(isExpanded: .constant(true)) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    JSONTreeView(value: pair.value,
                                 path: join(path, pair.key),
                                 label: pair.key, router: router)
                }
            } label: { nodeLabel(typeHint: "{}") }
        case .array(let items):
            DisclosureGroup(isExpanded: .constant(true)) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    JSONTreeView(value: item,
                                 path: join(path, String(idx)),
                                 label: "[\(idx)]", router: router)
                }
            } label: { nodeLabel(typeHint: "[]") }
        default:
            leaf
        }
    }

    private var leaf: some View {
        HStack(spacing: 6) {
            Text(label).font(.callout.monospaced())
            Text(value.sample)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            Image(systemName: "plus.circle")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .help(path)                                       // tooltip = path completo
        .onTapGesture { router.insert("{{\(path)}}") }    // NÃO Button (perderia o cursor)
    }

    private func nodeLabel(typeHint: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.callout.monospaced())
            Text(typeHint).font(.caption).foregroundStyle(.tertiary)
        }
        .help(path)
    }

    private func join(_ base: String, _ comp: String) -> String {
        base.isEmpty ? comp : "\(base).\(comp)"
    }
}

// MARK: - Motor de render local (mesmo comportamento do relay, pro preview)

/// Substitui cada `{{ caminho }}` pelo valor resolvido no payload; ausente → vazio.
func renderTemplate(_ tpl: String, _ root: JSONValue?) -> String {
    guard let regex = try? NSRegularExpression(pattern: "\\{\\{\\s*([^}]+?)\\s*\\}\\}") else { return tpl }
    let ns = tpl as NSString
    let matches = regex.matches(in: tpl, range: NSRange(location: 0, length: ns.length))
    var result = tpl
    // substitui de trás pra frente (ranges anteriores não se deslocam)
    for m in matches.reversed() {
        let full = m.range(at: 0)
        let pathRange = m.range(at: 1)
        let path = ns.substring(with: pathRange)
        let value = resolve(path, root)
        let r = Range(full, in: result)!
        result.replaceSubrange(r, with: value)
    }
    return result
}

/// Resolve um dot-path (com índices de array) contra a árvore. Ausente → "".
private func resolve(_ path: String, _ root: JSONValue?) -> String {
    guard var node = root else { return "" }
    for comp in path.split(separator: ".", omittingEmptySubsequences: true) {
        let key = String(comp)
        switch node {
        case .object(let pairs):
            guard let hit = pairs.first(where: { $0.key == key })?.value else { return "" }
            node = hit
        case .array(let items):
            guard let idx = Int(key), idx >= 0, idx < items.count else { return "" }
            node = items[idx]
        default:
            return ""
        }
    }
    switch node {
    case .string(let s): return s
    case .number(let d): return d == d.rounded() ? String(Int(d)) : String(d)
    case .bool(let b): return b ? "true" : "false"
    case .null: return ""
    // objeto/array inteiros não têm representação de texto útil no template
    case .array, .object: return ""
    }
}

// MARK: - Editor

struct MappingEditorView: View {
    @ObservedObject var client: WebhookClient
    let profile: WebhookClient.WebhookProfile
    var onClose: () -> Void

    @State private var title = ""
    @State private var body_ = ""
    @State private var url = ""
    @State private var idField = ""
    @State private var icon = ""
    @State private var sound = false
    @State private var root: JSONValue?
    @State private var loading = true
    @State private var saving = false
    @StateObject private var router = InsertionRouter()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                leftPane
                    .frame(minWidth: 320, idealWidth: 380)
                rightPane
                    .frame(minWidth: 260, idealWidth: 320)
            }
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 480)
        .task { await load() }
    }

    // MARK: cabeçalho / rodapé

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mapear notificação").font(.headline)
                Text(profile.name).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if loading { ProgressView().controlSize(.small) }
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button("Cancelar") { onClose() }
            Spacer()
            Button("Salvar") { Task { await save() } }
                .buttonStyle(.borderedProminent)
                .disabled(saving)
        }
        .padding()
    }

    // MARK: painel esquerdo — campos + preview

    private var leftPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                field("Título", $title, .title, minHeight: 46)
                field("Corpo", $body_, .body, minHeight: 70)
                field("URL ao abrir", $url, .url, minHeight: 46)
                field("ID (dedupe)", $idField, .id, minHeight: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ícone (URL ou emoji)").font(.caption).foregroundStyle(.secondary)
                    TextField("ex.: 🔔 ou https://…/avatar.png", text: $icon)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Tocar som ao chegar", isOn: $sound)

                Divider().padding(.vertical, 4)

                Text("Prévia").font(.caption).foregroundStyle(.secondary)
                previewCard
            }
            .padding()
        }
    }

    private func field(_ label: String, _ binding: Binding<String>,
                       _ id: TemplateField, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            CursorTextView(text: binding, fieldID: id, router: router)
                .frame(minHeight: minHeight)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            let renderedTitle = renderTemplate(title, root)
            let renderedBody = renderTemplate(body_, root)
            Text(renderedTitle.isEmpty ? "Título vazio" : renderedTitle)
                .font(.headline)
                .foregroundStyle(renderedTitle.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            if !renderedBody.isEmpty {
                Text(renderedBody).font(.callout).foregroundStyle(.secondary)
            }
            let renderedURL = renderTemplate(url, root)
            if !renderedURL.isEmpty {
                Text(renderedURL).font(.caption.monospaced()).foregroundStyle(.blue)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quinary))
    }

    // MARK: painel direito — árvore do payload

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Dados do teste").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await load() }
                } label: {
                    Label("Recarregar", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding([.horizontal, .top])

            if let root {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        JSONTreeView(value: root, path: "", label: "payload", router: router)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Mande um webhook de teste para o link deste perfil e clique em Recarregar.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }

    // MARK: carregar / salvar

    private func load() async {
        loading = true
        defer { loading = false }
        guard let detail = await client.getProfile(profile.id) else { return }
        // campos a partir do mapping JSON {title,body,url,sound,id}
        if let mapping = detail.mapping, let data = mapping.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            title = obj["title"] as? String ?? ""
            body_ = obj["body"] as? String ?? ""
            url = obj["url"] as? String ?? ""
            idField = obj["id"] as? String ?? ""
            sound = obj["sound"] as? Bool ?? false
        }
        icon = detail.icon ?? ""
        // árvore a partir do último payload capturado
        if let payload = detail.lastPayload, let data = payload.data(using: .utf8),
           let any = try? JSONSerialization.jsonObject(with: data) {
            root = JSONValue.from(any)
        } else {
            root = nil
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let mapping: [String: Any] = [
            "title": title,
            "body": body_,
            "url": url,
            "sound": sound,
            "id": idField,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: mapping),
              let json = String(data: data, encoding: .utf8) else { return }
        await client.updateProfile(profile.id, mapping: json, icon: icon)
        onClose()
    }
}
