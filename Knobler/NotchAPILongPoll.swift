//
//  NotchAPILongPoll.swift
//  Knobler
//
//  Long-poll da API local. Quem espera a resposta de um card (hook do Claude,
//  `knobler ask`, ponte do Codex) mandava um GET a cada 0,3 s, e cada conexão
//  deixa umas 20 linhas do Network.framework no log do sistema. Com o header
//  `X-Knobler-Wait: <segundos>` o servidor segura o GET de estado até ele
//  ficar final ou o prazo vencer, e responde o mesmo JSON de sempre.
//
//  Header, e não query string: o app antigo ignora o header e responde na
//  hora, então cliente novo segue funcionando contra app velho.
//
//  Lógica pura (só Foundation): não conhece rede nem relógio. Testada isolada
//  em tools/longpollcheck.swift; o servidor de verdade, em
//  tools/agentrequest-api-server-check.swift.
//

import Foundation

enum NotchAPILongPoll {
    static let cabecalho = "x-knobler-wait"
    /// Teto do prazo pedido: abaixo do `curl -m` dos clientes, com folga.
    static let esperaMaxima: TimeInterval = 25

    /// Segundos que o cliente aceita esperar, já limitados a `esperaMaxima`.
    /// nil = header ausente ou inválido: responde na hora, como sempre.
    /// `headers`: tudo antes do "\r\n\r\n" (linha de requisição inclusa).
    static func segundos(cabecalhos headers: String) -> TimeInterval? {
        for linha in headers.components(separatedBy: "\r\n").dropFirst() {
            let partes = linha.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard partes.count == 2,
                  partes[0].trimmingCharacters(in: .whitespaces).lowercased() == cabecalho
            else { continue }
            guard let valor = Double(partes[1].trimmingCharacters(in: .whitespaces)),
                  valor.isFinite, valor > 0
            else { return nil }
            return min(valor, esperaMaxima)
        }
        return nil
    }

    /// Conexões seguradas, por chave (o id que elas esperam). Cada uma sai
    /// daqui uma vez só — pelo estado final, pelo prazo ou pela desconexão —
    /// e quem a tirou é quem responde. As outras saídas viram no-op.
    struct Esperas<Chave: Hashable, Conexao> {
        private struct Entrada {
            let token: UInt64
            let chave: Chave
            let conexao: Conexao
        }

        /// Acima disso o GET responde na hora: cliente com defeito não
        /// acumula socket aberto no app.
        let limite: Int
        private var entradas: [Entrada] = []
        private var ultimoToken: UInt64 = 0

        init(limite: Int = 64) {
            self.limite = limite
        }

        var quantidade: Int { entradas.count }

        func quantidade(onde filtro: (Chave) -> Bool) -> Int {
            entradas.filter { filtro($0.chave) }.count
        }

        func contem(_ token: UInt64) -> Bool {
            entradas.contains { $0.token == token }
        }

        /// Token da espera, ou nil se o teto foi atingido.
        mutating func registrar(_ chave: Chave, _ conexao: Conexao) -> UInt64? {
            guard entradas.count < limite else { return nil }
            ultimoToken &+= 1
            entradas.append(Entrada(token: ultimoToken, chave: chave, conexao: conexao))
            return ultimoToken
        }

        /// Estado final: tira todas as esperas da chave, na ordem de chegada.
        mutating func retirar(_ chave: Chave) -> [Conexao] {
            let saindo = entradas.filter { $0.chave == chave }
            entradas.removeAll { $0.chave == chave }
            return saindo.map(\.conexao)
        }

        /// Prazo vencido ou cliente desconectado: tira uma espera. nil quando
        /// ela já saiu por outro caminho.
        mutating func remover(_ token: UInt64) -> Conexao? {
            guard let indice = entradas.firstIndex(where: { $0.token == token }) else { return nil }
            return entradas.remove(at: indice).conexao
        }

        /// Listener desligado: ninguém mais é respondido.
        mutating func retirarTodas() -> [Conexao] {
            defer { entradas.removeAll() }
            return entradas.map(\.conexao)
        }
    }
}
