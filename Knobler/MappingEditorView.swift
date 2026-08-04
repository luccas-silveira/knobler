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

// `TemplateField`, `JSONValue` e `renderTemplate` moraram aqui até a Fase 1 dos
// webhooks; agora vivem em `WebhookTemplate.swift`/`WebhookPresets.swift`, que
// não importam SwiftUI e têm gate próprio.

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

// MARK: - Editor

struct MappingEditorView: View {
    @ObservedObject var client: WebhookClient
    let profile: WebhookClient.WebhookProfile
    /// Preset escolhido no assistente: semeia os campos quando o perfil ainda
    /// não tem mapping. Payload real e edição do usuário sempre vencem — o
    /// preset nunca sobrescreve mapa salvo (006).
    var preset: WebhookPreset?
    /// JSON de exemplo já colado no assistente (008) — semeia a árvore enquanto
    /// nenhum payload de verdade chegou.
    var exemplo: JSONValue?
    var onClose: () -> Void

    @State private var title = ""
    @State private var body_ = ""
    @State private var url = ""
    @State private var idField = ""
    @State private var icon = ""
    @State private var sound = false
    @State private var root: JSONValue?
    @State private var fonte: FonteDaArvore = .nenhuma
    @State private var avisoDeColagem: String?
    @State private var ultimoPayloadAt: Double?
    @State private var origem: [String: Any]?
    /// O que o auto-mapeamento (005) chutou nesta árvore. `nil` = ainda não
    /// rodou (sem banner); vazio = rodou e nada casou (banner do convite).
    @State private var sugestao: [TemplateField: String]?
    @State private var loading = true
    @State private var saving = false
    @StateObject private var router = InsertionRouter()

