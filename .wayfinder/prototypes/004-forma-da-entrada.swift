//
//  Protótipo do ticket 004 — forma da entrada do primeiro perfil de webhook.
//
//  NÃO faz parte do app. Autônomo de propósito: o editor real usa HSplitView e
//  não renderiza no harness de snapshot, então a comparação tem que ser clicada.
//
//  swiftc -O -o /tmp/proto004 .wayfinder/prototypes/004-forma-da-entrada.swift && /tmp/proto004
//
//  Duas formas na mesma janela, alternadas pelo seletor do topo:
//    A) Assistente de passos  — criar → serviço → link → esperar POST → confirmar
//    B) Painel incrementado   — o Form .grouped de hoje + o sheet Mapear, ambos crescidos
//
//  Payload de exemplo: OpportunityCreate real do GHL (.wayfinder/research/ghl.md).
//

import SwiftUI
import AppKit

// MARK: - Estado inicial por argumento (pra capturar tela sem simular clique)
// uso: proto004 [forma 0|1] [passo 0..4] [sheet 0|1]

let argv = CommandLine.arguments
func arg(_ i: Int) -> Int { argv.count > i ? Int(argv[i]) ?? 0 : 0 }
let argForma = arg(1)
let argPasso = arg(2)
let argSheet = arg(3) == 1

// MARK: - Dados de mentira compartilhados

let payloadGHL = """
{
  "type": "OpportunityCreate",
  "locationId": "3jJ0coeqWCZMAosyGQ6K",
  "id": "UHXrFfZGSH5rj7z5rdDP",
  "name": "Test 2",
  "assignedTo": null,
  "contactId": "VQxH1EeoFPg9uhhnCeJx",
  "pipelineId": "WQ7tyljQSXAg7GuTgYdd",
  "status": "open",
  "dateAdded": "2025-11-07T12:40:44.510Z",
  "timestamp": "2025-11-07T12:46:45.953Z",
  "webhookId": "881b9415-5d35-4ff1-a667-0545b80b96c0"
}
"""

struct Servico: Identifiable, Hashable {
    let id: String
    let nome: String
    let emoji: String
    let instrucao: String
    let sugestaoTitulo: String
    let sugestaoCorpo: String
    let ressalva: String?
}

let servicos: [Servico] = [
    Servico(id: "ghl", nome: "GoHighLevel", emoji: "🟡",
            instrucao: "Em Settings → Integrations → Webhooks, cole o link e escolha os eventos.",
            sugestaoTitulo: "{{type}}", sugestaoCorpo: "{{name}} — {{status}}",
            ressalva: "Vale para webhook de Marketplace. Webhook de workflow tem corpo que você mesmo monta — aí o mapa é feito na mão."),
    Servico(id: "clickup", nome: "ClickUp", emoji: "🟣",
            instrucao: "Em Settings → Integrations → Webhooks, cole o link e marque os eventos.",
            sugestaoTitulo: "{{event}}", sugestaoCorpo: "{{history_items.0.field}} mudou",
            ressalva: "O ClickUp não manda o nome da tarefa no webhook — só o id. Título vai sair genérico."),
    Servico(id: "notion", nome: "Notion", emoji: "⚫️",
            instrucao: "Na database, Automations → New → Send webhook, cole o link.",
            sugestaoTitulo: "{{data.properties.Name.title.0.plain_text}}", sugestaoCorpo: "{{data.properties.Status.status.name}}",
            ressalva: "O Notion não manda a URL da página — só o id. O link do card fica vazio até existir transformação."),
    Servico(id: "outro", nome: "Outro serviço", emoji: "🔔",
            instrucao: "Cole o link onde o serviço pede a URL do webhook.",
            sugestaoTitulo: "", sugestaoCorpo: "", ressalva: nil),
]

let linkFake = "https://relay.knobler.app/w/8f3c2a1e-4b7d-49aa-9c10-2e5f7b0d1a44"

