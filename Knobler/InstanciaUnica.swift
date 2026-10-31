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
//  Função pura (só Foundation) pra ser testada isolada:
//  tools/instanciacheck.swift. Os efeitos (listar, pedir o quit, esperar,
//  forçar) moram em InstanciaUnicaPartida.swift.
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
    /// depois do check-in) e PIDs repetidos: os dois são ignorados.
    static func decidir(eu: InstanciaVista, outras: [InstanciaVista]) -> Acao {
        var vistos: Set<pid_t> = [eu.pid]
        let vivas = outras.filter { !$0.encerrada && vistos.insert($0.pid).inserted }
        let maisNovas = vivas.filter { ehMaisNova($0, que: eu) }
        if let maisNova = maisNovas.max(by: { ehMaisNova($1, que: $0) }) {
            return .sair(maisNova: maisNova.pid)
        }
        return vivas.isEmpty ? .seguir : .encerrar(vivas.map(\.pid).sorted())
    }
}
