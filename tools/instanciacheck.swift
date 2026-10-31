//
//  tools/instanciacheck.swift — self-check da regra "a instância mais nova
//  vence" (Knobler/InstanciaUnica.swift). NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/InstanciaUnica.swift tools/instanciacheck.swift \
//    -o /tmp/instanciacheck && /tmp/instanciacheck
//

import Foundation

@main
struct InstanciaCheck {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func vista(_ pid: pid_t, _ segundos: Double?, encerrada: Bool = false) -> InstanciaVista {
        InstanciaVista(pid: pid, inicio: segundos.map { t0.addingTimeInterval($0) }, encerrada: encerrada)
    }

    static func main() {
        let eu = vista(500, 10)

        // sozinha (a lista do sistema inclui o próprio processo depois do check-in)
        espera(eu, [], .seguir, "lista vazia")
        espera(eu, [eu], .seguir, "só eu na lista")
        espera(eu, [eu, eu], .seguir, "eu repetida")

        // a evidência: app aberto e um segundo lançamento (binário direto, open -n,
        // build do DerivedData) — o segundo derruba o primeiro
        espera(eu, [vista(300, 1), eu], .encerrar([300]), "uma antiga")
        espera(eu, [vista(400, 5), vista(300, 1)], .encerrar([300, 400]), "duas antigas, ordenadas por pid")
        espera(eu, [vista(300, 1), vista(300, 1)], .encerrar([300]), "pid repetido conta uma vez")

        // dois lançamentos quase simultâneos: a mais antiga sai sem montar nada
        espera(eu, [vista(600, 11)], .sair(maisNova: 600), "uma mais nova")
        espera(eu, [vista(300, 1), vista(600, 11)], .sair(maisNova: 600),
               "antiga e mais nova: quem sai sou eu, a mais nova cuida da antiga")
        espera(eu, [vista(600, 11), vista(700, 12)], .sair(maisNova: 700), "aponta a mais nova de todas")

        // já saindo/saída (Updater.relaunch espera o PID morrer; a lista pode atrasar)
        espera(eu, [vista(300, 1, encerrada: true)], .seguir, "antiga já encerrada")
        espera(eu, [vista(600, 11, encerrada: true)], .seguir, "mais nova já encerrada não me tira")
        espera(eu, [vista(300, 1, encerrada: true), vista(400, 2)], .encerrar([400]), "só a viva entra")

        // desempate: início igual ou ilegível cai no pid
        espera(eu, [vista(400, 10)], .encerrar([400]), "mesmo início, pid menor = antiga")
        espera(eu, [vista(600, 10)], .sair(maisNova: 600), "mesmo início, pid maior = nova")
        espera(eu, [vista(400, nil)], .encerrar([400]), "início ilegível, pid menor")
        espera(eu, [vista(600, nil)], .sair(maisNova: 600), "início ilegível, pid maior")
        espera(vista(500, nil), [vista(600, 1)], .sair(maisNova: 600), "meu início ilegível: pid decide")
        // o início manda quando os dois existem, mesmo com o pid do outro lado
        // (contador de pid que deu a volta)
        espera(eu, [vista(100, 11)], .sair(maisNova: 100), "pid menor mas nasceu depois")
        espera(eu, [vista(900, 1)], .encerrar([900]), "pid maior mas nasceu antes")

        // simetria: dois processos olhando um pro outro chegam a ações complementares
        // — nunca os dois saem, nunca os dois sobem
        let pares: [(InstanciaVista, InstanciaVista)] = [
            (vista(500, 10), vista(600, 11)), (vista(500, 10), vista(600, 10)),
            (vista(500, nil), vista(600, 11)), (vista(500, nil), vista(600, nil)),
            (vista(100, 11), vista(900, 1)),
        ]
        for (a, b) in pares {
            let deA = InstanciaUnica.decidir(eu: a, outras: [a, b])
            let deB = InstanciaUnica.decidir(eu: b, outras: [a, b])
            let complementares = (deA == .sair(maisNova: b.pid) && deB == .encerrar([a.pid]))
                || (deB == .sair(maisNova: a.pid) && deA == .encerrar([b.pid]))
            precondition(complementares, "par \(a.pid)/\(b.pid): \(deA) × \(deB)")
            precondition(InstanciaUnica.ehMaisNova(a, que: b) != InstanciaUnica.ehMaisNova(b, que: a),
                         "ordem não é antissimétrica no par \(a.pid)/\(b.pid)")
        }

        print("✅ instanciacheck ok")
    }

    static func espera(_ eu: InstanciaVista, _ outras: [InstanciaVista],
                       _ acao: InstanciaUnica.Acao, _ caso: String) {
        let obtida = InstanciaUnica.decidir(eu: eu, outras: outras)
        precondition(obtida == acao, "\(caso): esperava \(acao), veio \(obtida)")
    }
}