func copiar(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

// MARK: - =====================  FORMA A: ASSISTENTE  =====================

struct AssistenteView: View {
    @State private var passo = argPasso
    @State private var nome = "Vendas"
    @State private var servico = servicos[0]
    @State private var chegou = argPasso >= 4
    @State private var titulo = argPasso >= 4 ? servicos[0].sugestaoTitulo : ""
    @State private var corpo = argPasso >= 4 ? servicos[0].sugestaoCorpo : ""

    var body: some View {
        VStack(spacing: 0) {
            trilha
            Divider()
            Group {
                switch passo {
                case 0: passoNome
                case 1: passoServico
                case 2: passoLink
                case 3: passoEspera
                default: passoConfirmar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            Divider()
            rodape
        }
    }

    private var trilha: some View {
        HStack(spacing: 0) {
            ForEach(Array(["Nome", "Serviço", "Link", "Primeiro envio", "Mapa"].enumerated()), id: \.offset) { i, t in
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(i <= passo ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 18, height: 18)
                        if i < passo {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        } else {
                            Text("\(i + 1)").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(i == passo ? Color.white : Color.secondary)
                        }
                    }
                    Text(t).font(.caption).foregroundStyle(i == passo ? .primary : .secondary)
                    if i < 4 { Rectangle().fill(.quaternary).frame(height: 1).frame(minWidth: 12) }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var passoNome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Como você chama esse perfil?").font(.title3.weight(.semibold))
            Text("Cada perfil tem um link próprio. Um por serviço costuma bastar.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Nome do perfil", text: $nome)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 320)
        }
    }

    private var passoServico: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("De onde vêm as notificações?").font(.title3.weight(.semibold))
            Text("Isso só define a sugestão de mapa e as instruções. Dá pra mudar depois.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(servicos) { s in
                Button {
                    servico = s
                } label: {
                    HStack {
                        Text(s.emoji).frame(width: 22)
                        Text(s.nome)
                        Spacer()
                        if servico == s { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(servico == s ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 380)
            }
        }
    }

    private var passoLink: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cole este link no \(servico.nome)").font(.title3.weight(.semibold))
            HStack {
                Text(linkFake).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Copiar") { copiar(linkFake) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
            .frame(maxWidth: 520)
            Label(servico.instrucao, systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let r = servico.ressalva {
                Label(r, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 520, alignment: .leading)
            }
        }
    }

    private var passoEspera: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dispare um evento de teste").font(.title3.weight(.semibold))
            HStack(spacing: 10) {
                if chegou {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Recebido agora — `OpportunityCreate`").font(.callout)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Esperando o primeiro envio nesse link…").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: 520, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))

            HStack {
                Button("Simular chegada (protótipo)") { chegou = true; aplicarSugestao() }
                Button("Colar um JSON de exemplo") { chegou = true; aplicarSugestao() }
            }
            Text("Não precisa ficar olhando: pode fechar, o perfil continua esperando.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var passoConfirmar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confere se o card ficou certo").font(.title3.weight(.semibold))
            Label("Sugerido a partir do que chegou. Toque num campo pra ajustar.",
                  systemImage: "wand.and.stars").font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    campo("Título", $titulo)
                    campo("Corpo", $corpo)
                    Button("Abrir o editor completo…") {}
                        .buttonStyle(.link).font(.callout)
                }
                .frame(width: 300)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Como vai chegar").font(.caption).foregroundStyle(.secondary)
                    cardPreview(titulo: render(titulo), corpo: render(corpo))
                }
            }
        }
    }

    private func campo(_ l: String, _ b: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.caption).foregroundStyle(.secondary)
            TextField("", text: b).textFieldStyle(.roundedBorder).font(.callout.monospaced())
        }
    }

    private func aplicarSugestao() {
        titulo = servico.sugestaoTitulo
        corpo = servico.sugestaoCorpo
    }

    private var rodape: some View {
        HStack {
            Button("Cancelar") {}
            Spacer()
            if passo > 0 { Button("Voltar") { passo -= 1 } }
            Button(passo == 4 ? "Concluir" : "Continuar") {
                if passo < 4 { passo += 1 }
            }
            .buttonStyle(.borderedProminent)
            .disabled(passo == 3 && !chegou)
        }
        .padding(16)
    }
}

