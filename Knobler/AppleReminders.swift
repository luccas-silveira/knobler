import Foundation

enum AppleRemindersAccess { case notDetermined, authorized, denied, restricted }

enum AppleRemindersError: LocalizedError, Equatable {
    case conflict([String]), message(String), notFound, noAccess
    var errorDescription: String? {
        switch self {
        case .conflict(let fields): return "Este lembrete mudou na Apple: \(fields.joined(separator: ", ")). Revise antes de substituir."
        case .message(let text): return text
        case .notFound: return "Este item foi apagado na Apple. Seu rascunho foi preservado."
        case .noAccess: return "Autorize o acesso aos Lembretes nos Ajustes do macOS."
        }
    }
}

struct AppleReminderAccount: Identifiable, Equatable {
    var id: String
    var title: String
}

struct AppleReminderList: Identifiable, Equatable {
    var id: String
    var title: String
    var accountID: String
    var writable: Bool
    var editable: Bool = true
}

struct AppleReminderRecurrence: Equatable {
    enum Frequency: String, CaseIterable { case none, daily, weekly, monthly, yearly, custom }
    enum End: String, CaseIterable { case never, date, count }
    var frequency: Frequency = .none
    var interval = 1
    var weekdays: Set<Int> = []
    var end: End = .never
    var endDate: Date = .distantFuture
    var count = 1
    var customDescription = ""
    var customFingerprint = ""
}

struct AppleReminderDraft: Equatable {
    var title = ""
    var notes = ""
    var url = ""
    var listID = ""
    var priority = 0
    var dueDate: Date? = nil
    var hasTime = false
    var recurrence = AppleReminderRecurrence()
    var alarmAtDue = false

    func validated(original: Self? = nil) throws -> Self {
        var copy = self
        if original?.title != title { copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
        if original?.url != url { copy.url = url.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let dueDate, original?.dueDate != dueDate || original?.hasTime != hasTime {
            copy.dueDate = AppleReminder.dateComponents(dueDate, hasTime: hasTime).date
        }
        guard !copy.title.isEmpty else { throw AppleRemindersError.message("Informe o título.") }
        guard !listID.isEmpty else { throw AppleRemindersError.message("Escolha uma lista.") }
        guard (0...9).contains(priority) else { throw AppleRemindersError.message("Prioridade inválida.") }
        if !copy.url.isEmpty && original?.url != url {
            guard let link = URL(string: copy.url), let scheme = link.scheme, !scheme.isEmpty else {
                throw AppleRemindersError.message("Informe um link completo, incluindo o protocolo.")
            }
        }
        if recurrence.frequency != .none && recurrence.frequency != .custom {
            guard let dueDate else { throw AppleRemindersError.message("Defina um prazo para repetir.") }
            guard recurrence.interval > 0, recurrence.count > 0,
                  recurrence.weekdays.allSatisfy({ (1...7).contains($0) }) else {
                throw AppleRemindersError.message("Repetição inválida.")
            }
            if recurrence.end == .date && original?.recurrence != recurrence {
                let calendar = Calendar(identifier: .gregorian)
                copy.recurrence.endDate = calendar.date(byAdding: .second, value: -1, to: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: recurrence.endDate))!)!
            }
            if recurrence.end == .date && copy.recurrence.endDate < dueDate {
                throw AppleRemindersError.message("O término da repetição deve ser posterior ao prazo.")
            }
        }
        if alarmAtDue && (dueDate == nil || !hasTime) {
            throw AppleRemindersError.message("Defina uma data e horário para o aviso.")
        }
        return copy
    }

    func merging(original: Self, current: Self) -> Self {
        var merged = current
        func update<T: Equatable>(_ key: WritableKeyPath<Self, T>) {
            if self[keyPath: key] != original[keyPath: key] { merged[keyPath: key] = self[keyPath: key] }
        }
        update(\.title); update(\.notes); update(\.url); update(\.listID); update(\.priority)
        if dueDate != original.dueDate || hasTime != original.hasTime {
            merged.dueDate = dueDate; merged.hasTime = hasTime
        }
        update(\.recurrence); update(\.alarmAtDue)
        return merged
    }

    /// Só campos alterados pelo usuário participam da resolução de conflitos.
    func conflicts(original: Self, current: Self) -> [String] {
        var result: [String] = []
        func check<T: Equatable>(_ key: KeyPath<Self, T>, _ name: String) {
            if self[keyPath: key] != original[keyPath: key] && current[keyPath: key] != original[keyPath: key]
                && self[keyPath: key] != current[keyPath: key] { result.append(name) }
        }
        check(\.title, "título"); check(\.notes, "notas"); check(\.url, "link")
        check(\.listID, "lista"); check(\.priority, "prioridade")
        if (dueDate != original.dueDate || hasTime != original.hasTime)
            && (current.dueDate != original.dueDate || current.hasTime != original.hasTime)
            && (dueDate != current.dueDate || hasTime != current.hasTime) { result.append("prazo e horário") }
        check(\.recurrence, "repetição"); check(\.alarmAtDue, "aviso")
        return result
    }
}

enum AppleReminderFilter: Equatable {
    case today, scheduled, all, completed, list(String)
}

struct AppleReminder: Identifiable, Equatable {
    var id: String
    var draft: AppleReminderDraft
    var completed: Bool
    var writable: Bool

    static func visible(_ items: [Self], filter: AppleReminderFilter, search: String = "", now: Date = Date()) -> [Self] {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        return items.filter { item in
            let matches: Bool
            switch filter {
            case .today: matches = !item.completed && item.draft.dueDate.map { $0 < tomorrow } == true
            case .scheduled: matches = !item.completed && item.draft.dueDate != nil
            case .all: matches = !item.completed
            case .completed: matches = item.completed
            case .list(let id): matches = !item.completed && item.draft.listID == id
            }
            return matches && (search.isEmpty || item.draft.title.localizedCaseInsensitiveContains(search)
                || item.draft.notes.localizedCaseInsensitiveContains(search))
        }.sorted {
            let a = $0.draft, b = $1.draft
            if a.dueDate != b.dueDate { return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture) }
            if a.priority != b.priority { return (a.priority == 0 ? 10 : a.priority) < (b.priority == 0 ? 10 : b.priority) }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    static func dateComponents(_ date: Date, hasTime: Bool) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var parts = calendar.dateComponents(hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: date)
        parts.calendar = calendar
        if hasTime { parts.timeZone = calendar.timeZone }
        return parts
    }
}