    var body: some View {
        VStack(spacing: 0) {
            header
            if mostraBannerDoChute { bannerDoChute }
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
        .task { await acompanharPayload() }
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

    // MARK: auto-mapeamento (005)

    /// Chuta os campos VAZIOS a partir da árvore que está na tela. Roda uma vez
    /// por árvore nova (payload real ou JSON colado) — nunca por cima do que o
    /// usuário está digitando.
    private func autoMapear() {
        let vazios = Set(TemplateField.allCases.filter {
            valorDoCampo($0).trimmingCharacters(in: .whitespaces).isEmpty
        })
        guard !vazios.isEmpty else { sugestao = nil; return }   // nada a chutar, nada a anunciar
        let chute = AutoMap.sugerir(arvore: root, preset: preset, vazios: vazios)
        for (campo, template) in chute { escreverCampo(campo, template) }
        sugestao = chute
    }

    private func valorDoCampo(_ campo: TemplateField) -> String {
        switch campo {
        case .title: return title
        case .body:  return body_
        case .url:   return url
        case .id:    return idField
        }
    }

    private func escreverCampo(_ campo: TemplateField, _ v: String) {
        switch campo {
        case .title: title = v
        case .body:  body_ = v
        case .url:   url = v
        case .id:    idField = v
        }
    }

    /// O banner some ao primeiro toque em qualquer campo sugerido.
    private var mostraBannerDoChute: Bool {
        guard let sugestao else { return false }
        guard !sugestao.isEmpty else { return root != nil }
        return sugestao.allSatisfy { valorDoCampo($0.key) == $0.value }
    }

    private var bannerDoChute: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars").foregroundStyle(.secondary)
            Text(sugestao?.isEmpty == false
                 ? "Preenchi os campos vazios a partir deste payload — confira e edite."
                 : "Não reconheci este payload — clique num valor da árvore pra inserir.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if sugestao?.isEmpty == false {
                Button("Limpar sugestões") {
                    // só o que o chute preencheu e o usuário não editou
                    for (campo, template) in sugestao ?? [:] where valorDoCampo(campo) == template {
                        escreverCampo(campo, "")
                    }
                    sugestao = nil
                }
                .buttonStyle(.borderless).controlSize(.small)
            }
        }
        .padding(.horizontal).padding(.bottom, 8)
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
                    // só recarrega a árvore do payload — NÃO reescreve os campos editados
                    Task { await reloadPayload() }
                } label: {
                    Label("Recarregar", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding([.horizontal, .top])

            if let aviso = avisoDeColagem {
                avisoInline(aviso)
            }

            if let faixa = fonte.faixa {
                faixaDeExemplo(faixa)
            }

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
                    Text("Ou monte o mapa agora, colando um JSON de exemplo.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    botaoColar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }

    /// Um clique: lê o clipboard, parseia e monta a árvore (008). Sem campo de
    /// texto — o payload real tem quilobytes e ninguém revisa isso digitando.
    private var botaoColar: some View {
        Button {
            colarExemplo()
        } label: {
            Label("Colar JSON de exemplo", systemImage: "doc.on.clipboard")
        }
        .controlSize(.small)
    }

    private func avisoInline(_ texto: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(texto, systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Colar de novo") { colarExemplo() }
                Button("Descartar") { avisoDeColagem = nil }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
        .padding(.horizontal)
    }

    private func faixaDeExemplo(_ texto: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary)
            Text(texto).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if fonte.podeDescartar {
                Button("Descartar") {
                    root = nil
                    fonte = .nenhuma
                }
                .buttonStyle(.borderless).controlSize(.small)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
        .padding(.horizontal)
    }

    private func colarExemplo() {
        switch ExemploColado.avaliar(NSPasteboard.general.string(forType: .string)) {
        case .arvore(let v):
            root = v
            fonte = .exemplo
            avisoDeColagem = nil
            autoMapear()                                       // 005: uma vez por árvore nova
        case .invalido(let trecho):
            avisoDeColagem = ExemploColado.mensagemDeErro(trecho)   // árvore anterior fica intacta
        case .vazio:
            avisoDeColagem = ExemploColado.mensagemDeErro("")
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
            origem = obj["_origem"] as? [String: Any]   // preservada em edição manual
        } else if let preset, preset.mapaAplicavelSemPayload {
            origem = ["preset": preset.id, "versao": preset.versao]
            let mapa = preset.mapaSugerido
            title = mapa[.title] ?? ""
            body_ = mapa[.body] ?? ""
            url = mapa[.url] ?? ""
            idField = mapa[.id] ?? ""
        }
        icon = detail.icon ?? ""
        // árvore a partir do último payload capturado
        ultimoPayloadAt = detail.lastPayloadAt
        if let payload = detail.lastPayload, let data = payload.data(using: .utf8),
           let any = try? JSONSerialization.jsonObject(with: data) {
            root = JSONValue.from(any)
            fonte = .real
        } else if let exemplo, fonte == .nenhuma {
            root = exemplo
            fonte = .exemplo
        } else if fonte != .exemplo {
            root = nil
        }
        autoMapear()
    }

    /// Recarrega só a árvore do último payload capturado, sem tocar nos campos
    /// (title/body/url/id/sound/icon) — evita perder edições não salvas ao clicar "Recarregar".
    private func reloadPayload() async {
        guard let detail = await client.getProfile(profile.id) else { return }
        aplicar(detail)
    }

    /// Polling de 2s enquanto o sheet está aberto (007): payload real vence o
    /// exemplo colado e troca a árvore sozinho — é o instante que se esperava.
    private func acompanharPayload() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let detail = await client.getProfile(profile.id) else { continue }
            guard detail.lastPayloadAt != ultimoPayloadAt else { continue }
            aplicar(detail)
        }
    }

    private func aplicar(_ detail: WebhookClient.ProfileDetail) {
        ultimoPayloadAt = detail.lastPayloadAt
        guard let payload = detail.lastPayload, let data = payload.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data) else { return }
        root = JSONValue.from(any)
        fonte = fonte.comPayloadReal
        autoMapear()   // chaveado pelo lastPayloadAt: uma vez por payload novo
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var mapping: [String: Any] = [
            "title": title,
            "body": body_,
            "url": url,
            "sound": sound,
            "id": idField,
        ]
        // 006: a origem fica gravada no próprio mapping; chave desconhecida é
        // ignorada pelo relay (é o que permite guardá-la sem campo novo no banco).
        if let origem { mapping["_origem"] = origem }
        guard let data = try? JSONSerialization.data(withJSONObject: mapping),
              let json = String(data: data, encoding: .utf8) else { return }
        await client.updateProfile(profile.id, mapping: json, icon: icon)
        onClose()
    }
}