// MARK: - =====================  FORMA B: PAINEL INCREMENTADO  =====================

struct PainelView: View {
    @State private var ligado = true
    @State private var perfis: [PerfilFake] = [
        PerfilFake(nome: "Vendas", emoji: "🟡", servico: "GoHighLevel", estado: .esperando),
        PerfilFake(nome: "Tarefas", emoji: "🟣", servico: "ClickUp", estado: .mapeado("há 3 min")),
    ]
    @State private var editando: PerfilFake?
    @State private var abriuAuto = false

    struct PerfilFake: Identifiable, Hashable {
        let id = UUID()
        var nome: String
        var emoji: String
        var servico: String
        var estado: Estado
        enum Estado: Hashable {
            case novo, esperando, recebido, mapeado(String)
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Receber notificações externas", isOn: $ligado)
                if ligado {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle().fill(.green).frame(width: 8, height: 8)
                            Text("Conectado").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if ligado {
                Section("Perfis") {
                    ForEach(perfis) { p in linha(p) }
                    Menu {
                        ForEach(servicos) { s in
                            Button("\(s.emoji)  \(s.nome)") {
                                perfis.append(PerfilFake(nome: s.nome, emoji: s.emoji,
                                                         servico: s.nome, estado: .novo))
                            }
                        }
                    } label: {
                        Label("Adicionar perfil", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .sheet(item: $editando) { p in
            SheetMapear(perfil: p, fechar: { editando = nil })
        }
        .onAppear {
            if argSheet && !abriuAuto { abriuAuto = true; editando = perfis[0] }
        }
    }

    @ViewBuilder private func linha(_ p: PerfilFake) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(p.emoji).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.nome)
                    Text(legenda(p.estado)).font(.caption).foregroundStyle(cor(p.estado))
                }
                Spacer()
                Button { copiar(linkFake) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copiar o link do webhook")
                Menu {
                    Button("Mapear campos…") { editando = p }
                    Button("Renomear…") {}
                    Button("Gerar link novo…") {}
                    Divider()
                    Button("Apagar perfil", role: .destructive) {}
                } label: { Image(systemName: "ellipsis.circle") }
                    .buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
            }
            // A incrementação: uma faixa de próximo-passo dentro da própria linha.
            switch p.estado {
            case .novo, .esperando:
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill").foregroundStyle(.tint)
                    Text("Cole o link no \(p.servico) e dispare um evento — o mapa se sugere sozinho.")
                        .font(.caption)
                    Spacer()
                    Button("Copiar link") { copiar(linkFake) }.controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.10)))
            case .recebido:
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(.tint)
                    Text("Chegou um payload. Confira o mapa sugerido.").font(.caption)
                    Spacer()
                    Button("Mapear…") { editando = p }.controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.10)))
            case .mapeado:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }

    private func legenda(_ e: PerfilFake.Estado) -> String {
        switch e {
        case .novo: return "Perfil novo — nenhum envio ainda"
        case .esperando: return "Esperando o primeiro envio"
        case .recebido: return "Payload recebido — sem mapa"
        case .mapeado(let q): return "Último webhook \(q)"
        }
    }

    private func cor(_ e: PerfilFake.Estado) -> Color {
        if case .mapeado = e { return .secondary }
        return .orange
    }
}

