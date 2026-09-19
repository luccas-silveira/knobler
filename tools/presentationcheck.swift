// Controle de abertura, arbitragem, teclado e geometria sem janela ou relógio real.
import Foundation
import CoreGraphics

@main
enum PresentationCheck {
    static func main() {
        var opening = NotchOpening()
        opening.hover(true, typing: false, now: 10)
        let old = opening.pending!
        assert(NotchMetrics.alturaDaSecao(.agenda) == NotchMetrics.agendaHeight)
        assert(opening.fire(old, now: 10.1, linkOpen: false) == nil)
        opening.setExpanded(false, now: 10.15)
        assert(opening.fire(old, now: 11, linkOpen: false) == nil)
        opening.hover(true, typing: false, now: 11)
        assert(opening.fire(opening.pending!, now: 11.2, linkOpen: false) == true)
        opening.hover(false, typing: true, now: 12)
        assert(opening.pending?.deadline == 15)
        opening.hover(true, typing: true, now: 13)
        assert(opening.pending == nil && opening.expanded)
        opening.hover(false, typing: false, now: 14)
        assert(opening.fire(opening.pending!, now: 14.4, linkOpen: true) == nil)
        assert(opening.expanded)
        opening.setExpanded(false, now: 15)
        opening.hover(true, typing: false, now: 15.2)
        assert(opening.pending == nil)
        opening.setExpanded(true, now: 15.3)
        assert(opening.expanded)
        opening.hover(false, typing: false, now: 16)
        let beforeSuspend = opening.pending!
        opening.suspend()
        assert(!opening.hovering)
        assert(opening.fire(beforeSuspend, now: 17, linkOpen: false) == nil)

        var state = NotchContentState(question: true, incoming: true, reply: true,
            dictation: true, typingNote: true, notification: true, hud: true,
            update: true, airpods: true, expanded: true, pomodoro: true, focus: .nota)
        assert(state.mode == .question && state.keyboard)
        state.question = false
        assert(state.mode == .message && state.keyboard)
        state.reply = false
        assert(!state.keyboard, "nota atrás de mensagem não pode habilitar teclado")
        state.incoming = false
        assert(state.mode == .dictation && !state.keyboard)
        state.dictation = false
        assert(state.mode == .music && state.keyboard)
        state.typingNote = false
        assert(state.mode == .notification && !state.keyboard)
        state.notification = false
        assert(state.mode == .hud && !state.keyboard)
        state.hud = false
        assert(state.mode == .update)
        state.update = false
        assert(state.mode == .airpods)
        state.airpods = false
        assert(state.mode == .music)
        state.expanded = false
        assert(state.mode == .pomodoro && !state.keyboard)
        state.pomodoro = false
        assert(state.mode == .closed)

        for real in [true, false] {
            var layout = NotchPresentation.Layout()
            layout.realNotch = real
            let inset: CGFloat = real ? 32 : 4
            let note = NotchContentState(expanded: true, focus: .nota)
            layout.sectionHeight = NotchMetrics.alturaDaSecao(.nota)
            let p = NotchPresentation(content: note, layout: layout)
            assert(p.size == CGSize(width: 430, height: inset + 148 + 60))
            assert(p.keyboard && p.interactionSize.width == 462)
            layout.sectionWidth = NotchMetrics.linkCardWidth
            let link = NotchPresentation(content: NotchContentState(expanded: true, focus: .link), layout: layout)
            assert(link.size.width == 780 && link.interactionSize.width == 812)
            layout.available = CGSize(width: 600, height: 200)
            let limited = NotchPresentation(content: note, layout: layout)
            assert(limited.size.width <= 536 && limited.size.height <= 176)
        }
        for screen in [CGRect(x: 0, y: 0, width: 1512, height: 982),
                       CGRect(x: -1920, y: 400, width: 1920, height: 1080)] {
            let host = NotchPresentation.hostFrame(screen: screen, visible: screen.insetBy(dx: 0, dy: 50))
            assert(host.maxY == screen.maxY && host.midX == screen.midX)
            assert(host.width >= 812 && host.minY == screen.minY + 50)
        }
        // Repetição determinística de interrupções e isolamento entre monitores.
        for i in 0..<1000 {
            var a = NotchOpening(), b = NotchOpening()
            let now = Double(i)
            a.hover(true, typing: false, now: now)
            let stale = a.pending!
            a.setExpanded(false, now: now + 0.05)
            b.setExpanded(true, now: now)
            assert(a.fire(stale, now: now + 1, linkOpen: false) == nil)
            assert(!a.expanded && b.expanded)
        }
        let editor = NotchContentState(editingAgenda: true, expanded: true, focus: .agenda)
        assert(editor.mode == .music && editor.keyboard)
        assert(!NotchContentState(expanded: true, focus: .agenda).keyboard)
        let remindersEditor = NotchContentState(editingReminders: true, notification: true,
            expanded: true, focus: .lembretesApple)
        assert(remindersEditor.mode == .music && remindersEditor.keyboard)
        assert(!NotchContentState(expanded: true, focus: .lembretesApple).keyboard)
        assert(NotchMetrics.alturaDaSecao(.lembretesApple) == 330)
        assert(NotchMetrics.alturaAgenda(editando: true, disponivel: 900, topo: 32) == 400)
        assert(NotchMetrics.alturaAgenda(editando: true, disponivel: 400, topo: 4) == 312)
        print("presentationcheck ok")
    }
}
