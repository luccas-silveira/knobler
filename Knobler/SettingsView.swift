//
//  SettingsView.swift
//  Knobler
//
//  Janela de Ajustes no estilo do Ajustes do Sistema: sidebar com painéis
//  (Geral, Notch, Ditado, Pomodoro, Lembretes, Descanso, Notificações
//  externas, Mensagens) + detalhe em Form agrupado. O SettingsRouter permite
//  abrir a janela já num painel específico (ex.: menu do Pomodoro).
//

import AppKit
import SwiftUI
import Carbon.HIToolbox

// Fora do AppDelegate pra `tools/snapshot.sh` compilar os Ajustes sem ele.
extension KeyboardShortcuts.Name {
    static let abrirNotch = KeyboardShortcuts.Name(
        "abrirNotch", default: .init(carbonKeyCode: kVK_ANSI_K, carbonModifiers: controlKey | optionKey))
}

// MARK: - Painéis

enum SettingsPane: String, CaseIterable, Identifiable {
    case geral, notch, desenho, ditado, pomodoro, lembretes, descanso, webhooks, mensagens
    case plugins, permissoes, monitores
    var id: String { rawValue }

    var title: String {
        switch self {
        case .geral: return "Geral"
        case .notch: return "Notch"
        case .desenho: return "Desenho"
        case .ditado: return "Ditado"
        case .pomodoro: return "Pomodoro"
        case .lembretes: return "Alertas programados"
        case .descanso: return "Descanso"
        case .webhooks: return "Notificações externas"
        case .mensagens: return "Mensagens"
        case .plugins: return "Plugins"
        case .permissoes: return "Permissões"
        case .monitores: return "Monitores"
        }
    }

    var symbol: String {
        switch self {
        case .geral: return "gearshape.fill"
        case .notch: return "macbook.gen2"
        case .desenho: return "pencil.tip.crop.circle"
        case .ditado: return "mic.fill"
        case .pomodoro: return "timer"
        case .lembretes: return "bell.badge.fill"
        case .descanso: return "moon.zzz.fill"
        case .webhooks: return "bell.and.waves.left.and.right.fill"
        case .mensagens: return "bubble.left.and.bubble.right.fill"
        case .plugins: return "square.grid.2x2.fill"
        case .permissoes: return "lock.shield.fill"
        case .monitores: return "display"
        }
    }

    /// Painel de peça desinstalada não entra na lista — some, sem item
    /// acinzentado (002). Painel que não é de peça nenhuma (Geral, Notch,
    /// Permissões) nunca sai.
    enum Grupo: String, CaseIterable {
        case sistema = "Sistema", features = "Features", integracoes = "Integrações"
    }

    var grupo: Grupo {
        switch self {
        case .geral, .notch, .permissoes, .plugins: return .sistema
        case .webhooks, .mensagens: return .integracoes
        default: return .features
        }
    }

    // ponytail: lista manual dos rótulos de cada painel; opção nova só aparece
    // na busca se entrar aqui.
    var palavras: [String] {
        switch self {
        case .geral: return ["HUD", "volume", "brilho", "bateria", "música", "visualizador", "calendário",
                             "reunião", "silenciar", "microfone", "atualizações", "login", "API", "prateleira",
                             "capturas de tela", "tela cheia", "agentes", "Claude", "espelho", "câmera"]
        case .notch: return ["atalho", "teclado", "clique", "hover", "mouse", "atraso", "ordem", "seções", "esconder", "ações rápidas", "atalhos"]
        case .desenho: return ["anotação", "traço", "cor", "ferramenta", "quadro", "fundo", "desvanecer"]
        case .ditado: return ["microfone", "Control", "ativação", "motor", "IA", "formatação", "endpoint"]
        case .pomodoro: return ["foco", "pausa", "durações", "fase", "timer"]
        case .lembretes: return ["lembrete", "alerta", "horário", "frequência", "som"]
        case .descanso: return ["pausa", "bloqueio", "olhos", "frequência"]
        case .webhooks: return ["webhook", "perfil", "push", "credenciais"]
        case .mensagens: return ["rede local", "identidade", "nome", "Mac"]
        case .plugins: return ["peça", "instalar", "desinstalar", "marketplace", "vitrine"]
        case .permissoes: return ["acessibilidade", "microfone", "calendário", "Bluetooth", "gravação de tela", "TCC"]
        case .monitores: return ["brilho", "contraste", "DDC", "som", "mudo", "atalhos", "HUD", "escurecimento"]
        }
    }

