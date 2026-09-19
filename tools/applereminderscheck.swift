import Foundation
import EventKit

@main
struct AppleRemindersCheck {
    static func main() throws {
        let due = Date(timeIntervalSince1970: 1_789_660_800)
        let original = AppleReminderDraft(title: "Comprar café", notes: "Original", listID: "lista", dueDate: due)
        var edited = original
        edited.title = "Comprar chá"
        var current = original
        current.notes = "Atualização da Apple"
        assert(edited.conflicts(original: original, current: current).isEmpty)
        current.title = "Comprar leite"
        assert(edited.conflicts(original: original, current: current) == ["título"])
        current.title = edited.title
        assert(edited.conflicts(original: original, current: current).isEmpty)
        assert(AppleReminder.dateComponents(due, hasTime: false).hour == nil)
        assert(AppleReminder.dateComponents(due, hasTime: true).calendar?.identifier == .gregorian)
        assert(AppleReminder.dateComponents(due, hasTime: true).hour != nil)
        var invalid = original
        invalid.title = " \n "
        assert((try? invalid.validated()) == nil)
        invalid = original; invalid.url = "sem protocolo"
        assert((try? invalid.validated()) == nil)
        invalid = original; invalid.alarmAtDue = true
        assert((try? invalid.validated()) == nil)
        invalid = original; invalid.recurrence.frequency = .daily; invalid.recurrence.interval = 0
        assert((try? invalid.validated()) == nil)
        var recurring = original
        recurring.recurrence.frequency = .weekly
        recurring.recurrence.weekdays = [2, 4, 6]
        recurring.recurrence.interval = 2
        recurring.recurrence.end = .count
        recurring.recurrence.count = 8
        let weekly = AppleRemindersStore.rule(recurring)!
        assert(AppleRemindersStore.recurrence([weekly], due: due) == recurring.recurrence)
        for frequency in [AppleReminderRecurrence.Frequency.monthly, .yearly] {
            recurring.recurrence = AppleReminderRecurrence(frequency: frequency)
            let rule = AppleRemindersStore.rule(recurring)!
            assert(rule.daysOfTheMonth == nil && rule.monthsOfTheYear == nil)
            assert(AppleRemindersStore.recurrence([rule], due: due).frequency == frequency)
        }
        let custom = EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: [-1], monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
        assert(AppleRemindersStore.recurrence([custom], due: due).frequency == .custom)
        // Restrições que coincidem com o prazo ainda não são regras simples:
        // reconstruí-las como diária/mensal apagaria a restrição da Apple.
        let dueParts = AppleReminder.dateComponents(due, hasTime: false)
        let constrainedDaily = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: [NSNumber(value: dueParts.day!)], monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
        let constrainedMonthly = EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: nil, monthsOfTheYear: [NSNumber(value: dueParts.month!)], weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
        assert(AppleRemindersStore.recurrence([constrainedDaily], due: due).frequency == .custom)
        assert(AppleRemindersStore.recurrence([constrainedMonthly], due: due).frequency == .custom)
        // Objetos desconectados: não pede autorização, não consulta e não grava contas reais.
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = original.title
        reminder.notes = "Alterado externamente"
        reminder.recurrenceRules = [custom]
        let alarm = EKAlarm(absoluteDate: due.addingTimeInterval(-300))
        reminder.alarms = [alarm]
        AppleRemindersStore.apply(edited, original: original, to: reminder)
        assert(reminder.title == edited.title)
        assert(reminder.notes == "Alterado externamente")
        assert(reminder.recurrenceRules?.first === custom)
        assert(reminder.alarms?.first === alarm)
        var withPrecision = original
        withPrecision.hasTime = true
        withPrecision.dueDate = due.addingTimeInterval(33.125)
        withPrecision.alarmAtDue = true
        let normalized = try withPrecision.validated()
        assert(normalized.dueDate == AppleReminder.dateComponents(withPrecision.dueDate!, hasTime: true).date)
        AppleRemindersStore.apply(normalized, original: nil, to: reminder)
        assert(reminder.alarms?.contains { $0.absoluteDate == reminder.dueDateComponents?.date } == true)
        var allDay = withPrecision; allDay.hasTime = false; allDay.alarmAtDue = false
        let normalizedAllDay = try allDay.validated()
        assert(Calendar.current.component(.hour, from: normalizedAllDay.dueDate!) == 0)
        var untilToday = withPrecision
        untilToday.recurrence = AppleReminderRecurrence(frequency: .daily, end: .date, endDate: due)
        let normalizedEnd = try untilToday.validated()
        assert(normalizedEnd.recurrence.endDate > untilToday.dueDate!)
        var existing = original
        existing.title = "  Título antigo  "
        existing.recurrence = AppleReminderRecurrence(frequency: .daily, end: .date, endDate: due.addingTimeInterval(86400))
        existing.dueDate = due.addingTimeInterval(33.125)
        var changedNotes = existing; changedNotes.notes = "Nova nota"
        let preserved = try changedNotes.validated(original: existing)
        assert(preserved.title == existing.title && preserved.dueDate == existing.dueDate)
        assert(preserved.recurrence == existing.recurrence)
        let oldRule = AppleRemindersStore.rule(existing)!
        reminder.recurrenceRules = [oldRule]
        AppleRemindersStore.apply(preserved, original: existing, to: reminder)
        assert(reminder.recurrenceRules?.first === oldRule)
        var switched = recurring
        switched.recurrence.frequency = .monthly
        switched.recurrence.weekdays = [2, 4]
        assert(AppleRemindersStore.rule(switched)?.daysOfTheWeek == nil)
        let nativeMonth = EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: [NSNumber(value: AppleReminder.dateComponents(due, hasTime: false).day!)], monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
        var monthDraft = original
        monthDraft.recurrence = AppleRemindersStore.recurrence([nativeMonth], due: due)
        reminder.recurrenceRules = [nativeMonth]
        reminder.dueDateComponents = AppleReminder.dateComponents(due, hasTime: false)
        var moved = monthDraft; moved.dueDate = due.addingTimeInterval(86400)
        AppleRemindersStore.apply(moved, original: monthDraft, to: reminder)
        assert(reminder.recurrenceRules?.first?.daysOfTheMonth == nil)
        assert(reminder.startDateComponents?.day == AppleReminder.dateComponents(moved.dueDate!, hasTime: false).day)
        let customCopy = custom.copy() as! EKRecurrenceRule
        assert(AppleRemindersStore.recurrence([custom], due: due) == AppleRemindersStore.recurrence([customCopy], due: due))
        var originalTimed = original; originalTimed.hasTime = true
        var localAlarm = originalTimed; localAlarm.alarmAtDue = true
        var removedDue = originalTimed; removedDue.dueDate = nil; removedDue.hasTime = false
        let mergedInvalid = localAlarm.merging(original: originalTimed, current: removedDue)
        assert((try? mergedInvalid.validated(original: removedDue)) == nil)
        var localTime = original; localTime.hasTime = true
        var externalDate = original; externalDate.dueDate = due.addingTimeInterval(86400)
        assert(localTime.conflicts(original: original, current: externalDate) == ["prazo e horário"])
        assert(edited.merging(original: original, current: externalDate).dueDate == externalDate.dueDate)
        let untimed = AppleReminder(id: "1", draft: AppleReminderDraft(title: "Sem prazo", listID: "lista"), completed: false, writable: true)
        let pending = AppleReminder(id: "2", draft: original, completed: false, writable: true)
        let complete = AppleReminder(id: "3", draft: original, completed: true, writable: true)
        assert(AppleReminder.visible([untimed, pending, complete], filter: .today, now: due).map(\.id) == ["2"])
        assert(AppleReminder.visible([untimed, pending, complete], filter: .all).map(\.id) == ["2", "1"])
        assert(AppleReminder.visible([pending, complete], filter: .completed).map(\.id) == ["3"])
        assert(AppleReminder.visible([pending], filter: .all, search: "CAFÉ").count == 1)
        assert(AppleReminder.visible([pending], filter: .list("outra")).isEmpty)
        let preview = AppleRemindersStore(snapshot: true)
        preview.refresh()
        assert(preview.access == .authorized && !preview.loading)
        preview.items = [pending]
        var rejected = false
        preview.save(original) { result in if case .failure = result { rejected = true } }
        assert(rejected && preview.items == [pending])
        preview.receiveFetch([], token: -1, lists: [], accounts: [], defaultID: nil, authorization: .authorized)
        assert(preview.items == [pending])
        preview.receiveFetch(nil, token: 0, lists: [], accounts: [], defaultID: nil, authorization: .authorized)
        assert(preview.error != nil && preview.items == [pending])
        preview.receiveFetch([pending], token: 0, lists: [], accounts: [], defaultID: nil, authorization: .authorized)
        assert(preview.error == nil)
        preview.error = .message("Falha de gravação")
        preview.receiveFetch([pending], token: 0, lists: [], accounts: [], defaultID: nil, authorization: .authorized)
        assert(preview.error != nil)
        preview.receiveFetch([], token: 0, lists: [], accounts: [], defaultID: nil, authorization: .denied)
        assert(preview.access == .denied && preview.items.isEmpty)
        print("applereminderscheck: OK")
    }
}
