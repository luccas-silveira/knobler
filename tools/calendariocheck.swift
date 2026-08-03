// Gate do aviso de calendário — a string e o corte de urgência do CalendarAviso.
//
// xcrun swiftc -parse-as-library -swift-version 5 \
//   Knobler/CalendarAviso.swift tools/calendariocheck.swift \
//   -o /tmp/calendariocheck && /tmp/calendariocheck

import Foundation

@main
struct CalendarioCheck {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("calendariocheck: \(message)") }
    }

    static func quando(_ faltam: TimeInterval) -> String {
        CalendarAviso(titulo: "Reunião", faltam: faltam).quando
    }

    static func main() {
        // "agora" cobre o evento em curso (o countdown segura por 1 min)
        check(quando(-30) == "agora", "evento começado deve dizer agora")
        check(quando(0) == "agora", "faltando 0 deve dizer agora")
        check(quando(1) == "em 1 min", "1s arredonda pra cima")
        check(quando(60) == "em 1 min", "60s é 1 min")
        check(quando(61) == "em 2 min", "61s arredonda pra cima")
        check(quando(12 * 60) == "em 12 min", "12 min")
        check(quando(15 * 60) == "em 15 min", "topo da janela do countdown")

        // fronteira dos 5 min: a pílula fechada troca o timer pelo evento
        check(CalendarAviso(titulo: "x", faltam: 5 * 60).urgente, "300s é urgente")
        check(!CalendarAviso(titulo: "x", faltam: 5 * 60 + 1).urgente, "301s não é urgente")
        check(CalendarAviso(titulo: "x", faltam: -30).urgente, "evento em curso é urgente")

        print("calendariocheck: OK")
    }
}
