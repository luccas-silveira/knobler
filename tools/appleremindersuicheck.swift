import AppKit
import Foundation

@main
struct AppleRemindersUICheck {
    @MainActor static func main() {
        // Store sintético nunca solicita permissão nem altera dados da Apple.
        let store = AppleRemindersStore(snapshot: true)
        store.defaultListID = "lista"
        let ui = AppleRemindersUI(store: store)
        ui.newReminder()
        assert(ui.draft?.listID == "lista")
        ui.cancel()
        assert(ui.draft == nil, "Rascunho intacto pode ser descartado diretamente")

        ui.newReminder()
        ui.draft?.title = "Texto importante"
        let edited = ui.draft
        ui.cancel()
        assert(ui.confirmDiscard && ui.draft == edited)
        ui.keepEditing()
        assert(!ui.confirmDiscard && ui.draft == edited)

        ui.newReminder()
        assert(ui.confirmDiscard && ui.draft == edited, "Novo não substitui edição sem confirmação")
        ui.discard()
        assert(ui.draft?.title == "" && !ui.confirmDiscard)

        ui.draft?.title = "Preservar após erro"
        let failedDraft = ui.draft
        ui.save()
        assert(ui.error == .noAccess && ui.draft == failedDraft, "Falha mantém o rascunho")

        store.busy = true
        ui.cancel()
        ui.newReminder()
        assert(ui.draft == failedDraft && !ui.confirmDiscard, "Operação pendente bloqueia substituição")
        store.busy = false
        ui.cancel()
        ui.discard()
        assert(ui.draft == nil && ui.error == nil)
        ui.discard()
        assert(ui.draft == nil, "Confirmação repetida não recria rascunho")
        print("appleremindersuicheck: OK")
    }
}
