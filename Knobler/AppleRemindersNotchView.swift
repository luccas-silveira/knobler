import SwiftUI

struct AppleRemindersNotchView: View {
    @ObservedObject var store: AppleRemindersStore
    @ObservedObject var ui: AppleRemindersUI
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onKeyboard: () -> Void = {}
    @FocusState private var titleFocused: Bool
    @State private var visible = false
    @State private var ownsDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lembretes").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Atualizar lembretes").disabled(store.loading || store.busy)
                Button("Gerenciar") { ui.show() }
                Button { requestDraftChange { ui.newReminder() } } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Novo lembrete")
                    .disabled(store.access != .authorized || store.busy)
            }
            if store.access != .authorized {
                AppleRemindersPermissionView(store: store)
            } else if let value = ui.draft {
                let draft = Binding(get: { ui.draft ?? value }, set: { if ui.draft != nil { ui.draft = $0 } })
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ui.original == nil ? "Novo lembrete" : "Rascunho em edição").font(.headline)
                        TextField("Título do lembrete", text: draft.title)
                            .textFieldStyle(.roundedBorder)
                            .focused($titleFocused)
                            .accessibilityIdentifier("lembretes-rapido-titulo")
                        Picker("Lista", selection: draft.listID) {
                            if !store.lists.contains(where: { $0.id == value.listID && $0.writable }) {
                                Text("Selecione uma lista").tag(value.listID)
                            }
                            ForEach(store.lists.filter(\.writable)) { list in
                                Text("\(list.title) — \(store.accounts.first { $0.id == list.accountID }?.title ?? "")").tag(list.id)
                            }
                        }.pickerStyle(.menu)
                        AppleReminderDueFields(draft: draft)
                    }.disabled(store.busy || ui.original?.writable == false)
                }
                if let error = ui.error ?? store.error {
                    Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button("Cancelar") { requestDraftChange { ui.cancel() } }
                    Button("Mais detalhes") { ui.show() }
                    Spacer()
                    Button(store.busy ? "Salvando…" : "Salvar") { ui.save() }
                        .disabled(value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ui.original?.writable == false)
                }.disabled(store.busy)
            } else {
                if store.loading { ProgressView("Atualizando…").controlSize(.small) }
                let items = AppleReminder.visible(store.items, filter: .today, search: "", now: Date())
                if items.isEmpty && !store.loading {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle").font(.title)
                        Text("Nenhum lembrete para hoje")
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(items) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    Button { ui.complete(item) } label: { Image(systemName: "circle") }
                                        .accessibilityLabel("Concluir \(item.draft.title)")
                                        .disabled(!item.writable || store.busy)
                                    Button { ui.edit(item) } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.draft.title).lineLimit(3)
                                            if let due = item.draft.dueDate {
                                                Text(due, format: item.draft.hasTime ? .dateTime.day().month().hour().minute() : .dateTime.day().month())
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                if let error = ui.error ?? store.error {
                    Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .font(.system(size: 12))
        .environment(\.colorScheme, .dark)
        .onAppear { visible = true; store.refresh(); updateEditing() }
        .onChange(of: ui.draft != nil) { _, _ in updateEditing() }
        .onChange(of: ui.confirmDiscard) { _, showing in if !showing { ownsDiscard = false } }
        .onDisappear { visible = false; onEditingChanged(false) }
        .alert("Descartar alterações?", isPresented: Binding(get: { ownsDiscard && ui.confirmDiscard && !ui.windowVisible }, set: { if !$0 { ui.confirmDiscard = false } })) {
            Button("Continuar editando", role: .cancel) { ui.keepEditing() }
            Button("Descartar", role: .destructive) { ui.discard() }
        } message: { Text("As alterações deste rascunho ainda não foram salvas.") }
    }

    private func requestDraftChange(_ action: () -> Void) {
        // A confirmação aparece apenas na superfície que recebeu a ação.
        ownsDiscard = !ui.windowVisible
        if ui.windowVisible { ui.show() }
        action()
    }

    private func updateEditing() {
        onEditingChanged(ui.draft != nil)
        if ui.draft != nil {
            DispatchQueue.main.async {
                guard visible, ui.draft != nil, !ui.windowVisible else { return }
                onKeyboard()
                titleFocused = true
            }
        }
    }
}
