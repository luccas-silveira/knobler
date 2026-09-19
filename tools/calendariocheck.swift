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

        testAgenda()
        testRascunho()
        print("calendariocheck: OK")
    }
    static func testAgenda() {
        var calendario = Calendar(identifier: .gregorian)
        calendario.timeZone = TimeZone(identifier: "America/New_York")!
        let dia = calendario.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let amanha = calendario.date(byAdding: .day, value: 1, to: dia)!
        assert(amanha.timeIntervalSince(dia) == 23 * 3600)
        func evento(_ id: String, _ inicio: Date, _ fim: Date,
                    inteiro: Bool = false) -> CalendarEvento {
            CalendarEvento(id: id, titulo: id, calendario: "Teste", inicio: inicio,
                           fim: fim, diaInteiro: inteiro)
        }
        let atravessa = evento("atravessa", dia.addingTimeInterval(-3600), dia.addingTimeInterval(3600))
        let termina = evento("termina", dia.addingTimeInterval(-3600), dia)
        let depois = evento("depois", amanha, amanha.addingTimeInterval(3600))
        let inteiro = evento("inteiro", dia, amanha, inteiro: true)
        let pontual = evento("pontual", dia, dia)
        let pontualAmanha = evento("pontual-amanha", amanha, amanha)
        let a = evento("a", dia.addingTimeInterval(4000), dia.addingTimeInterval(5000))
        let b = evento("b", a.inicio, a.fim)
        let ordenados = CalendarAgenda.eventosDoDia([b, depois, termina, pontualAmanha,
            a, pontual, atravessa, inteiro], dia: dia, calendario: calendario)
        assert(ordenados.map(\.id) == ["inteiro", "atravessa", "pontual", "a", "b"])
        assert(atravessa.emAndamento(em: dia))
        assert(!atravessa.emAndamento(em: atravessa.fim))
        assert(!inteiro.emAndamento(em: dia))
        assert(!a.emAndamento(em: dia))
        assert(CalendarAgenda.eventosDoDia([], dia: dia).isEmpty)
        let outono = calendario.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let fimOutono = calendario.date(byAdding: .day, value: 1, to: outono)!
        assert(fimOutono.timeIntervalSince(outono) == 25 * 3600)
        let tarde = evento("tarde", fimOutono.addingTimeInterval(-60), fimOutono)
        assert(CalendarAgenda.eventosDoDia([tarde], dia: outono, calendario: calendario) == [tarde])
    }

    static func testRascunho() {
        var calendario = Calendar(identifier: .gregorian)
        calendario.timeZone = TimeZone(identifier: "America/New_York")!
        let dia = calendario.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let agora = calendario.date(bySettingHour: 9, minute: 7, second: 32, of: dia)!
        var r = CalendarRascunho.novo(no: dia, agora: agora, calendario: calendario)
        assert(calendario.component(.minute, from: r.inicio) == 15)
        assert(calendario.component(.second, from: r.inicio) == 0)
        assert(r.fim.timeIntervalSince(r.inicio) == 3600)
        let ontem = calendario.date(byAdding: .day, value: -1, to: dia)!
        let passado = CalendarRascunho.novo(no: ontem, agora: agora, calendario: calendario)
        assert(calendario.component(.hour, from: passado.inicio) == 9)
        let destino = CalendarDestino(id: "teste", nome: "Teste", conta: "Local", padrao: true)
        r.calendarioID = destino.id
        func erro(_ esperado: CalendarErro, autorizado: Bool = true, destinos: [CalendarDestino]? = nil) {
            do { try r.validar(autorizado: autorizado, destinos: destinos ?? [destino]); assertionFailure("Deveria falhar") }
            catch { assert(error as? CalendarErro == esperado) }
        }
        erro(.titulo)
        r.titulo = "   "
        erro(.titulo)
        r.titulo = "Teste"
        erro(.permissao, autorizado: false)
        erro(.calendario, destinos: [])
        r.link = "javascript:alert(1)"
        erro(.link)
        r.link = "https://"
        erro(.link)
        r.link = "https://site.test/com espaço"
        erro(.link)
        r.link = " https://meet.google.com/teste "
        assert(r.url?.host == "meet.google.com")
        try! r.validar(autorizado: true, destinos: [destino])
        r.fim = r.inicio
        erro(.datas)
        r.diaInteiro = true
        r.inicio = dia
        r.fim = dia
        assert(try! r.intervalo(calendario: calendario).duration == 23 * 3600)
        r.fim = ontem
        do { _ = try r.intervalo(calendario: calendario); assertionFailure("Fim anterior") }
        catch { assert(error as? CalendarErro == .datas) }
        let outono = calendario.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        r.inicio = outono
        r.fim = outono
        assert(try! r.intervalo(calendario: calendario).duration == 25 * 3600)
        r.fim = calendario.date(byAdding: .day, value: 1, to: outono)!
        assert(try! r.intervalo(calendario: calendario).duration == 49 * 3600)
    }

}
