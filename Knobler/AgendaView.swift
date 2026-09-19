// Agenda diária dentro do card: estado e consultas pertencem ao ViewModel.
import SwiftUI

struct AgendaView: View {
    @ObservedObject var vm: NotchViewModel

    private var hoje: Bool {
        Calendar.current.isDate(vm.agenda.dia, inSameDayAs: vm.agenda.atualizadoEm)
    }

    var body: some View {
        Group {
            if let rascunho = vm.agendaRascunhoBinding {
                AgendaEditorView(vm: vm, rascunho: rascunho)
            } else {
                lista
            }
        }
        .frame(height: NotchMetrics.alturaAgenda(editando: vm.agendaRascunho != nil,
            disponivel: vm.availableSize.height, topo: vm.hasRealNotch ? vm.notchSize.height : 4))
    }

    private var lista: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agenda")
                        .font(.system(size: 15, weight: .semibold))
                    Text(vm.agenda.dia.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)
                        .locale(Locale(identifier: "pt_BR"))))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 8)
                Button { vm.novoEventoAgenda() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Novo evento")
                .help("Novo evento")
                Button("Hoje") { vm.agendaHoje() }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(.white.opacity(hoje ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Voltar para hoje")
                diaButton("chevron.left", label: "Dia anterior", dias: -1)
                diaButton("chevron.right", label: "Dia seguinte", dias: 1)
            }
            .buttonStyle(.plain)

            if let confirmacao = vm.agendaConfirmacao {
                Label(confirmacao, systemImage: "checkmark.circle")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !vm.agenda.autorizado {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 22))
                    Text("Permita o acesso ao calendário")
                        .font(.system(size: 13, weight: .medium))
                    Text("Veja seus compromissos aqui no notch.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                    Button("Abrir permissões") { vm.onAgendaPermissions?() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.agenda.eventos.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 22))
                    Text("Nenhum evento neste dia")
                        .font(.system(size: 13))
                }
                .foregroundStyle(.white.opacity(0.65))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(vm.agenda.eventos) { evento in
                            linha(evento)
                        }
                    }
                }
                .id(vm.agenda.dia)
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxHeight: .infinity)
    }

    private func diaButton(_ simbolo: String, label: String, dias: Int) -> some View {
        Button { vm.navegarAgenda(dias) } label: {
            Image(systemName: simbolo)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .help(label)
    }

    private func linha(_ evento: CalendarEvento) -> some View {
        let emAndamento = evento.emAndamento(em: vm.agenda.atualizadoEm)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if evento.diaInteiro {
                    Text("Dia inteiro")
                } else {
                    Text(evento.inicio, style: .time)
                    Text(evento.fim, style: .time)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .frame(width: 68, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(evento.titulo)
                    .font(.system(size: 13, weight: emAndamento ? .semibold : .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(evento.calendario)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                if emAndamento {
                    Text("Em andamento")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(.white.opacity(emAndamento ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .help(evento.titulo)
    }
}
