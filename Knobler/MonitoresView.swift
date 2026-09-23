import SwiftUI

extension Monitores: PluginServico {
    func parar() { stop() }
}

final class MonitoresSettingsSelection: ObservableObject {
    static let shared = MonitoresSettingsSelection()
    @Published var displayID: UInt32?
}

struct MonitoresView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var service: Monitores = .shared

    private var selected: MonitorState? {
        service.displays.first { $0.id == vm.monitoresSelecionado }
            ?? service.displays.first { $0.id == vm.displayID }
            ?? service.displays.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let display = selected {
                HStack {
                    Picker("Monitor", selection: Binding(get: { display.id }, set: { vm.monitoresSelecionado = $0 })) {
                        ForEach(service.displays) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Monitor selecionado")
                    Button { vm.onMonitoresSettings?(display.id) } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ajustes de \(display.name)")
                    .help("Ajustes de \(display.name)")
                }
                control("Brilho", value: display.brightness, command: .brightness, display: display)
                    .disabled(display.preferences.mode == .hardware && !display.hardwareBrightness)
                if display.preferences.mode == .hardware && !display.hardwareBrightness {
                    Text("Brilho por hardware indisponível. Use o modo automático ou software nos ajustes.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if display.software {
                    Label("Escurecimento por software", systemImage: "circle.lefthalf.filled")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if let volume = display.volume {
                    HStack {
                        control("Volume", value: volume, command: .volume, display: display)
                        Button { service.toggleMute(displayID: display.id) } label: {
                            Image(systemName: display.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        }
                        .buttonStyle(.plain)
                        .disabled(display.busy || !display.preferences.enableMute || !display.muteSupported)
                        .help(display.muteSupported ? "Alternar mudo" : "Este monitor não oferece controle de mudo.")
                        .accessibilityLabel(display.muted ? "Reativar som" : "Silenciar monitor")
                    }
                } else {
                    Text("Volume indisponível neste monitor.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                DisclosureGroup("Contraste", isExpanded: $vm.monitoresContraste) {
                    if let contrast = display.contrast {
                        control("Contraste", value: contrast, command: .contrast, display: display)
                    } else {
                        Text("Este monitor não oferece controle de contraste.").font(.caption)
                    }
                }
                if let error = display.error {
                    HStack {
                        Text(error).font(.system(size: 10)).lineLimit(2)
                        Spacer(minLength: 0)
                        Button("Tentar novamente") { service.retry(displayID: display.id) }
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.orange)
                }
            } else {
                Label("Nenhum monitor disponível", systemImage: "display")
                Button("Atualizar monitores") { service.refresh() }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .onAppear { vm.onAgendaKeyboard?() }
        .onDisappear { vm.monitoresArrastando = false }
    }

    private func control(_ title: String, value: Double, command: MonitorCommand, display: MonitorState) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { value }, set: { service.set(command, value: $0, displayID: display.id) }),
                   in: 0...1, onEditingChanged: { editing in
                vm.monitoresArrastando = editing
                if !editing && !vm.isHovering { vm.setHover(false) }
            })
            .disabled(display.busy)
            .accessibilityLabel("\(title) de \(display.name)")
            .accessibilityValue("\(Int((value * 100).rounded())) por cento")
        }
    }
}

struct MonitoresSettingsPane: View {
    @ObservedObject var service: Monitores = .shared
    @ObservedObject private var selection = MonitoresSettingsSelection.shared
    private var selected: MonitorState? {
        service.displays.first { $0.id == selection.displayID } ?? service.displays.first
    }

    var body: some View {
        Form {
            if let error = service.restorationError {
                Section("Restaurar brilho") {
                    Text(error).foregroundStyle(.orange)
                    Button("Tentar novamente") { service.retryRestoration() }
                }
            }
            if let display = selected {
                Picker("Monitor", selection: Binding(get: { display.id }, set: { selection.displayID = $0 })) {
                    ForEach(service.displays) { Text($0.name).tag($0.id) }
                }
                preferences(display)
            } else {
                Text("Conecte um monitor para configurar seus controles.")
                Button("Atualizar monitores") { service.refresh() }
            }
        }
        .formStyle(.grouped)
    }

    private func binding<T>(_ key: WritableKeyPath<MonitorPreferences, T>, _ display: MonitorState) -> Binding<T> {
        Binding(get: { display.preferences[keyPath: key] }, set: {
            var prefs = display.preferences
            prefs[keyPath: key] = $0
            service.updatePreferences(prefs, displayID: display.id)
        })
    }

    @ViewBuilder private func preferences(_ display: MonitorState) -> some View {
        Section("Controle") {
            TextField("Nome", text: binding(\.name, display))
            Toggle("Usar teclas de controle", isOn: binding(\.keyboardEnabled, display))
            Toggle("Mostrar HUD", isOn: binding(\.showHUD, display))
            Picker("Modo", selection: binding(\.mode, display)) {
                Text("Automático").tag(MonitorControlMode.automatic)
                Text("Hardware (DDC)").tag(MonitorControlMode.hardware)
                Text("Software").tag(MonitorControlMode.software)
            }
            Picker("Escurecimento por software", selection: binding(\.softwareMethod, display)) {
                Text("Gamma").tag(MonitorSoftwareMethod.gamma)
                Text("Sobreposição").tag(MonitorSoftwareMethod.overlay)
            }
            Toggle("Sincronizar diferenças de brilho", isOn: binding(\.synchronize, display))
            Text("Preserva os níveis relativos entre os monitores participantes.").font(.caption).foregroundStyle(.secondary)
            Toggle("Restaurar últimos valores ao conectar", isOn: binding(\.restoreLastValues, display))
        }
        Section("Som") {
            Picker("Saída de áudio associada", selection: binding(\.audioDeviceUID, display)) {
                Text("Sem associação").tag("")
                ForEach(Monitores.audioOutputs()) { Text($0.name).tag($0.id) }
            }
            Text("As teclas de volume seguem a saída ativa. O slider controla este monitor.").font(.caption).foregroundStyle(.secondary)
            Toggle("Monitor oferece comando de mudo", isOn: binding(\.enableMute, display))
        }
        Section("Atalhos") {
            ForEach(Monitores.shortcutNames, id: \.name) { shortcut in
                HStack {
                    Text(shortcut.title)
                    Spacer()
                    ShortcutRecorder(name: shortcut.name)
                        .frame(width: 150)
                        .accessibilityLabel(shortcut.title)
                }
            }
            Text("Sem combinação por padrão. Apague a combinação para remover o atalho.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Avançado") {
            Toggle("Permitir preto total", isOn: binding(\.allowZeroBrightness, display))
            Stepper("Tentativas: \(display.preferences.attempts)", value: binding(\.attempts, display), in: 1...10)
            Stepper("Atraso: \(display.preferences.delayMilliseconds) ms", value: binding(\.delayMilliseconds, display), in: 1...1000, step: 10)
            calibration("Brilho", key: \.brightnessCalibration, display: display)
            calibration("Contraste", key: \.contrastCalibration, display: display)
            calibration("Volume", key: \.volumeCalibration, display: display)
        }
    }

    private func calibration(_ title: String, key: WritableKeyPath<MonitorPreferences, MonitorCalibration>, display: MonitorState) -> some View {
        let base = binding(key, display)
        return DisclosureGroup("Calibração de \(title.lowercased())") {
            TextField("Mínimo", value: base.minimum, format: .number)
            Toggle("Detectar máximo do monitor", isOn: Binding(get: { base.wrappedValue.usesHardwareMaximum }, set: {
                var value = base.wrappedValue
                value.automaticMaximum = $0
                base.wrappedValue = value
            }))
            TextField("Máximo", value: Binding(get: { base.wrappedValue.maximum }, set: {
                var value = base.wrappedValue
                value.maximum = $0
                value.automaticMaximum = false
                base.wrappedValue = value
            }), format: .number)
            .disabled(base.wrappedValue.usesHardwareMaximum)
            Stepper("Curva: \(base.wrappedValue.curve)", value: base.curve, in: 0...10)
            Toggle("Inverter", isOn: base.inverted)
            TextField("Remapeamento DDC (hexadecimal)", text: base.remap)
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        KeyboardShortcuts.RecorderCocoa(for: name)
    }
    func updateNSView(_ view: KeyboardShortcuts.RecorderCocoa, context: Context) {
        view.shortcutName = name
    }
}
