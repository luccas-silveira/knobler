import SwiftUI

/// Campos nativos; fechar ou desmontar esta view não descarta o rascunho.
struct AgendaEditorView: View {
    @ObservedObject var vm: NotchViewModel
    @Binding var rascunho: CalendarRascunho
    @FocusState private var tituloFocado: Bool

    private var calendarioDisponivel: Bool {
        vm.agendaDestinos.contains { $0.id == rascunho.calendarioID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Novo evento")
                .font(.system(size: 15, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    campo("Título") {
                        TextField("Nome do evento", text: $rascunho.titulo)
                            .focused($tituloFocado)
                            .accessibilityIdentifier("agenda-titulo")
                    }
                    Toggle("Dia inteiro", isOn: $rascunho.diaInteiro)
                        .toggleStyle(.checkbox)
                    DatePicker("Início", selection: $rascunho.inicio,
                               displayedComponents: rascunho.diaInteiro ? [.date] : [.date, .hourAndMinute])
                        .datePickerStyle(.field)
                    DatePicker("Fim", selection: $rascunho.fim,
                               displayedComponents: rascunho.diaInteiro ? [.date] : [.date, .hourAndMinute])
                        .datePickerStyle(.field)
                    Picker("Calendário", selection: $rascunho.calendarioID) {
                        if !calendarioDisponivel {
                            Text("Escolha um calendário").tag(rascunho.calendarioID)
                        }
                        ForEach(vm.agendaDestinos) { destino in
                            Text(destino.rotulo).tag(destino.id)
                        }
                    }
                    .pickerStyle(.menu)
                    campo("Local") { TextField("Opcional", text: $rascunho.local) }
                    campo("Link") { TextField("https://… (opcional)", text: $rascunho.link) }
                    campo("Observações") {
                        TextField("Opcional", text: $rascunho.observacoes, axis: .vertical)
                            .lineLimit(3...5)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(.trailing, 4)
                .padding(.bottom, 4)
                .disabled(vm.agendaSalvando)
            }
            if !vm.agenda.autorizado {
                Text("Permita o acesso ao calendário para criar eventos.")
                    .foregroundStyle(.white.opacity(0.7))
                Button("Abrir permissões") { vm.onAgendaPermissions?() }
            } else if vm.agendaDestinos.isEmpty {
                Text("Nenhum calendário permite criar eventos. Adicione uma conta ou um calendário editável no app Calendário.")
                    .foregroundStyle(.white.opacity(0.7))
            } else if !calendarioDisponivel {
                Text("Selecione um calendário disponível antes de salvar.")
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let erro = vm.agendaErro {
                Label(erro, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("agenda-erro")
            }
            HStack {
                Button("Cancelar") { vm.cancelarEventoAgenda() }
                    .disabled(vm.agendaSalvando)
                Spacer()
                Button(vm.agendaSalvando ? "Salvando…" : "Salvar") { vm.salvarEventoAgenda() }
                    .fontWeight(.semibold)
                    .disabled(vm.agendaSalvando || !vm.agenda.autorizado || !calendarioDisponivel)
                    .accessibilityIdentifier("agenda-salvar")
            }
            .buttonStyle(.bordered)
        }
        .environment(\.colorScheme, .dark)
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.9))
        .onExitCommand { vm.setExpandedDirect(false) }
        .onAppear {
            DispatchQueue.main.async {
                guard vm.editandoAgenda else { return }
                vm.onAgendaKeyboard?()
                tituloFocado = true
            }
        }
    }

    private func campo<Content: View>(_ titulo: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).foregroundStyle(.white.opacity(0.7))
            content().accessibilityLabel(titulo)
        }
    }
}
