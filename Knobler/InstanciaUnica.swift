//
//  InstanciaUnica.swift
//  Knobler
//
//  Uma instância por sessão de usuário, e a MAIS NOVA vence. Duas instâncias
//  vivas brigam por tudo que é único na máquina: a porta 4477, o token de
//  solicitações de agente (a segunda regravava o arquivo e a primeira passava a
//  responder 401 a toda aprovação), o tap de teclado, o escurecimento dos
//  monitores e as janelas do notch.
//
//  Por que a mais nova: quem abre o app de novo (`open -n`, binário executado
//  direto, build do DerivedData ao lado da cópia em /Applications) quer ESSA
//  cópia rodando — é o build que acabou de compilar ou o app que acabou de
//  instalar. A antiga recebe o quit normal e, se não sair, é derrubada.
//
//  Só Foundation, pra ser testada isolada (tools/instanciacheck.swift): a
//  decisão pura e a leitura do argv de outro processo no kernel. Os efeitos
//  (listar, pedir o quit, esperar, forçar) moram em InstanciaUnicaPartida.swift.
//

import Foundation

/// Uma instância do app vista na partida, reduzida ao que a decisão usa.
struct InstanciaVista: Equatable {
    let pid: pid_t
    /// Início do processo. Vem do kernel (vale até pra binário executado sem o
    /// LaunchServices, que fica sem `launchDate`); `nil` = não deu pra ler, e aí
    /// o desempate é só o PID.
    let inicio: Date?
    /// Já saiu ou está saindo: o LaunchServices a deu como encerrada, ou o
    /// processo nem existe mais. Não conta pra nada.
    let encerrada: Bool
}

enum InstanciaUnica {
    enum Acao: Equatable {
        /// Ninguém mais vivo: a partida segue.
        case seguir
        /// Só há instâncias mais antigas: pedir que saiam e, depois, seguir.
        case encerrar([pid_t])
        /// Existe uma instância mais nova subindo junto (dois lançamentos quase
        /// simultâneos): esta sai sem montar nada. A outra a derruba, se precisar.
        case sair(maisNova: pid_t)
    }

    /// `a` nasceu depois de `b`? Ordem total e igual vista dos dois lados — cada
    /// instância lê o mesmo início do kernel pras duas —, então nunca as duas
    /// se acham a mais nova (ninguém sobe) nem as duas se acham a mais antiga
    /// (as duas sobem).
    /// ponytail: PID como desempate assume que o contador não deu a volta entre
    /// os dois lançamentos; só entra com início igual ou ilegível.
    static func ehMaisNova(_ a: InstanciaVista, que b: InstanciaVista) -> Bool {
        if let ia = a.inicio, let ib = b.inicio, ia != ib { return ia > ib }
        return a.pid > b.pid
    }

    /// O que esta instância (`eu`) faz diante das `outras` com o mesmo bundle id.
    /// `outras` pode conter `eu` (a lista do sistema inclui o próprio processo
    /// depois do check-in) e PIDs repetidos: os dois são ignorados. PID ≤ 0 não
    /// é processo (o LaunchServices devolve -1 pra app sem PID): nunca vira
    /// alvo — `kill(-1, …)` atinge TODOS os processos do usuário.
    static func decidir(eu: InstanciaVista, outras: [InstanciaVista]) -> Acao {
        var vistos: Set<pid_t> = [eu.pid]
        let vivas = outras.filter { $0.pid > 0 && !$0.encerrada && vistos.insert($0.pid).inserted }
        let maisNovas = vivas.filter { ehMaisNova($0, que: eu) }
        if let maisNova = maisNovas.max(by: { ehMaisNova($1, que: $0) }) {
            return .sair(maisNova: maisNova.pid)
        }
        return vivas.isEmpty ? .seguir : .encerrar(vivas.map(\.pid).sorted())
    }

    // MARK: - Modos headless

    /// Os modos de linha de comando: `--download-model` (postflight do cask),
    /// `--selfcheck` (tools/check.sh) e `--permissoes` (suporte). O
    /// `KnoblerMain` os trata antes da guarda, e eles convivem com o app
    /// aberto. Mas não são invisíveis: tocar `NSScreen.screens` ou criar um
    /// `NSPanel` (o `--selfcheck` faz os dois) já faz check-in no
    /// LaunchServices, e o processo entra na lista do bundle id. A guarda os
    /// tira da lista pelo argv — nem os derruba, nem sai por causa deles.
    static let flagsHeadless: Set<String> = ["--download-model", "--selfcheck", "--permissoes"]

    /// O processo com este argv é um modo headless? O primeiro item é o
    /// executável e não conta.
    static func ehHeadless(argv: [String]) -> Bool {
        argv.dropFirst().contains(where: flagsHeadless.contains)
    }

    /// Lê o buffer do `sysctl(KERN_PROCARGS2)`: `argc` (Int32), o caminho do
    /// executável, NULs de enchimento e então as `argc` strings do argv, cada
    /// uma terminada em NUL (o ambiente vem depois e é ignorado). `nil` =
    /// buffer que não segue esse formato.
    static func argv(deProcargs2 dados: [UInt8]) -> [String]? {
        let tamanhoDoArgc = MemoryLayout<Int32>.size
        guard dados.count >= tamanhoDoArgc else { return nil }
        let argc = dados.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc >= 0 else { return nil }
        var i = tamanhoDoArgc
        while i < dados.count, dados[i] != 0 { i += 1 }  // caminho do executável
        while i < dados.count, dados[i] == 0 { i += 1 }  // enchimento
        var argv: [String] = []
        while argv.count < argc {
            guard i < dados.count else { return nil }
            let inicio = i
            while i < dados.count, dados[i] != 0 { i += 1 }
            guard i < dados.count else { return nil }      // string sem NUL: truncado
            argv.append(String(decoding: dados[inicio..<i], as: UTF8.self))
            i += 1
        }
        return argv
    }

    /// O processo existe? `EPERM` = existe, mas é de outro usuário. PID ≤ 0
    /// não é um processo: `kill(-1, 0)` e `kill(0, 0)` falam de grupos e
    /// devolvem 0, e a espera nunca acabaria.
    static func estaVivo(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// O processo foi lançado num modo headless? Lê o argv dele no kernel.
    /// Argv ilegível (processo de outro usuário, já morto) = não é headless:
    /// na dúvida, ele conta como instância.
    static func ehModoHeadless(_ pid: pid_t) -> Bool {
        argv(de: pid).map(ehHeadless(argv:)) ?? false
    }

    /// O argv de outro processo, via `sysctl(KERN_PROCARGS2)`.
    static func argv(de pid: pid_t) -> [String]? {
        guard pid > 0 else { return nil }
        var maximo: Int32 = 0
        var tamanhoDoMaximo = MemoryLayout<Int32>.size
        var mibMax: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mibMax, 2, &maximo, &tamanhoDoMaximo, nil, 0) == 0, maximo > 0 else { return nil }
        var dados = [UInt8](repeating: 0, count: Int(maximo))
        var tamanho = dados.count
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &dados, &tamanho, nil, 0) == 0 else { return nil }
        return argv(deProcargs2: Array(dados.prefix(tamanho)))
    }
}