    /// Busca da barra lateral: título ou rótulo de opção, sem acento nem caixa.
    func combina(_ busca: String) -> Bool {
        let b = busca.trimmingCharacters(in: .whitespaces)
        return b.isEmpty || title.localizedStandardContains(b) || palavras.contains { $0.localizedStandardContains(b) }
    }

    static var visiveis: [SettingsPane] {
        let escondidos = PluginHost.shared.paineisEscondidos
        return allCases.filter { !escondidos.contains($0.rawValue) }
    }

    var color: Color {
        switch self {
        case .geral: return .gray
        case .notch: return .black
        case .desenho: return .yellow
        case .ditado: return .blue
        case .pomodoro: return .red
        case .lembretes: return .orange
        case .descanso: return .indigo
        case .webhooks: return .purple
        case .mensagens: return .green
        case .plugins: return .cyan
        case .permissoes: return .brown
        case .monitores: return .cyan
        }
    }
}

/// Seleção compartilhada — o app seta o painel antes de mostrar a janela.
final class SettingsRouter: ObservableObject {
    @Published var pane: SettingsPane = .geral
}

// MARK: - Shell (sidebar + detalhe)

struct SettingsView: View {
    @ObservedObject var router: SettingsRouter
    @ObservedObject var webhookClient: WebhookClient
    /// A barra lateral lê `SettingsPane.visiveis`, que consulta o host. Sem
    /// observar o host aqui, instalar ou desinstalar pela vitrine só mudaria a
    /// lista na próxima abertura da janela.
    // periphery:ignore
    @ObservedObject private var host = PluginHost.shared
    @State private var busca = ""

    var body: some View {
        // .constant(.all): sem isso o divisor colapsa a sidebar por arrasto e,
        // sem toolbar/menu (LSUIElement), não existe caminho de volta
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: selection) {
              ForEach(SettingsPane.Grupo.allCases, id: \.self) { grupo in
                let paineis = SettingsPane.visiveis.filter { $0.grupo == grupo && $0.combina(busca) }
                if !paineis.isEmpty {
                  Section(grupo.rawValue) {
                    ForEach(paineis) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6).fill(pane.color.gradient))
                }
                .tag(pane)
                    }
                  }
                }
              }
            }
            .listStyle(.sidebar)
            .searchable(text: $busca, placement: .sidebar, prompt: "Buscar")
            // ponytail: frame direto — navigationSplitViewColumnWidth é ignorado
            // em NavigationSplitView hospedado num NSWindow manual (sem cena SwiftUI)
            .frame(width: 224)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(router.pane.title)
        }
        .frame(minWidth: 720, minHeight: 470)
    }

    private var selection: Binding<SettingsPane?> {
        Binding(get: { router.pane }, set: { if let p = $0 { router.pane = p } })
    }

    @ViewBuilder private var detail: some View {
        switch router.pane {
        case .geral: GeneralSettingsPane()
        case .notch: NotchSettingsPane()
        case .desenho: DesenhoSettingsPane()
        case .ditado: DictationSettingsPane()
        case .pomodoro: PomodoroSettingsPane()
        case .lembretes: RemindersView()
        case .descanso: DescansoTabView()
        case .webhooks: WebhookSettingsView(client: webhookClient)
        case .mensagens: IdentitySettingsView()
        case .plugins: PluginsSettingsPane(router: router)
        case .permissoes: PermissionsSettingsPane()
        case .monitores: MonitoresSettingsPane()
        }
    }
}

// MARK: - Linha de toggle com descrição

/// Toggle com título + descrição secundária, no padrão do Ajustes do Sistema.
struct SettingToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Geral

