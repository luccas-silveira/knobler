//
//  RemindersView.swift
//  Knobler
//
//  Aba "Lembretes" na janela de Ajustes: lista (liga/desliga, editar, apagar) +
//  formulário de criar/editar. Edita AppSettings.shared.reminders direto.
//

import SwiftUI
import AppKit

struct RemindersView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var editing: Reminder?
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            if settings.reminders.isEmpty {
                ContentUnavailableView("Sem lembretes", systemImage: "bell.slash",
                    description: Text("Toque em + para criar um lembrete programado."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(settings.reminders) { r in row(r) }
                        .onDelete { settings.reminders.remove(atOffsets: $0) }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button { creating = true } label: {
                    Image(systemName: "plus").frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless).padding(8)
            }
        }
        .sheet(isPresented: $creating) {
            ReminderFormView(reminder: nil) { settings.reminders.append($0) }
        }
        .sheet(item: $editing) { r in
            ReminderFormView(reminder: r) { edited in
                if let i = settings.reminders.firstIndex(where: { $0.id == edited.id }) {
                    settings.reminders[i] = edited
                }
            }
        }
    }

    private func row(_ r: Reminder) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title.isEmpty ? "(sem título)" : r.title)
                Text(r.scheduleSummary()).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { r.enabled },
                set: { on in
                    if let i = settings.reminders.firstIndex(where: { $0.id == r.id }) {
                        settings.reminders[i].enabled = on
                    }
                }))
                .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = r }
    }
}

private struct ReminderFormView: View {
    enum Freq: String, CaseIterable, Identifiable {
        case oneShot = "Uma vez", daily = "Diária", weekly = "Semanal"
        case monthly = "Mensal", yearly = "Anual", nth = "N-ésimo dia", interval = "Intervalo"
        var id: String { rawValue }
    }

    let existing: Reminder?
    let onSave: (Reminder) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var freq: Freq = .daily
    @State private var time = ReminderFormView.defaultTime()   // hora (modos de relógio)
    @State private var date = Date()                            // oneShot: data+hora
    @State private var weekdays: Set<Int> = [2]                 // 1=Dom..7=Sáb
    @State private var dayOfMonth = 1
    @State private var month = 1
    @State private var ordinal = 1                              // 1..4, -1 = última
    @State private var nthWeekday = 2
    @State private var intervalValue = 2
    @State private var intervalHours = true
    @State private var soundName: String? = "Glass"
    @State private var openURL = ""
    @State private var soundReady = false   // ponytail: só toca preview após load inicial

    init(reminder: Reminder?, onSave: @escaping (Reminder) -> Void) {
        self.existing = reminder
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Título", text: $title)
                    TextField("Descrição (opcional)", text: $bodyText)
                }
                Section("Quando") {
                    Picker("Frequência", selection: $freq) {
                        ForEach(Freq.allCases) { Text($0.rawValue).tag($0) }
                    }
                    freqFields
                }
                Section("Ao disparar") {
                    Picker("Som", selection: $soundName) {
                        Text("Nenhum").tag(String?.none)
                        ForEach(ReminderSounds.all, id: \.self) { s in
                            Text(s).tag(String?.some(s))
                        }
                    }
                    .onChange(of: soundName) { _, new in
                        if soundReady, let new { NSSound(named: new)?.play() }
                    }
                    TextField("Abrir ao clicar (URL, opcional)", text: $openURL)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button("Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 380, height: 480)
        .onAppear {
            loadExisting()
            // ponytail: libera o preview só no próximo ciclo, depois do load programático
            DispatchQueue.main.async { soundReady = true }
        }
    }

    @ViewBuilder private var freqFields: some View {
        switch freq {
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
        guard let r = existing else { return }
        title = r.title; bodyText = r.body
        soundName = r.soundName; openURL = r.openURL ?? ""
        switch r.schedule {
        case .oneShot(let dt):
            freq = .oneShot; date = dt
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
        var r = existing ?? Reminder(title: title, schedule: makeSchedule())
        r.title = title.trimmingCharacters(in: .whitespaces)
        r.body = bodyText
        r.schedule = makeSchedule()
        r.soundName = soundName
        let url = openURL.trimmingCharacters(in: .whitespaces)
        r.openURL = url.isEmpty ? nil : url
        onSave(r)
        dismiss()
    }

    static func defaultTime() -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 9; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }
}
