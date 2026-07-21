//
//  DescansoView.swift
//  Knobler
//
//  UI do Descanso (bloqueio forçado): a view do contador do overlay (SwiftUI puro,
//  entra no harness de snapshot) e a aba "Descanso" nos Ajustes (lista + formulário).
//  A lógica de janela/quiosque vive no DescansoController (AppKit), à parte.
//

import SwiftUI

// MARK: - Overlay (contador)

/// Estado compartilhado entre o controller e as views do overlay (uma por tela).
final class BreakOverlayModel: ObservableObject {
    @Published var endDate = Date()
    @Published var label = ""
    @Published var holdProgress = 0.0   // 0..1 enquanto o usuário segura Esc
}

/// A tela escurecida + contador regressivo. Não decrementa um contador: recomputa o
/// restante do `endDate` a cada tick — sleep-proof (dormiu/acordou → lê o alvo real).
struct BreakOverlayView: View {
    @ObservedObject var model: BreakOverlayModel
    @State private var now = Date()
    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var remaining: TimeInterval { max(0, model.endDate.timeIntervalSince(now)) }

    private var clock: String {
        let s = Int(remaining.rounded())
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }

    private var subtitle: String { model.label.isEmpty ? "descanse um pouco" : model.label }

    var body: some View {
        ZStack {
            // ponytail: 0.9 é o único knob de "quão escuro"; a tela aparece fantasma atrás
            Color.black.opacity(0.9).ignoresSafeArea()

            VStack(spacing: 12) {
                Text(clock)
                    .font(.system(size: 76, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
            }

            // rodapé fixo: a dica do escape + barra de progresso do hold
            VStack {
                Spacer()
                VStack(spacing: 8) {
                    if model.holdProgress > 0 {
                        // barra desenhada à mão (ProgressView não renderiza no ImageRenderer)
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule().fill(.white.opacity(0.85))
                                .frame(width: 160 * min(1, model.holdProgress))
                        }
                        .frame(width: 160, height: 4)
                    }
                    Text("segurar Esc para sair")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.bottom, 44)
            }
        }
        .onReceive(tick) { now = $0 }
    }
}

// MARK: - Aba "Descanso" (Ajustes)

struct DescansoTabView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var editing: ScreenBreak?
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            if settings.screenBreaks.isEmpty {
                ContentUnavailableView("Sem bloqueios", systemImage: "moon.zzz",
                    description: Text("Toque em + para agendar uma pausa que trava a tela."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(settings.screenBreaks) { b in row(b) }
                        .onDelete { settings.screenBreaks.remove(atOffsets: $0) }
                }
            }
            Divider()
            HStack {
                Button { creating = true } label: {
                    Label("Novo bloqueio", systemImage: "plus")
                }
                .buttonStyle(.borderless).padding(8)
                Spacer()
            }
        }
        .sheet(isPresented: $creating) {
            BreakFormView(existing: nil) { settings.screenBreaks.append($0) }
        }
        .sheet(item: $editing) { b in
            BreakFormView(existing: b) { edited in
                if let i = settings.screenBreaks.firstIndex(where: { $0.id == edited.id }) {
                    settings.screenBreaks[i] = edited
                }
            }
        }
    }

    private func row(_ b: ScreenBreak) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(b.label.isEmpty ? "(sem nome)" : b.label)
                Text(b.scheduleSummary()).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { b.enabled },
                set: { on in
                    if let i = settings.screenBreaks.firstIndex(where: { $0.id == b.id }) {
                        settings.screenBreaks[i].enabled = on
                    }
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = b }
        .help("Clique para editar")
        .contextMenu {
            Button("Editar…") { editing = b }
            Divider()   // separa o destrutivo — misclick não apaga sem querer
            Button("Apagar", role: .destructive) {
                settings.screenBreaks.removeAll { $0.id == b.id }
            }
        }
    }
}

private struct BreakFormView: View {
    enum Freq: String, CaseIterable, Identifiable {
        case relative = "Daqui a", oneShot = "Uma vez", daily = "Diária"
        case weekly = "Semanal", monthly = "Mensal", yearly = "Anual"
        case nth = "N-ésimo dia", interval = "Intervalo"
        var id: String { rawValue }
    }

