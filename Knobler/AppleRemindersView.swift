import AppKit
import SwiftUI

/// Uma sessão compartilhada mantém o rascunho ao fechar o notch ou a janela.
@MainActor
final class AppleRemindersUI: NSObject, ObservableObject, NSWindowDelegate {
    let store: AppleRemindersStore
    @Published var draft: AppleReminderDraft?
    @Published var original: AppleReminder?
    @Published var error: AppleRemindersError?
    @Published var confirmDiscard = false
    @Published var windowVisible = false
    private var initialDraft: AppleReminderDraft?
    private var afterDiscard: (() -> Void)?
    private var window: NSWindow?

    init(store: AppleRemindersStore) { self.store = store }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Lembretes"
            window.minSize = NSSize(width: 780, height: 540)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AppleRemindersView(store: store, ui: self))
            window.delegate = self
            window.center()
            self.window = window
        }
        windowVisible = true
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        store.refresh()
    }

    func windowWillClose(_ notification: Notification) { windowVisible = false }
    func windowDidMiniaturize(_ notification: Notification) { windowVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { windowVisible = true }

    func newReminder() {
        replaceDraft {
            self.original = nil
            self.draft = AppleReminderDraft(listID: self.store.defaultListID ?? "")
            self.initialDraft = self.draft
            self.error = nil
        }
    }

    func edit(_ item: AppleReminder) {
        show()
        replaceDraft {
            self.original = item
            self.draft = item.draft
            self.initialDraft = item.draft
            self.error = nil
        }
    }

    func cancel() { replaceDraft { self.clear() } }
    func discard() {
        let action = afterDiscard
        afterDiscard = nil
        confirmDiscard = false
        action?()
    }
    func keepEditing() { afterDiscard = nil; confirmDiscard = false }

    private func replaceDraft(_ action: @escaping () -> Void) {
        guard !store.busy else { return }
        if draft != nil && draft != initialDraft {
            afterDiscard = action
            confirmDiscard = true
        } else { action() }
    }

    private func clear() { draft = nil; original = nil; initialDraft = nil; error = nil }

    func save(overwrite: Bool = false) {
        guard let draft, !store.busy else { return }
        error = nil
        store.save(draft, original: original, overwriteConflict: overwrite) { result in
            switch result {
            case .success: self.clear()
            case .failure(let error): self.error = error
            }
        }
    }

    func complete(_ item: AppleReminder) {
        store.setCompleted(item, completed: !item.completed) { result in
            if case .failure(let error) = result { self.error = error }
        }
    }
}

struct AppleRemindersView: View {
    @ObservedObject var store: AppleRemindersStore
    @ObservedObject var ui: AppleRemindersUI
    @State private var filter = AppleReminderFilter.today
    @State private var search = ""
    @State private var listSheet = false
    @State private var listToEdit: AppleReminderList?
    @State private var listTitle = ""
    @State private var accountID = ""
    @State private var deleteList: AppleReminderList?
    @State private var deleteItem: AppleReminder?

    private var items: [AppleReminder] {
        AppleReminder.visible(store.items, filter: filter, search: search, now: Date())
    }

