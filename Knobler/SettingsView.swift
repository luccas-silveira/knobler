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

// MARK: - Painéis

enum SettingsPane: String, CaseIterable, Identifiable {
    case geral, notch, ditado, pomodoro, lembretes, descanso, webhooks, mensagens
    var id: String { rawValue }

    var title: String {
        switch self {
        case .geral: return "Geral"
        case .notch: return "Notch"
        case .ditado: return "Ditado"
        case .pomodoro: return "Pomodoro"
        case .lembretes: return "Lembretes"
        case .descanso: return "Descanso"
        case .webhooks: return "Notificações externas"
        case .mensagens: return "Mensagens"
        }
    }

    var symbol: String {
        switch self {
        case .geral: return "gearshape.fill"
        case .notch: return "macbook.gen2"
        case .ditado: return "mic.fill"
        case .pomodoro: return "timer"
        case .lembretes: return "bell.badge.fill"
        case .descanso: return "moon.zzz.fill"
        case .webhooks: return "bell.and.waves.left.and.right.fill"
        case .mensagens: return "bubble.left.and.bubble.right.fill"
        }
    }

    var color: Color {
        switch self {
        case .geral: return .gray
        case .notch: return .black
        case .ditado: return .blue
        case .pomodoro: return .red
        case .lembretes: return .orange
        case .descanso: return .indigo
        case .webhooks: return .purple
        case .mensagens: return .green
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

    var body: some View {
        // .constant(.all): sem isso o divisor colapsa a sidebar por arrasto e,
        // sem toolbar/menu (LSUIElement), não existe caminho de volta
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsPane.allCases, selection: selection) { pane in
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
            .listStyle(.sidebar)
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
        case .ditado: DictationSettingsPane()
        case .pomodoro: PomodoroSettingsPane()
        case .lembretes: RemindersView()
        case .descanso: DescansoTabView()
        case .webhooks: WebhookSettingsView(client: webhookClient)
        case .mensagens: IdentitySettingsView()
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
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
            Section {
                LabeledContent("Versão", value: appVersion)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}

// MARK: - Notch

struct NotchSettingsPane: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
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
                SettingToggle(
                    title: "Travar a tela nas pausas",
                    subtitle: "Bloqueio forçado (como o Descanso) enquanto durar a pausa.",
                    isOn: $settings.pomodoroLockScreen)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}