    let existing: ScreenBreak?
    let onSave: (ScreenBreak) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var freq: Freq = .relative
    @State private var time = BreakFormView.defaultTime()   // hora (modos de relógio)
    @State private var date = Date()                         // oneShot: data+hora
    @State private var weekdays: Set<Int> = [2]             // 1=Dom..7=Sáb
    @State private var dayOfMonth = 1
    @State private var month = 1
    @State private var ordinal = 1                          // 1..4, -1 = última
    @State private var nthWeekday = 2
    @State private var intervalValue = 2
    @State private var intervalHours = true
    @State private var relativeValue = 50                   // "Daqui a X"
    @State private var relativeHours = false
    @State private var durationMinutes = 5

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Nome (opcional)", text: $label)
                }
                Section("Quando") {
                    Picker("Frequência", selection: $freq) {
                        ForEach(Freq.allCases) { Text($0.rawValue).tag($0) }
                    }
                    freqFields
                }
                Section("Bloqueio") {
                    Stepper("Bloquear por: \(durationMinutes) min",
                            value: $durationMinutes, in: 1...120)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 380, height: 460)
        .onAppear { loadExisting() }
    }

    @ViewBuilder private var freqFields: some View {
        switch freq {
        case .relative:
            Stepper("Daqui a \(relativeValue) \(relativeHours ? "h" : "min")",
                    value: $relativeValue, in: 1...99)
            Toggle("Em horas", isOn: $relativeHours)
        case .oneShot:
            DatePicker("Data e hora", selection: $date)
        case .daily:
            DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
        case .weekly:
            DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
            weekdayPicker
        case .monthly:
            DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
            Stepper("Dia do mês: \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
        case .yearly:
            DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
            Stepper("Dia: \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
            Picker("Mês", selection: $month) {
                ForEach(1...12, id: \.self) { m in
                    Text(ReminderClock.monthNames[m - 1]).tag(m)
                }
            }
        case .nth:
            DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
            Picker("Posição", selection: $ordinal) {
                Text("1ª").tag(1); Text("2ª").tag(2); Text("3ª").tag(3)
                Text("4ª").tag(4); Text("Última").tag(-1)
            }
            Picker("Dia da semana", selection: $nthWeekday) {
                ForEach(1...7, id: \.self) { w in
                    Text(ReminderClock.weekdayNamesFull[w - 1]).tag(w)
                }
            }
        case .interval:
            Stepper("A cada \(intervalValue) \(intervalHours ? "h" : "min")",
                    value: $intervalValue, in: 1...99)
            Toggle("Em horas", isOn: $intervalHours)
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { w in
                let on = weekdays.contains(w)
                Text(ReminderClock.weekdayNames[w - 1])
                    .font(.caption)
                    .frame(width: 34, height: 26)
                    .background(on ? Color.accentColor : Color.gray.opacity(0.2))
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture {
                        if on { weekdays.remove(w) } else { weekdays.insert(w) }
                    }
            }
        }
    }

    // MARK: - Fields <-> Schedule

    private func hourMinute() -> (Int, Int) {
        let c = ReminderClock.calendar.dateComponents([.hour, .minute], from: time)
        return (c.hour ?? 9, c.minute ?? 0)
    }

    private func makeSchedule() -> Schedule {
        let (h, m) = hourMinute()
        switch freq {
        case .relative:
            let secs = relativeValue * (relativeHours ? 3600 : 60)
            return .oneShot(Date().addingTimeInterval(TimeInterval(secs)))
        case .oneShot:
            return .oneShot(date)
        case .daily:
            return .calendar([DateComponents(hour: h, minute: m)])
        case .weekly:
            let days = weekdays.isEmpty ? [2] : weekdays.sorted()
            return .calendar(days.map { DateComponents(hour: h, minute: m, weekday: $0) })
        case .monthly:
            return .calendar([DateComponents(day: dayOfMonth, hour: h, minute: m)])
        case .yearly:
            return .calendar([DateComponents(month: month, day: dayOfMonth, hour: h, minute: m)])
        case .nth:
            return .calendar([DateComponents(hour: h, minute: m,
                                             weekday: nthWeekday, weekdayOrdinal: ordinal)])
        case .interval:
            return .interval(minutes: intervalValue * (intervalHours ? 60 : 1))
        }
    }

    private func loadExisting() {
        guard let b = existing else { return }
        label = b.label
        durationMinutes = b.durationMinutes
        switch b.schedule {
        case .oneShot(let dt):
            freq = .oneShot; date = dt   // "Daqui a X" salvo vira oneShot absoluto (aceito)
        case .interval(let min):
            freq = .interval
            if min % 60 == 0 { intervalHours = true; intervalValue = max(1, min / 60) }
            else { intervalHours = false; intervalValue = min }
        case .calendar(let comps):
            loadCalendar(comps)
        }
    }

    private func loadCalendar(_ comps: [DateComponents]) {
        guard let first = comps.first else { return }
        setTime(hour: first.hour ?? 9, minute: first.minute ?? 0)
        if let ord = first.weekdayOrdinal, let wd = first.weekday {
            freq = .nth; ordinal = ord; nthWeekday = wd
        } else if first.weekday != nil {
            freq = .weekly; weekdays = Set(comps.compactMap { $0.weekday })
        } else if let mo = first.month, let day = first.day {
            freq = .yearly; month = mo; dayOfMonth = day
        } else if let day = first.day {
            freq = .monthly; dayOfMonth = day
        } else {
            freq = .daily
        }
    }

    private func setTime(hour: Int, minute: Int) {
        var c = ReminderClock.calendar.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour; c.minute = minute
        if let dt = ReminderClock.calendar.date(from: c) { time = dt }
    }

    private func save() {
        var b = existing ?? ScreenBreak(schedule: makeSchedule())
        b.label = label.trimmingCharacters(in: .whitespaces)
        b.schedule = makeSchedule()
        b.durationMinutes = durationMinutes
        onSave(b)
        dismiss()
    }

    static func defaultTime() -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 9; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }
}
