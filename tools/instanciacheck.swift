//
//  tools/instanciacheck.swift — self-check da regra "a instância mais nova
//  vence" (Knobler/InstanciaUnica.swift): a decisão, o PID ≤ 0 e o
//  reconhecimento dos modos headless pelo argv. NÃO faz parte do alvo do app.
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

        // PID ≤ 0 não é processo (o LaunchServices devolve -1 pra app sem PID):
        // nunca vira alvo — `kill(-1, SIGKILL)` mataria todo processo do usuário
        espera(eu, [vista(-1, nil)], .seguir, "pid -1 vivo e sem data")
        espera(eu, [vista(-1, 99)], .seguir, "pid -1 'mais novo' não me tira")
        espera(eu, [vista(0, 1)], .seguir, "pid 0")
        espera(eu, [vista(-1, nil), vista(0, nil), vista(300, 1)], .encerrar([300]),
               "pid ≤ 0 some, a antiga de verdade fica")
        precondition(!InstanciaUnica.estaVivo(-1) && !InstanciaUnica.estaVivo(0),
                     "estaVivo(-1/0) deu true: kill(-1/0, 0) fala de grupos, não de um processo")
        precondition(InstanciaUnica.estaVivo(getpid()), "estaVivo(eu) deu false")

        verificaHeadless()
        print("✅ instanciacheck ok")
    }

    /// Modos headless (--selfcheck, --download-model, --permissoes) fazem
    /// check-in no LaunchServices quando tocam o AppKit: a guarda os reconhece
    /// pelo argv que o kernel guarda, e não pela lista de apps.
    static func verificaHeadless() {
        precondition(InstanciaUnica.flagsHeadless == ["--download-model", "--selfcheck", "--permissoes"],
                     "a lista de modos headless mudou: o KnoblerMain.main() trata as mesmas flags")
        precondition(InstanciaUnica.ehHeadless(argv: ["/A/Knobler", "--selfcheck"]), "--selfcheck")
        precondition(InstanciaUnica.ehHeadless(argv: ["/A/Knobler", "-x", "--download-model"]), "--download-model")
        precondition(InstanciaUnica.ehHeadless(argv: ["/A/Knobler", "--permissoes"]), "--permissoes")
        precondition(!InstanciaUnica.ehHeadless(argv: ["/A/Knobler"]), "sem flag")
        precondition(!InstanciaUnica.ehHeadless(argv: ["/A/Knobler", "--ajustes=geral"]),
                     "--ajustes sobe o app inteiro: não é headless")
        precondition(!InstanciaUnica.ehHeadless(argv: ["--selfcheck"]), "o executável não conta")

        // o formato do KERN_PROCARGS2: argc, caminho, enchimento, argv, ambiente
        func buffer(_ argc: Int32, _ partes: [String], enchimento: Int = 3) -> [UInt8] {
            var b = withUnsafeBytes(of: argc) { Array($0) }
            b += Array("/caminho/Knobler".utf8) + [UInt8](repeating: 0, count: enchimento)
            for p in partes { b += Array(p.utf8) + [0] }
            return b
        }
        precondition(InstanciaUnica.argv(deProcargs2: buffer(2, ["Knobler", "--selfcheck", "HOME=/x"]))
                     == ["Knobler", "--selfcheck"], "argv com ambiente depois")
        precondition(InstanciaUnica.argv(deProcargs2: buffer(1, ["Knobler"], enchimento: 1)) == ["Knobler"],
                     "um NUL de enchimento")
        precondition(InstanciaUnica.argv(deProcargs2: buffer(3, ["a", "b"])) == nil, "argc maior que o buffer")
        precondition(InstanciaUnica.argv(deProcargs2: [1, 0]) == nil, "buffer menor que o argc")

        // de verdade: o argv do próprio processo e o de um filho com a flag
        precondition(InstanciaUnica.argv(de: getpid()) == CommandLine.arguments,
                     "argv do kernel ≠ CommandLine.arguments: \(InstanciaUnica.argv(de: getpid()) ?? [])")
        precondition(InstanciaUnica.argv(de: -1) == nil && InstanciaUnica.argv(de: 0) == nil, "argv de pid ≤ 0")
        precondition(!InstanciaUnica.ehModoHeadless(getpid()), "este harness não é headless")
        let filho = Process()
        filho.executableURL = URL(fileURLWithPath: "/bin/sh")
        // `sh -c <cmd> <arg0>`: a flag fica no argv do filho e o sh a ignora
        filho.arguments = ["-c", "sleep 5", "--selfcheck"]
        try! filho.run()
        defer { filho.terminate() }
        var visto = false
        for _ in 0..<40 where !visto {
            visto = InstanciaUnica.ehModoHeadless(filho.processIdentifier)
            if !visto { usleep(50_000) }
        }
        precondition(visto, "o filho com --selfcheck não foi visto como headless: "
                     + "\(InstanciaUnica.argv(de: filho.processIdentifier) ?? [])")
    }

    static func espera(_ eu: InstanciaVista, _ outras: [InstanciaVista],
                       _ acao: InstanciaUnica.Acao, _ caso: String) {
        let obtida = InstanciaUnica.decidir(eu: eu, outras: outras)
        precondition(obtida == acao, "\(caso): esperava \(acao), veio \(obtida)")
    }
}