    var body: some View {
        HSplitView {
            List {
                sidebar("Hoje e atrasados", symbol: "sun.max", filter: .today)
                sidebar("Programados", symbol: "calendar", filter: .scheduled)
                sidebar("Todos", symbol: "tray", filter: .all)
                sidebar("Concluídos", symbol: "checkmark.circle", filter: .completed)
                ForEach(store.accounts) { account in
                    Section(account.title) {
                        ForEach(store.lists.filter { $0.accountID == account.id }) { list in
                            sidebar(list.title, symbol: "list.bullet", filter: .list(list.id))
                                .contextMenu {
                                    Button("Renomear lista") { prepareList(list) }.disabled(!list.editable)
                                    Button("Excluir lista…", role: .destructive) { deleteList = list }
                                        .disabled(!list.editable || store.busy)
                                }
                        }
                    }
                }
                Button("Nova lista…", systemImage: "plus") { prepareList(nil) }
                    .disabled(store.access != .authorized || store.busy)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 190, idealWidth: 210, maxWidth: 270)
            VStack(spacing: 12) {
                HStack {
                    TextField("Buscar título ou notas", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("lembretes-busca")
                    Button("Atualizar", systemImage: "arrow.clockwise") { store.refresh() }.disabled(store.loading || store.busy)
                    Button("Novo lembrete", systemImage: "plus") { ui.newReminder() }
                        .disabled(store.access != .authorized || store.busy)
                }
                if store.access != .authorized {
                    AppleRemindersPermissionView(store: store)
                } else if ui.draft != nil {
                    AppleReminderEditor(store: store, ui: ui)
                } else {
                    if store.loading { ProgressView("Atualizando lembretes…") }
                    if items.isEmpty && !store.loading {
                        ContentUnavailableView("Nenhum lembrete", systemImage: "checklist",
                                               description: Text("Crie um lembrete ou escolha outra visualização."))
                    } else {
                        List(items) { item in
                            HStack(alignment: .top) {
                                Button { ui.complete(item) } label: {
                                    Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item.completed ? "Reabrir lembrete" : "Concluir lembrete")
                                .disabled(!item.writable || store.busy)
                                Button { ui.edit(item) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.draft.title).strikethrough(item.completed)
                                        if let due = item.draft.dueDate {
                                            Text(due, format: item.draft.hasTime ? .dateTime.day().month().hour().minute() : .dateTime.day().month())
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Text(store.lists.first { $0.id == item.draft.listID }?.title ?? "Lista indisponível")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                            .contextMenu {
                                Button("Editar") { ui.edit(item) }
                                Button("Excluir…", role: .destructive) { deleteItem = item }
                                    .disabled(!item.writable || store.busy)
                            }
                        }
                    }
                }
                if ui.draft == nil, let error = ui.error ?? store.error {
                    Text(error.localizedDescription).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .padding(16).frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Descartar alterações?", isPresented: $ui.confirmDiscard) {
            Button("Continuar editando", role: .cancel) { ui.keepEditing() }
            Button("Descartar", role: .destructive) { ui.discard() }
        } message: { Text("As alterações deste rascunho ainda não foram salvas.") }
        .alert("Excluir lembrete?", isPresented: Binding(get: { deleteItem != nil }, set: { if !$0 { deleteItem = nil } })) {
            Button("Cancelar", role: .cancel) { deleteItem = nil }
            Button("Excluir", role: .destructive) {
                guard let item = deleteItem else { return }
                store.delete(item) { if case .failure(let error) = $0 { ui.error = error } }
                deleteItem = nil
            }
        }
        .alert("Excluir lista e seus lembretes?", isPresented: Binding(get: { deleteList != nil }, set: { if !$0 { deleteList = nil } })) {
            Button("Cancelar", role: .cancel) { deleteList = nil }
            Button("Excluir lista", role: .destructive) {
                guard let list = deleteList else { return }
                store.deleteList(list) { result in
                    if case .failure(let error) = result { ui.error = error }
                    else { filter = .all }
                }
                deleteList = nil
            }
        } message: { Text("Todos os lembretes de “\(deleteList?.title ?? "")” também serão removidos da Apple e dos dispositivos sincronizados.") }
        .sheet(isPresented: $listSheet) { listEditor }
    }

    private func sidebar(_ title: String, symbol: String, filter target: AppleReminderFilter) -> some View {
        Button { filter = target } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .foregroundStyle(filter == target ? Color.accentColor : Color.primary)
        }.buttonStyle(.plain)
    }

    private func prepareList(_ list: AppleReminderList?) {
        ui.error = nil
        listToEdit = list; listTitle = list?.title ?? ""
        accountID = list?.accountID ?? store.accounts.first?.id ?? ""
        listSheet = true
    }

    private var listEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(listToEdit == nil ? "Nova lista" : "Renomear lista").font(.headline)
            TextField("Nome da lista", text: $listTitle).textFieldStyle(.roundedBorder)
            if listToEdit == nil {
                Picker("Conta", selection: $accountID) {
                    ForEach(store.accounts) { Text($0.title).tag($0.id) }
                }
            }
            if let error = ui.error { Text(error.localizedDescription).foregroundStyle(.red) }
            HStack {
                Button("Cancelar") { listSheet = false }.disabled(store.busy)
                Spacer()
                Button("Salvar") {
                    let completion: (Result<Void, AppleRemindersError>) -> Void = {
                        if case .failure(let error) = $0 { ui.error = error }
                        else { ui.error = nil; listSheet = false }
                    }
                    if let list = listToEdit { store.renameList(list, title: listTitle, completion: completion) }
                    else { store.createList(title: listTitle, accountID: accountID, completion: completion) }
                }.disabled(store.busy || listTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || accountID.isEmpty)
            }
        }.padding(24).frame(width: 360)
    }
}

struct AppleRemindersPermissionView: View {
    @ObservedObject var store: AppleRemindersStore
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist").font(.largeTitle)
            Text("Seus Lembretes da Apple").font(.headline)
            Text("Permita o acesso para consultar e gerenciar seus lembretes.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if store.access == .notDetermined {
                Button("Permitir acesso") { store.requestAccess() }
            } else {
                Button("Abrir permissões") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AppleReminderEditor: View {
    @ObservedObject var store: AppleRemindersStore
    @ObservedObject var ui: AppleRemindersUI

    var body: some View {
        if let value = ui.draft {
            let draft = Binding(get: { ui.draft ?? value }, set: { if ui.draft != nil { ui.draft = $0 } })
            VStack(alignment: .leading, spacing: 12) {
                Text(ui.original == nil ? "Novo lembrete" : "Editar lembrete").font(.headline)
                ScrollView {
                    Form {
                        TextField("Título", text: draft.title).accessibilityIdentifier("lembretes-titulo")
                        TextField("Notas", text: draft.notes, axis: .vertical).lineLimit(3...6)
                        TextField("Link", text: draft.url)
                        Picker("Lista", selection: draft.listID) {
                            if !store.lists.contains(where: { $0.id == value.listID && $0.writable }) {
                                Text("Selecione uma lista editável").tag(value.listID)
                            }
                            ForEach(store.lists.filter(\.writable)) { list in
                                Text("\(list.title) — \(store.accounts.first { $0.id == list.accountID }?.title ?? "")").tag(list.id)
                            }
                        }
                        Picker("Prioridade", selection: Binding(get: { value.priority == 0 ? 0 : value.priority < 5 ? 1 : value.priority == 5 ? 5 : 9 }, set: { draft.wrappedValue.priority = $0 })) {
                            Text("Nenhuma").tag(0); Text("Alta").tag(1)
                            Text("Média").tag(5); Text("Baixa").tag(9)
                        }
                        AppleReminderDueFields(draft: draft)
                        recurrenceFields(draft)
                    }.formStyle(.grouped)
                }.disabled(store.busy || ui.original?.writable == false)
                if ui.original?.writable == false { Text("Esta lista permite apenas leitura.").foregroundStyle(.secondary) }
                if store.lists.filter(\.writable).isEmpty {
                    Text("Crie uma lista editável no app Lembretes ou adicione uma conta no macOS.").foregroundStyle(.secondary)
                }
                if let error = ui.error ?? store.error {
                    Text(error.localizedDescription).foregroundStyle(.red).textSelection(.enabled)
                    if case .conflict = error {
                        HStack {
                            Text("O rascunho foi preservado.")
                            Button("Aplicar minhas alterações") { ui.save(overwrite: true) }.disabled(store.busy)
                        }
                    }
                }
                HStack {
                    Button("Cancelar") { ui.cancel() }.disabled(store.busy)
                    Spacer()
                    Button(store.busy ? "Salvando…" : "Salvar") { ui.save() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("lembretes-salvar")
                        .disabled(store.busy || ui.original?.writable == false || store.access != .authorized || value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func recurrenceFields(_ draft: Binding<AppleReminderDraft>) -> some View {
        Group {
            Picker("Repetição", selection: draft.recurrence.frequency) {
                Text("Nunca").tag(AppleReminderRecurrence.Frequency.none)
                Text("Diária").tag(AppleReminderRecurrence.Frequency.daily)
                Text("Semanal").tag(AppleReminderRecurrence.Frequency.weekly)
                Text("Mensal").tag(AppleReminderRecurrence.Frequency.monthly)
                Text("Anual").tag(AppleReminderRecurrence.Frequency.yearly)
                if draft.wrappedValue.recurrence.frequency == .custom {
                    Text("Personalizada (preservar)").tag(AppleReminderRecurrence.Frequency.custom)
                }
            }
            if draft.wrappedValue.recurrence.frequency == .custom {
                Text(draft.wrappedValue.recurrence.customDescription).foregroundStyle(.secondary)
            } else if draft.wrappedValue.recurrence.frequency != .none {
                Stepper("Intervalo: \(draft.wrappedValue.recurrence.interval)", value: draft.recurrence.interval, in: 1...999)
                if draft.wrappedValue.recurrence.frequency == .weekly {
                    HStack {
                        ForEach(1...7, id: \.self) { day in
                            Toggle(["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"][day - 1], isOn: Binding(get: {
                                draft.wrappedValue.recurrence.weekdays.contains(day)
                            }, set: { selected in
                                if selected { draft.wrappedValue.recurrence.weekdays.insert(day) }
                                else { draft.wrappedValue.recurrence.weekdays.remove(day) }
                            })).toggleStyle(.button)
                        }
                    }
                }
                Picker("Termina", selection: Binding(get: { draft.wrappedValue.recurrence.end }, set: { end in
                    draft.wrappedValue.recurrence.end = end
                    if end == .date && draft.wrappedValue.recurrence.endDate == .distantFuture {
                        draft.wrappedValue.recurrence.endDate = Calendar.current.date(byAdding: .month, value: 1, to: draft.wrappedValue.dueDate ?? Date()) ?? Date()
                    }
                })) {
                    Text("Nunca").tag(AppleReminderRecurrence.End.never)
                    Text("Em uma data").tag(AppleReminderRecurrence.End.date)
                    Text("Após ocorrências").tag(AppleReminderRecurrence.End.count)
                }
                if draft.wrappedValue.recurrence.end == .date {
                    DatePicker("Último dia", selection: draft.recurrence.endDate, displayedComponents: .date).datePickerStyle(.field)
                } else if draft.wrappedValue.recurrence.end == .count {
                    Stepper("Ocorrências: \(draft.wrappedValue.recurrence.count)", value: draft.recurrence.count, in: 1...9999)
                }
            }
        }
    }
}

struct AppleReminderDueFields: View {
    @Binding var draft: AppleReminderDraft
    var body: some View {
        Toggle("Definir prazo", isOn: Binding(get: { draft.dueDate != nil }, set: { enabled in
            draft.dueDate = enabled ? Date() : nil
            if !enabled { draft.alarmAtDue = false }
        }))
        if draft.dueDate != nil {
            Toggle("Com horário", isOn: Binding(get: { draft.hasTime }, set: { enabled in
                draft.hasTime = enabled
                if !enabled { draft.alarmAtDue = false }
            }))
            DatePicker("Prazo", selection: Binding(get: { draft.dueDate ?? Date() }, set: { draft.dueDate = $0 }),
                       displayedComponents: draft.hasTime ? [.date, .hourAndMinute] : [.date]).datePickerStyle(.field)
            if draft.hasTime { Toggle("Avisar no horário", isOn: $draft.alarmAtDue) }
        }
    }
}