/// O sheet "Mapear" de hoje, incrementado: faixa de origem do payload no topo do
/// painel direito e banner de auto-mapeamento no esquerdo.
struct SheetMapear: View {
    let perfil: PainelView.PerfilFake
    var fechar: () -> Void
    @State private var titulo = "{{type}}"
    @State private var corpo = "{{name}} — {{status}}"
    @State private var autoAplicado = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mapear notificação").font(.headline)
                    Text(perfil.nome).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            Divider()
            HSplitView {
                esquerda.frame(minWidth: 340, idealWidth: 380)
                direita.frame(minWidth: 300, idealWidth: 340)
            }
            Divider()
            HStack {
                Button("Cancelar", action: fechar)
                Spacer()
                Button("Salvar", action: fechar).buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 520)
    }

    private var esquerda: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if autoAplicado {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "wand.and.stars").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mapa sugerido a partir do payload que chegou.").font(.caption)
                            Text("Nada foi salvo ainda — ajuste o que quiser.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Desfazer") { titulo = ""; corpo = ""; autoAplicado = false }
                            .controlSize(.small)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.10)))
                }
                campo("Título", $titulo)
                campo("Corpo", $corpo)
                campo("URL ao abrir", .constant(""))
                Divider()
                Text("Prévia").font(.caption).foregroundStyle(.secondary)
                cardPreview(titulo: render(titulo), corpo: render(corpo))
            }
            .padding()
        }
    }

    private var direita: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A incrementação: as quatro fontes de payload viradas para cima.
            HStack(spacing: 6) {
                Text("Dados").font(.caption).foregroundStyle(.secondary)
                Menu("Ao vivo") {
                    Button("Ao vivo — o que chegar no link") {}
                    Button("Colar um JSON…") {}
                    Button("Exemplo do \(perfil.servico)") {}
                    Divider()
                    Button("Envio anterior (2 de 5)") {}
                }
                .fixedSize()
                Spacer()
            }
            .padding([.horizontal, .top])

            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("Recebido há 8 s — OpportunityCreate").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(linhasPayload(), id: \.0) { chave, valor in
                        HStack(spacing: 6) {
                            Text(chave).font(.callout.monospaced())
                            Text(valor).font(.callout.monospaced()).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 0)
                            Image(systemName: "plus.circle").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal).padding(.bottom)
            }
            Divider()
            Text("Clique num valor para inserir no campo em foco.")
                .font(.caption).foregroundStyle(.secondary).padding([.horizontal, .bottom], 10)
        }
    }

    private func campo(_ l: String, _ b: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.caption).foregroundStyle(.secondary)
            TextField("", text: b).textFieldStyle(.roundedBorder).font(.callout.monospaced())
        }
    }
}

// MARK: - Peças comuns

func linhasPayload() -> [(String, String)] {
    guard let d = payloadGHL.data(using: .utf8),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
    return o.sorted { $0.key < $1.key }.map { ($0.key, "\($0.value)") }
}

func render(_ tpl: String) -> String {
    guard let d = payloadGHL.data(using: .utf8),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return tpl }
    var s = tpl
    for (k, v) in o { s = s.replacingOccurrences(of: "{{\(k)}}", with: "\(v)") }
    // caminhos aninhados que não existem neste payload viram vazio, como no relay
    while let r = s.range(of: "\\{\\{[^}]*\\}\\}", options: .regularExpression) {
        s.replaceSubrange(r, with: "")
    }
    return s.trimmingCharacters(in: .whitespaces)
}

func cardPreview(titulo: String, corpo: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        RoundedRectangle(cornerRadius: 8).fill(.tertiary).frame(width: 34, height: 34)
            .overlay(Text("🟡"))
        VStack(alignment: .leading, spacing: 3) {
            Text(titulo.isEmpty ? "Título vazio" : titulo)
                .font(.headline).foregroundStyle(titulo.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            if !corpo.isEmpty { Text(corpo).font(.callout).foregroundStyle(.secondary) }
        }
        Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.85)))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    .environment(\.colorScheme, .dark)
}

// MARK: - Casca

struct Root: View {
    @State private var forma = argForma
    @State private var mostrarAssistente = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $forma) {
                Text("A — Assistente de passos").tag(0)
                Text("B — Painel incrementado").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(12)
            Divider()
            if forma == 0 {
                AssistenteView()
            } else {
                PainelView()
            }
        }
        .frame(width: 980, height: 620)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                   styleMask: [.titled, .closable, .resizable],
                   backing: .buffered, defer: false)
win.title = "Protótipo 004 — forma da entrada"
win.contentView = NSHostingView(rootView: Root())
win.center()
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()