struct GeneralSettingsPane: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var updater = Updater.shared
    @ObservedObject private var host = PluginHost.shared

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
    }

    private var updateSubtitle: String {
        switch updater.state {
        case .available(let release): return "Versão \(release.version) disponível"
        case .installing: return "Atualizando…"
        case .failed(let message): return message
        case .none: return "Você está na versão mais recente"
        }
    }

    var body: some View {
        Form {
            Section {
                SettingToggle(
                    title: "Abrir no login",
                    subtitle: "Inicia o Knobler automaticamente quando você entra no Mac.",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.launchAtLogin = $0 }))
            }
            Section {
                SettingToggle(
                    title: "API local",
                    subtitle: "Servidor HTTP para automações mandarem cards pro notch.",
                    isOn: $settings.localAPI)
                if settings.localAPI {
                    LabeledContent("Endpoint") {
                        Text("POST http://localhost:4477/notify")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Corpo") {
                        Text("{\"title\", \"body\", \"app\"}")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            if host.estaInstalado(.textoDaTela) {
                Section("Texto da tela") {
                    LabeledContent("Atalho") {
                        ShortcutRecorder(name: TextoDaTelaServico.atalho)
                            .frame(width: 140)
                    }
                }
            }
            Section("Atualizações") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Versão \(appVersion)")
                        Text(updateSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    switch updater.state {
                    case .available:
                        if updater.canInstall {
                            Button("Atualizar") { updater.install() }
                                .buttonStyle(.borderedProminent)
                        } else if let url = updater.releaseURL {
                            Button("Ver release") { NSWorkspace.shared.open(url) }
                        }
                    case .installing:
                        ProgressView().controlSize(.small)
                    case .failed, .none:
                        Button("Verificar agora") { updater.check(force: true) }
                    }
                }
                SettingToggle(
                    title: "Verificar atualizações automaticamente",
                    subtitle: "Consulta o GitHub uma vez por dia e avisa no notch.",
                    isOn: $settings.checkForUpdates)
                SettingToggle(
                    title: "Avisos do desenvolvedor",
                    subtitle: "Novidades e recados sobre o Knobler, no máximo um por vez. Desligado, avisos críticos (segurança, falha que perde dado) continuam chegando.",
                    isOn: $settings.avisosDoDesenvolvedor)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}

// MARK: - Notch

struct NotchSettingsPane: View {
    @ObservedObject var settings = AppSettings.shared
    /// Desinstalar Agentes some com o toggle na hora.
    @ObservedObject private var host = PluginHost.shared

    /// A ordem salva menos as seções de peça desinstalada.
    private var visiveis: [NotchSection] {
        NotchSectionOrder.visiveis(base: settings.notchSectionOrder,
                                   desinstaladas: NotchSection.desinstaladas())
    }

    var body: some View {
        Form {
            Section("Abrir o card") {
                Picker("Abrir com", selection: $settings.notchAbrirComClique) {
                    Text("Passar o mouse").tag(false)
                    Text("Clicar").tag(true)
                }
                .pickerStyle(.segmented)
                LabeledContent("Atalho") {
                    ShortcutRecorder(name: .abrirNotch)
                }
                Text("Com o card aberto pelo atalho, ← → ou Tab trocam de seção e Esc fecha.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !settings.notchAbrirComClique {
                    LabeledContent("Atraso") {
                        HStack {
                            Slider(value: $settings.notchAtrasoHover, in: 0.1...1, step: 0.05)
                            Text(settings.notchAtrasoHover, format: .number.precision(.fractionLength(2)))
                                .monospacedDigit()
                            Text("s")
                        }
                    }
                }
            }
            Section("Seções do card") {
                Text("Arraste para mudar a ordem. O olho mostra a seção no card; o alfinete a mantém lá mesmo sem conteúdo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                cabecalhoColunas(["No card", "Fixa"])
                List {
                    ForEach(visiveis, id: \.self) { s in
                        let oculta = settings.notchSectionsOcultas.contains(s)
                        HStack {
                            linhaSecao(s, arrastavel: true)
                            Spacer()
                            Toggle(isOn: Binding(
                                get: { !oculta },
                                set: { mostrar in
                                    if mostrar { settings.notchSectionsOcultas.remove(s) }
                                    else { settings.notchSectionsOcultas.insert(s) }
                                })) {
                                    Label("Mostrar \(s.titulo) no card", systemImage: "eye")
                                        .labelStyle(.iconOnly)
                                }
                                .toggleStyle(.checkbox)
                                .frame(width: Self.larguraColuna)
                                .help("Mostrar no card")
                            // checkbox nativo, não `Button` com ícone: dentro de
                            // uma `List` com `.onMove` o botão disputa o gesto de
                            // arrastar com a reordenação da linha. O checkbox é o
                            // controle que o NSTableView já sabe hospedar.
                            Toggle(isOn: Binding(
                                get: { settings.notchSectionsFixadas.contains(s) },
                                set: { fixar in
                                    if fixar { settings.notchSectionsFixadas.insert(s) }
                                    else { settings.notchSectionsFixadas.remove(s) }
                                })) {
                                    Label("Fixar \(s.titulo) no card", systemImage: "pin.fill")
                                        .labelStyle(.iconOnly)
                                }
                                .toggleStyle(.checkbox)
                                .frame(width: Self.larguraColuna)
                                // fixar uma seção que o olho esconde não faz nada.
                                .disabled(oculta)
                                .help(oculta ? "Mostre a seção no card para poder fixá-la" : "Sempre no card, mesmo sem conteúdo")
                        }
                        .frame(height: Self.alturaLinha)
                    }
                    .onMove { origem, destino in
                        var nova = visiveis
                        nova.move(fromOffsets: origem, toOffset: destino)
                        // as escondidas voltam no fim: são invisíveis, e é lá
                        // que `sanear` as recolocaria de qualquer jeito.
                        settings.notchSectionOrder =
                            nova + settings.notchSectionOrder.filter { !nova.contains($0) }
                    }
                }
                .scrollDisabled(true)
                .frame(height: Self.alturaLista(visiveis.count))
                SettingToggle(
                    title: "Subir o que acabou de acontecer",
                    subtitle: "Seção com novidade passa na frente por alguns segundos. Desligado, o card segue sempre a ordem acima.",
                    isOn: $settings.promoverSecoesRecentes)
            }
            Section("Ações rápidas") {
                Text("Atalhos que aparecem na seção Ações rápidas. Valem também para seções escondidas do card. Arraste os marcados para mudar a ordem.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                cabecalhoColunas(["Atalho"])
                let marcados = settings.acoesRapidas
                let linhas = marcados + NotchSection.allCases.filter { $0 != .acoesRapidas && !marcados.contains($0) }
                List {
                    ForEach(linhas, id: \.self) { s in
                        let marcado = marcados.contains(s)
                        HStack {
                            linhaSecao(s, arrastavel: marcado)
                            Spacer()
                            Toggle(isOn: Binding(
                                get: { settings.acoesRapidas.contains(s) },
                                set: { marcar in
                                    if marcar { if !settings.acoesRapidas.contains(s) { settings.acoesRapidas.append(s) } }
                                    else { settings.acoesRapidas.removeAll { $0 == s } }
                                })) { Text("Mostrar \(s.titulo) nas Ações rápidas") }
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .frame(width: Self.larguraColuna)
                                .help("Mostrar nas Ações rápidas")
                        }
                        .frame(height: Self.alturaLinha)
                        // desmarcado não tem posição na grade: não arrasta.
                        .moveDisabled(!marcado)
                    }
                    .onMove { origem, destino in
                        // só os marcados se reordenam: soltar abaixo deles cola no fim.
                        guard origem.allSatisfy({ $0 < marcados.count }) else { return }
                        var nova = marcados
                        nova.move(fromOffsets: origem, toOffset: min(destino, marcados.count))
                        settings.acoesRapidas = nova
                    }
                }
                .scrollDisabled(true)
                .frame(height: Self.alturaLista(linhas.count))
            }
            if host.estaInstalado(.agentes) {
                Section("Agentes") {
                    SettingToggle(
                        title: "Mostrar o limite do Claude",
                        subtitle: "Lê o login do Claude Code num endereço interno da Anthropic. Os termos de uso de fevereiro de 2026 não permitem isso ao pé da letra, e o macOS pode pedir a senha do Keychain algumas vezes por dia. O limite do Codex e as sessões dos dois aparecem sem isso.",
                        isOn: $settings.agentesClaudeUso)
                }
            }
            Section("Visibilidade") {
                SettingToggle(
                    title: "Esconder em tela cheia",
                    subtitle: "O notch some na tela que estiver com um app em tela cheia.",
                    isOn: $settings.ocultarEmTelaCheia)
            }
            Section("Cards e avisos") {
                SettingToggle(
                    title: "Notificações no notch",
                    subtitle: "Banners do sistema viram cards no notch.",
                    isOn: $settings.notchNotifications)
                SettingToggle(
                    title: "Avisos de bateria",
                    subtitle: "Ao conectar/desconectar o carregador e com 20% ou menos.",
                    isOn: $settings.batteryAlerts)
                SettingToggle(
                    title: "AirPods no notch",
                    subtitle: "Card ao conectar, com a bateria dos fones e do estojo.",
                    isOn: $settings.airpodsNotch)
                SettingToggle(
                    title: "Indicador de microfone",
                    subtitle: "Mostra quando algum app está usando o microfone.",
                    isOn: $settings.micIndicator)
            }
            Section("HUDs") {
                SettingToggle(
                    title: "HUD de som",
                    subtitle: "Substitui o HUD nativo de volume por um no notch.",
                    isOn: $settings.volumeHUD)
                SettingToggle(
                    title: "HUD de brilho",
                    subtitle: "Substitui o HUD nativo de brilho por um no notch.",
                    isOn: $settings.brightnessHUD)
            }
            Section("Música") {
                SettingToggle(
                    title: "Visualizador com áudio real",
                    subtitle: "As barras dançam com o áudio que está tocando.",
                    isOn: $settings.liveAudioVisualizer)
            }
            Section("Calendário") {
                SettingToggle(
                    title: "Contagem do calendário",
                    subtitle: "Contagem regressiva pro próximo evento com horário.",
                    isOn: $settings.calendarCountdown)
                SettingToggle(
                    title: "Espelho antes de reuniões",
                    subtitle: "Abre a câmera 2 min antes de eventos com link de call.",
                    isOn: $settings.mirrorBeforeMeetings)
                    .disabled(!settings.calendarCountdown)
            }
            Section("Silenciar") {
                SettingToggle(
                    title: "Silenciar durante reuniões",
                    subtitle: "Em evento com link de call, notificação de app, "
                        + "API e webhook vai direto pro histórico, sem virar card. "
                        + "Alertas programados e Pomodoro continuam aparecendo.",
                    isOn: $settings.silenciarEmReuniao)
                    .disabled(!settings.calendarCountdown)
                SettingToggle(
                    title: "Silenciar durante chamadas",
                    subtitle: "Mesma coisa enquanto algum app estiver usando o "
                        + "microfone — pega a call que não está no calendário. "
                        + "Nada se perde: fica no histórico.",
                    isOn: $settings.silenciarComMicrofone)
            }
            Section("Prateleira") {
                SettingToggle(
                    title: "Arrastar pra fora tira da prateleira",
                    subtitle: "O item some da prateleira quando o destino aceita. "
                        + "O arquivo original não é tocado.",
                    isOn: $settings.shelfSaiAoArrastar)
            }
            Section("Capturas de tela") {
                SettingToggle(
                    title: "Capturas vão pro shelf",
                    subtitle: "Todo print entra no shelf do notch automaticamente.",
                    isOn: $settings.screenshotsToShelf)
                SettingToggle(
                    title: "Esconder o preview nativo do print",
                    subtitle: "Some com a miniatura flutuante — o shelf já mostra.",
                    isOn: $settings.hideScreenshotPreview)
                    .disabled(!settings.screenshotsToShelf)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    // As listas mostram todas as linhas de uma vez: uma `List` com altura fixa
    // rolaria por dentro da página, e as seções fora da janela pareceriam não existir.
    private static let alturaLinha: CGFloat = 28
    private static let larguraColuna: CGFloat = 52
    private static func alturaLista(_ linhas: Int) -> CGFloat {
        // ponytail: folga medida a olho pro inset do NSTableView; ajuste se sobrar/faltar linha.
        CGFloat(linhas) * (alturaLinha + 4) + 12
    }

    /// Alça de arrastar + ícone de largura fixa + nome, pra os nomes alinharem.
    private func linhaSecao(_ s: NotchSection, arrastavel: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .opacity(arrastavel ? 1 : 0)
                .accessibilityHidden(true)
            Image(systemName: s.simbolo)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(s.titulo)
        }
    }

    /// Títulos das colunas de checkbox, alinhados à direita com as linhas.
    private func cabecalhoColunas(_ titulos: [String]) -> some View {
        HStack(spacing: 8) {
            Spacer()
            ForEach(titulos, id: \.self) { t in
                Text(t)
                    .frame(width: Self.larguraColuna)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.trailing, 12)
        .accessibilityHidden(true)
    }
}

// MARK: - Desenho

/// Ajustes da anotação de tela. As ferramentas em si moram na seção Anotação do
/// card (`AnnotationDeckView`) — aqui ficam só os padrões e o comportamento.
struct DesenhoSettingsPane: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var annotation = AnnotationController.shared

    var body: some View {
        Form {
            Section("Ativação") {
                Picker("Ativação do Control esquerdo", selection: $settings.annotationActivationMode) {
                    Text("Pressionar e Segurar").tag(AnnotationActivationMode.pressAndHold)
                    Text("Alternar").tag(AnnotationActivationMode.toggle)
                }
                Text("Desenha sobre a tela inteira como o DemoPro. O atalho é o Control esquerdo, sem Command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Padrões do traço") {
                Picker("Ferramenta", selection: Binding(
                    get: { settings.annotationDefaultTool },
                    set: { annotation.select(tool: $0) })) {
                        ForEach(AnnotationTool.allCases, id: \.self) {
                            Label($0.title, systemImage: $0.symbol).tag($0)
                        }
                    }
                // qualificado: o projeto tem um `ColorPicker` próprio (o painel
                // nativo que o deck do card abre), e ele sombreia o do SwiftUI.
                SwiftUI.ColorPicker("Cor", selection: Binding(
                    get: { Color(cor: settings.annotationDefaultColor) },
                    set: { nova in
                        let cor = AnnotationColor(nova)
                        annotation.setColor(cor)
                    }), supportsOpacity: false)
                HStack {
                    Text("Espessura")
                    Slider(value: Binding(
                        get: { settings.annotationLineWidth },
                        set: { annotation.setLineWidth($0) }),
                           in: 1...24, step: 1)
                    Text("\(Int(settings.annotationLineWidth)) pt")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
            }
            Section("Fundo") {
                Picker("Quadro", selection: Binding(
                    get: { annotation.background },
                    set: { annotation.setBackground($0) })) {
                        ForEach(AnnotationBackground.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                Text("O quadro cobre a tela atrás do traço. Vale pra todos os monitores.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Desvanecer") {
                SettingToggle(
                    title: "Desvanecer automaticamente",
                    subtitle: "Apaga cada anotação depois do atraso escolhido.",
                    isOn: $settings.annotationAutoFade)
                if settings.annotationAutoFade {
                    HStack {
                        Text("Atraso")
                        Slider(value: $settings.annotationFadeSeconds, in: 0.5...30, step: 0.5)
                        Text("\(settings.annotationFadeSeconds, specifier: "%.1f") s")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
            Section("Atalhos enquanto desenha") {
                ForEach(Self.atalhos, id: \.tecla) { atalho in
                    HStack {
                        Text(atalho.tecla).monospaced()
                            .frame(width: 60, alignment: .leading)
                        Text(atalho.acao).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    /// As teclas das ferramentas saem do próprio enum — só as fixas são escritas
    /// aqui, e elas vivem no `installKeyMonitor` do controller.
    private static let atalhos: [(tecla: String, acao: String)] =
        AnnotationTool.allCases.map { (String($0.key), $0.title) } + [
            ("U", "Desfazer"), ("R", "Refazer"), ("X", "Apagar tudo"),
            ("W", "Quadro branco"), ("K", "Quadro negro"),
            ("Esc", "Para de desenhar (o traço fica)"),
            ("Delete", "Apagar tudo"),
            ("⌘Z / ⇧⌘Z", "Desfazer / refazer"),
        ]
}

private extension AnnotationColor {
    init(_ color: Color) {
        let rgb = NSColor(color).usingColorSpace(.deviceRGB) ?? .yellow
        self.init(red: Double(rgb.redComponent),
                  green: Double(rgb.greenComponent),
                  blue: Double(rgb.blueComponent),
                  alpha: Double(rgb.alphaComponent))
    }
}

// MARK: - Ditado

struct DictationSettingsPane: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var deepgramKey = DeepgramKeyStore.load()

    var body: some View {
        Form {
            Section {
                SettingToggle(
                    title: "Ditado",
                    subtitle: "Segure a ⌥ direita para gravar; ao soltar, o texto é "
                        + "transcrito e colado onde o cursor estiver.",
                    isOn: $settings.dictation)
            }
            Section {
                Picker("Motor", selection: $settings.dictationCloud) {
                    Text("Local (offline)").tag(false)
                    Text("Deepgram (nuvem)").tag(true)
                }
                .pickerStyle(.radioGroup)
                if settings.dictationCloud {
                    SecureField("API key do Deepgram", text: $deepgramKey)
                        .onChange(of: deepgramKey) { _, new in
                            DeepgramKeyStore.save(new)
                        }
                }
            } header: {
                Text("Transcrição")
            } footer: {
                if settings.dictationCloud {
                    Text("A chave fica guardada no Keychain do macOS.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.dictation)
            Section("Formatação com IA") {
                SettingToggle(
                    title: "Formatar transcrição",
                    subtitle: "Passa o texto por um modelo local (Ollama/LM Studio) pra "
                        + "limpar vícios de fala e pontuação. Adiciona ~1 s.",
                    isOn: $settings.formatTranscript)
                if settings.formatTranscript {
                    TextField("Endpoint", text: $settings.formatEndpoint)
                    TextField("Modelo", text: $settings.formatModel)
                }
            }
            .disabled(!settings.dictation)
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}

// MARK: - Pomodoro

struct PomodoroSettingsPane: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Durações") {
                Stepper("Foco: \(settings.pomodoroFocus) min",
                        value: $settings.pomodoroFocus, in: 1...120)
                Stepper("Pausa curta: \(settings.pomodoroShortBreak) min",
                        value: $settings.pomodoroShortBreak, in: 1...60)
                Stepper("Pausa longa: \(settings.pomodoroLongBreak) min",
                        value: $settings.pomodoroLongBreak, in: 1...60)
                Stepper("Focos até a pausa longa: \(settings.pomodoroCyclesLong)",
                        value: $settings.pomodoroCyclesLong, in: 1...12)
            }
            Section("Ao trocar de fase") {
                SettingToggle(
                    title: "Som",
                    subtitle: "Um toque curto no fim de cada foco ou pausa.",
                    isOn: $settings.pomodoroSound)
                // sem a peça Descanso não há o que travar a tela: a opção some,
                // sem alerta e sem item acinzentado (002).
                if PluginHost.shared.estaInstalado(.descanso) {
                    SettingToggle(
                        title: "Travar a tela nas pausas",
                        subtitle: "Bloqueio forçado (como o Descanso) enquanto durar a pausa.",
                        isOn: $settings.pomodoroLockScreen)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}

// MARK: - Permissões

struct PermissionsSettingsPane: View {
    @EnvironmentObject private var lanMessaging: LANMessaging

    /// Lido de uma vez e revalidado quando o app volta ao foco — o usuário sai
    /// pro Ajustes do Sistema, mexe lá e volta esperando ver o novo estado.
    @State private var statuses: [Permission: PermissionStatus] = [:]

    /// Recalculado junto com os status: mudar de lugar exige relançar o app, mas
    /// tirar a quarentena não — e o usuário volta ao painel esperando ver limpo.
    @State private var installIssue: Permission.InstallIssue?

    var body: some View {
        Form {
            if let issue = installIssue {
                Section {
                    InstallIssueRow(issue: issue)
                }
            }
            Section {
                ForEach(Permission.allCases) { permission in
                    PermissionRow(
                        permission: permission,
                        status: statuses[permission] ?? .naoVerificada,
                        onChange: reload,
                        ligarBonjour: { lanMessaging.start() })
                }
            } footer: {
                Text("A acessibilidade é pedida na abertura do Knobler — sem ela "
                     + "o app não lê teclado nem notificações. As outras são "
                     + "pedidas no primeiro uso do recurso, e recusar só desliga "
                     + "aquele recurso.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Text("O Ajustes do Sistema só lista um app depois que ele pede a "
                     + "permissão. Se o Knobler não estiver na lista, abra o painel, "
                     + "clique em + e arraste o app a partir do Finder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack {
                    Button("Revelar o Knobler no Finder") {
                        Permission.revealAppInFinder()
                    }
                    Button("Copiar diagnóstico") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Permission.diagnostico(), forType: .string)
                    }
                }
            } header: {
                Text("Não achou o Knobler na lista?")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
    }

    private func reload() {
        statuses = Dictionary(uniqueKeysWithValues:
            Permission.allCases.map { ($0, $0.status) })
        installIssue = Permission.installIssue
    }
}

/// A instalação está num estado em que conceder permissão não adianta — isso
/// vem antes de qualquer linha de permissão, senão o usuário fica tentando
/// conceder algo que o TCC vai descartar.
private struct InstallIssueRow: View {
    let issue: Permission.InstallIssue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13))
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Instalação fora do lugar").bold()
                Text(issue.mensagem)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Text(issue.comoResolver)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Revelar") { Permission.revealAppInFinder() }
        }
        .padding(.vertical, 2)
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let status: PermissionStatus
    /// Rechecagem imediata após o balão — sem isso o badge só atualiza quando o
    /// app volta ao foco, e ele nunca perdeu o foco.
    let onChange: () -> Void
    /// Liga o Bonjour: é a única sonda da Rede local que não mora no
    /// `Permission` (precisa de alguém anunciando pra ter o que achar).
    let ligarBonjour: () -> Void

    @State private var verificando = false

    private func verificar() {
        verificando = true
        if permission == .redeLocal { ligarBonjour() }
        permission.probe {
            // O Bonjour leva alguns segundos pra achar o próprio anúncio; a
            // sonda de arquivos já respondeu e a espera não custa nada.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                verificando = false
                onChange()
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: badge.symbol)
                .foregroundStyle(badge.tint)
                .font(.system(size: 13))
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(permission.title)
                    Text(badge.label)
                        .font(.caption)
                        .foregroundStyle(badge.tint)
                }
                Text(permission.why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            // Balão do sistema quando ele ainda pode aparecer; o Ajustes do
            // Sistema é o fallback (permissão já negada, ou sem API de pedido).
            if permission.canRequest {
                Button("Permitir") { permission.request(completion: onChange) }
                    .buttonStyle(.borderedProminent)
            }
            // Sem API de consulta: quem concedeu no Ajustes do Sistema não vê
            // mudança nenhuma aqui até a feature rodar. O botão faz ela rodar.
            if permission.canProbe, status == .naoVerificada {
                Button(verificando ? "Verificando…" : "Verificar") { verificar() }
                    .disabled(verificando)
            }
            // O "Abrir" fica mesmo com o "Permitir" ao lado: a Acessibilidade não
            // distingue negada de nunca pedida, então o balão pode ser um no-op
            // silencioso e o Ajustes do Sistema precisa continuar a um clique.
            Button("Abrir") { NSWorkspace.shared.open(permission.settingsURL) }
        }
        .padding(.vertical, 2)
    }

    private var badge: (symbol: String, label: String, tint: Color) {
        switch status {
        case .concedida: return ("checkmark.circle.fill", "Concedida", .green)
        case .negada: return ("xmark.circle.fill", "Negada", .red)
        case .naoPedida: return ("circle.dashed", "Não solicitada", .secondary)
        // O macOS não expõe status pra Rede local, Arquivos e Áudio do sistema:
        // "concedida" só depois que a feature roda uma vez. Dizer "ainda não
        // usada" fazia parecer defeito pra quem tinha acabado de ligar o
        // interruptor no Ajustes do Sistema.
        case .naoVerificada: return ("questionmark.circle", "Sem status até usar", .secondary)
        }
    }
}
