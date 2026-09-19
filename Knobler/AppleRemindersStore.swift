import AppKit
import Combine
import EventKit

/// Interface na main thread; objetos EventKit nunca saem da fila serial.
final class AppleRemindersStore: ObservableObject {
    @Published var items: [AppleReminder] = []
    @Published var lists: [AppleReminderList] = []
    @Published var accounts: [AppleReminderAccount] = []
    @Published var access: AppleRemindersAccess = .notDetermined
    @Published var loading = false
    @Published var busy = false
    @Published var error: AppleRemindersError?
    @Published var defaultListID: String?
    private let queue = DispatchQueue(label: "com.zoi.knobler.apple-reminders")
    private var eventStore: EKEventStore?
    private var generation = 0
    private var fetchFailed = false
    private var observers: [NSObjectProtocol] = []
    private let snapshot: Bool
    typealias Completion = (Result<Void, AppleRemindersError>) -> Void

    init(snapshot: Bool = false) {
        self.snapshot = snapshot
        guard !snapshot else { access = .authorized; return }
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        refresh()
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func store() -> EKEventStore {
        if let eventStore { return eventStore }
        let value = EKEventStore(); eventStore = value; return value
    }

    private static var authorization: AppleRemindersAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        default: return .denied
        }
    }

    func requestAccess() {
        guard !snapshot, !busy else { return }
        busy = true
        queue.async { [weak self] in
            guard let self else { return }
            self.store().requestFullAccessToReminders { _, failure in
                DispatchQueue.main.async {
                    self.busy = false
                    if let failure { self.error = .message(failure.localizedDescription) }
                    self.refresh()
                }
            }
        }
    }

    func refresh() {
        guard !snapshot else { return }
        generation += 1
        let token = generation
        access = Self.authorization
        guard access == .authorized else {
            items = []; lists = []; accounts = []; defaultListID = nil; loading = false
            return
        }
        loading = true
        queue.async { [weak self] in
            guard let self else { return }
            let store = self.store()
            let calendars = store.calendars(for: .reminder)
            let lists = calendars.map { AppleReminderList(id: $0.calendarIdentifier, title: $0.title, accountID: $0.source.sourceIdentifier, writable: $0.allowsContentModifications, editable: !$0.isImmutable) }
            let sources = store.sources.filter { $0.sourceType != .subscribed && $0.sourceType != .birthdays }
            let accounts = sources.map { AppleReminderAccount(id: $0.sourceIdentifier, title: $0.title) }
            let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
            store.fetchReminders(matching: store.predicateForReminders(in: calendars)) { reminders in
                self.queue.async {
                    let mapped = reminders?.map(Self.model)
                    DispatchQueue.main.async {
                        self.receiveFetch(mapped, token: token, lists: lists, accounts: accounts,
                                          defaultID: defaultID, authorization: Self.authorization)
                    }
                }
            }
        }
    }

    /// Publicação separada da consulta para verificar respostas fora de ordem sem acessar contas.
    func receiveFetch(_ fetched: [AppleReminder]?, token: Int, lists: [AppleReminderList],
                      accounts: [AppleReminderAccount], defaultID: String?, authorization: AppleRemindersAccess) {
        guard token == generation else { return }
        loading = false
        access = authorization
        guard authorization == .authorized else {
            items = []; self.lists = []; self.accounts = []; defaultListID = nil
            return
        }
        guard let fetched else { fetchFailed = true; error = .message("Não foi possível consultar os lembretes. Tente atualizar."); return }
        if fetchFailed { error = nil; fetchFailed = false }
        items = fetched; self.lists = lists; self.accounts = accounts; defaultListID = defaultID
    }

    private func mutate(_ completion: @escaping Completion, operation: @escaping (EKEventStore) throws -> Void) {
        guard !busy else { completion(.failure(.message("Aguarde a operação em andamento."))); return }
        guard !snapshot, Self.authorization == .authorized else { completion(.failure(.noAccess)); return }
        busy = true; error = nil; fetchFailed = false; generation += 1
        queue.async {
            let result: Result<Void, AppleRemindersError>
            do { try operation(self.store()); result = .success(()) }
            catch let failure as AppleRemindersError { self.eventStore = nil; result = .failure(failure) }
            catch { self.eventStore = nil; result = .failure(.message(error.localizedDescription)) }
            DispatchQueue.main.async {
                self.busy = false
                if case .failure(let failure) = result { self.error = failure }
                self.refresh(); completion(result)
            }
        }
    }

    func save(_ draft: AppleReminderDraft, original: AppleReminder? = nil, overwriteConflict: Bool = false, completion: @escaping Completion = { _ in }) {
        mutate(completion) { store in
            var draft = try draft.validated(original: original?.draft)
            let reminder: EKReminder
            if let original { reminder = try Self.existing(original.id, store: store) }
            else { reminder = EKReminder(eventStore: store) }
            let current = original.map { _ in Self.model(reminder).draft }
            if let original, let current, !overwriteConflict {
                let conflicts = draft.conflicts(original: original.draft, current: current)
                guard conflicts.isEmpty else { throw AppleRemindersError.conflict(conflicts) }
            }
            let preserveAnchor = original != nil && current?.recurrence != original?.draft.recurrence && draft.recurrence == original?.draft.recurrence
            if let original, let current { draft = try draft.merging(original: original.draft, current: current).validated(original: current) }
            let old = current
            if old == nil || old?.listID != draft.listID {
                guard let calendar = store.calendar(withIdentifier: draft.listID) else { throw AppleRemindersError.notFound }
                guard calendar.allowsContentModifications else { throw AppleRemindersError.message("Esta lista é somente leitura.") }
                reminder.calendar = calendar
            }
            Self.apply(draft, original: old, to: reminder, preserveRecurrenceAnchor: preserveAnchor)
            try store.save(reminder, commit: true)
        }
    }

    /// Aplica somente campos editados; também usado pelos checks sem acesso a contas.
    static func apply(_ draft: AppleReminderDraft, original old: AppleReminderDraft?, to reminder: EKReminder, preserveRecurrenceAnchor: Bool = false) {
        let currentRecurrence = recurrence(reminder.recurrenceRules ?? [], due: reminder.dueDateComponents?.date)
        let canReanchor = !preserveRecurrenceAnchor && (old == nil || (currentRecurrence == old?.recurrence && currentRecurrence.frequency != .custom))
        if old == nil || old?.title != draft.title { reminder.title = draft.title }
        if old == nil || old?.notes != draft.notes { reminder.notes = draft.notes.isEmpty ? nil : draft.notes }
        if old == nil || old?.url != draft.url { reminder.url = draft.url.isEmpty ? nil : URL(string: draft.url) }
        if old == nil || old?.priority != draft.priority { reminder.priority = draft.priority }
        if old == nil || old?.dueDate != draft.dueDate || old?.hasTime != draft.hasTime {
            reminder.dueDateComponents = draft.dueDate.map { AppleReminder.dateComponents($0, hasTime: draft.hasTime) }
            // EventKit exige início para calcular recorrências.
            if draft.recurrence.frequency != .none && canReanchor { reminder.startDateComponents = reminder.dueDateComponents }
        }
        if old == nil || old?.recurrence != draft.recurrence || (canReanchor && old?.dueDate != draft.dueDate && [.monthly, .yearly].contains(draft.recurrence.frequency)) {
            if draft.recurrence.frequency != .custom { reminder.recurrenceRules = Self.rule(draft).map { [$0] } }
            if draft.recurrence.frequency != .none && reminder.startDateComponents == nil { reminder.startDateComponents = reminder.dueDateComponents }
        }
        if old == nil || old?.alarmAtDue != draft.alarmAtDue {
            // Não tocar em alarmes de localização, relativos ou de outros horários.
            let previousDue = old?.dueDate
            var alarms = reminder.alarms ?? []
            alarms.removeAll { $0.structuredLocation == nil && ($0.absoluteDate == previousDue && previousDue != nil) }
            if draft.alarmAtDue, let due = draft.dueDate { alarms.append(EKAlarm(absoluteDate: due)) }
            reminder.alarms = alarms
        } else if draft.alarmAtDue, let old, old.dueDate != draft.dueDate, let due = draft.dueDate {
            // O aviso oferecido pelo editor acompanha o prazo; outros alarmes permanecem.
            reminder.alarms?.filter { $0.structuredLocation == nil && $0.absoluteDate == old.dueDate }.forEach { $0.absoluteDate = due }
        }
    }

    func setCompleted(_ item: AppleReminder, completed: Bool, completion: @escaping Completion = { _ in }) {
        mutate(completion) { store in
            let reminder = try Self.existing(item.id, store: store)
            reminder.isCompleted = completed
            try store.save(reminder, commit: true)
        }
    }

    func delete(_ item: AppleReminder, completion: @escaping Completion = { _ in }) {
        mutate(completion) { store in try store.remove(Self.existing(item.id, store: store), commit: true) }
    }

    func createList(title: String, accountID: String, completion: @escaping Completion = { _ in }) {
        mutate(completion) { store in
            guard let source = store.source(withIdentifier: accountID) else { throw AppleRemindersError.notFound }
            let calendar = EKCalendar(for: .reminder, eventStore: store)
            calendar.title = try Self.listTitle(title); calendar.source = source
            try store.saveCalendar(calendar, commit: true)
        }
    }

    func renameList(_ list: AppleReminderList, title: String, completion: @escaping Completion = { _ in }) {
        mutate(completion) { store in
            let calendar = try Self.editableCalendar(list.id, store: store)
            calendar.title = try Self.listTitle(title)
            try store.saveCalendar(calendar, commit: true)
        }
    }

    func deleteList(_ list: AppleReminderList, completion: @escaping Completion = { _ in }) {
        mutate(completion) { store in try store.removeCalendar(Self.editableCalendar(list.id, store: store), commit: true) }
    }

    private static func listTitle(_ title: String) throws -> String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw AppleRemindersError.message("Informe o nome da lista.") }
        return value
    }

    private static func editableCalendar(_ id: String, store: EKEventStore) throws -> EKCalendar {
        guard let calendar = store.calendar(withIdentifier: id) else { throw AppleRemindersError.notFound }
        guard !calendar.isImmutable else { throw AppleRemindersError.message("Esta lista não permite alteração.") }
        return calendar
    }

    private static func existing(_ id: String, store: EKEventStore) throws -> EKReminder {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { throw AppleRemindersError.notFound }
        reminder.reset()
        guard reminder.refresh() else { throw AppleRemindersError.notFound }
        guard reminder.calendar.allowsContentModifications else { throw AppleRemindersError.message("Esta lista é somente leitura.") }
        return reminder
    }

    static func model(_ item: EKReminder) -> AppleReminder {
        var draft = AppleReminderDraft(title: item.title ?? "", notes: item.notes ?? "", url: item.url?.absoluteString ?? "", listID: item.calendar.calendarIdentifier, priority: item.priority)
        if var components = item.dueDateComponents {
            if components.calendar == nil { components.calendar = Calendar(identifier: .gregorian) }
            draft.dueDate = components.date
            draft.hasTime = components.hour != nil
        }
        draft.recurrence = recurrence(item.recurrenceRules ?? [], due: draft.dueDate)
        draft.alarmAtDue = draft.hasTime && draft.dueDate != nil && (item.alarms ?? []).contains { $0.absoluteDate == draft.dueDate && $0.structuredLocation == nil }
        return AppleReminder(id: item.calendarItemIdentifier, draft: draft, completed: item.isCompleted, writable: item.calendar.allowsContentModifications)
    }

    static func recurrence(_ rules: [EKRecurrenceRule], due: Date?) -> AppleReminderRecurrence {
        guard let rule = rules.first else { return AppleReminderRecurrence() }
        var result = AppleReminderRecurrence()
        let dueParts = due.map { AppleReminder.dateComponents($0, hasTime: false) }
        let monthlySupported = rule.daysOfTheMonth == nil || ([.monthly, .yearly].contains(rule.frequency) && rule.daysOfTheMonth == dueParts?.day.map { [NSNumber(value: $0)] })
        let yearlySupported = rule.monthsOfTheYear == nil || (rule.frequency == .yearly && rule.monthsOfTheYear == dueParts?.month.map { [NSNumber(value: $0)] })
        guard rules.count == 1, rule.weeksOfTheYear == nil, rule.daysOfTheYear == nil, rule.setPositions == nil,
              monthlySupported, yearlySupported, [0, 2].contains(rule.firstDayOfTheWeek),
              (rule.daysOfTheWeek ?? []).allSatisfy({ $0.weekNumber == 0 }),
              rule.frequency == .weekly || rule.daysOfTheWeek == nil else {
            result.frequency = .custom
            result.customDescription = "Repetição personalizada da Apple (preservada)"
            result.customFingerprint = rules.map { rule in
                [String(rule.frequency.rawValue), String(rule.interval), String(rule.firstDayOfTheWeek),
                 (rule.daysOfTheWeek ?? []).map { "\($0.dayOfTheWeek.rawValue):\($0.weekNumber)" }.joined(separator: ","),
                 String(describing: rule.daysOfTheMonth), String(describing: rule.monthsOfTheYear),
                 String(describing: rule.weeksOfTheYear), String(describing: rule.daysOfTheYear),
                 String(describing: rule.setPositions), String(describing: rule.recurrenceEnd?.endDate),
                 String(describing: rule.recurrenceEnd?.occurrenceCount)].joined(separator: "|")
            }.joined(separator: ";")
            return result
        }
        switch rule.frequency { case .daily: result.frequency = .daily; case .weekly: result.frequency = .weekly; case .monthly: result.frequency = .monthly; case .yearly: result.frequency = .yearly; @unknown default: result.frequency = .custom }
        result.interval = rule.interval
        result.weekdays = Set((rule.daysOfTheWeek ?? []).map { $0.dayOfTheWeek.rawValue })
        if let end = rule.recurrenceEnd {
            if let date = end.endDate { result.end = .date; result.endDate = date }
            else if end.occurrenceCount > 0 { result.end = .count; result.count = end.occurrenceCount }
        }
        return result
    }

    static func rule(_ draft: AppleReminderDraft) -> EKRecurrenceRule? {
        let value = draft.recurrence
        let frequency: EKRecurrenceFrequency
        switch value.frequency { case .daily: frequency = .daily; case .weekly: frequency = .weekly; case .monthly: frequency = .monthly; case .yearly: frequency = .yearly; default: return nil }
        let end: EKRecurrenceEnd?
        switch value.end { case .never: end = nil; case .date: end = EKRecurrenceEnd(end: value.endDate); case .count: end = EKRecurrenceEnd(occurrenceCount: value.count) }
        let weekdays = value.weekdays.sorted().compactMap { EKWeekday(rawValue: $0).map { EKRecurrenceDayOfWeek($0) } }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: value.interval, daysOfTheWeek: frequency == .weekly && !weekdays.isEmpty ? weekdays : nil, daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
    }
}
