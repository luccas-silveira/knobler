//
//  tools/longpollcheck.swift — self-check da lógica pura do long-poll da API
//  local (header X-Knobler-Wait e registro de conexões seguradas). NÃO faz
//  parte do alvo do app. O servidor de verdade segurando conexão é provado em
//  tools/agentrequest-api-server-check.swift.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/NotchAPILongPoll.swift tools/longpollcheck.swift \
//    -o /tmp/longpollcheck && /tmp/longpollcheck
//

import Foundation

@main
struct LongPollCheck {
    static func main() {
        cabecalho()
        registro()
        prazoEDesconexao()
        teto()
        print("✅ longpollcheck ok")
    }

    /// Header ausente ou inválido = cliente antigo: responde na hora.
    static func cabecalho() {
        func segundos(_ linhas: String...) -> TimeInterval? {
            NotchAPILongPoll.segundos(cabecalhos: (["GET /ask/x HTTP/1.1", "Host: 127.0.0.1:4477"] + linhas)
                .joined(separator: "\r\n"))
        }
        confere(segundos() == nil, "sem header responde na hora")
        confere(segundos("X-Knobler-Wait: 25") == 25, "25 s")
        confere(segundos("X-Knobler-Wait: 7") == 7, "prazo menor que o teto vale como veio")
        confere(segundos("X-Knobler-Wait: 2.5") == 2.5, "fração de segundo")
        confere(segundos("X-Knobler-Wait: 600") == NotchAPILongPoll.esperaMaxima, "teto de 25 s")
        confere(segundos("x-knobler-wait:3") == 3, "nome sem diferenciar caixa e sem espaço")
        confere(segundos("X-KNOBLER-WAIT:   4  ") == 4, "espaços em volta do valor")
        confere(segundos("X-Knobler-Wait: 0") == nil, "zero = sem espera")
        confere(segundos("X-Knobler-Wait: -3") == nil, "negativo = sem espera")
        confere(segundos("X-Knobler-Wait: abc") == nil, "lixo = sem espera")
        confere(segundos("X-Knobler-Wait: nan") == nil, "NaN = sem espera")
        confere(segundos("X-Knobler-Wait: inf") == nil, "infinito = sem espera")
        confere(segundos("X-Knobler-Wait-Extra: 5") == nil, "outro header com o mesmo prefixo")
        confere(NotchAPILongPoll.segundos(cabecalhos: "GET /x-knobler-wait:5 HTTP/1.1") == nil,
                "linha de requisição não conta como header")
    }

    /// Estado final acorda só quem espera aquele id, na ordem de chegada.
    static func registro() {
        var esperas = NotchAPILongPoll.Esperas<String, String>()
        let a1 = esperas.registrar("a", "conexão a1")
        let b1 = esperas.registrar("b", "conexão b1")
        let a2 = esperas.registrar("a", "conexão a2")
        confere(a1 != nil && b1 != nil && a2 != nil, "registra abaixo do teto")
        confere(Set([a1, b1, a2]).count == 3, "token único por conexão")
        confere(esperas.quantidade == 3, "três seguradas")
        confere(esperas.quantidade { $0 == "a" } == 2, "contagem por chave")

        confere(esperas.retirar("a") == ["conexão a1", "conexão a2"], "flush do id, na ordem de chegada")
        confere(esperas.retirar("a").isEmpty, "segundo flush do mesmo id é vazio")
        confere(esperas.quantidade == 1 && esperas.contem(b1!), "o outro id continua esperando")
        confere(!esperas.contem(a1!), "quem saiu pelo flush não está mais lá")
        confere(esperas.retirar("desconhecido").isEmpty, "flush de id sem espera é no-op")
    }

    /// Prazo e desconexão tiram uma conexão só, e uma vez só: quem chegar
    /// depois (flush, prazo ou desconexão) não responde de novo.
    static func prazoEDesconexao() {
        var esperas = NotchAPILongPoll.Esperas<String, String>()
        let prazo = esperas.registrar("x", "prazo")!
        let desconecta = esperas.registrar("x", "desconecta")!

        confere(esperas.remover(prazo) == "prazo", "prazo vencido tira a conexão")
        confere(esperas.remover(prazo) == nil, "segunda saída da mesma conexão é no-op")
        confere(esperas.remover(desconecta) == "desconecta", "desconexão tira a conexão")
        confere(esperas.retirar("x").isEmpty, "flush depois do prazo e da desconexão não acha ninguém")

        let flush = esperas.registrar("y", "flush")!
        confere(esperas.retirar("y") == ["flush"], "flush primeiro")
        confere(esperas.remover(flush) == nil, "prazo depois do flush é no-op")

        _ = esperas.registrar("z", "um")
        _ = esperas.registrar("w", "dois")
        confere(Set(esperas.retirarTodas()) == ["um", "dois"], "desligar a API solta todas")
        confere(esperas.quantidade == 0, "e não sobra nenhuma")
    }

    /// Acima do teto a requisição volta pro polling de sempre.
    static func teto() {
        var esperas = NotchAPILongPoll.Esperas<String, Int>(limite: 2)
        let primeira = esperas.registrar("a", 1)
        _ = esperas.registrar("b", 2)
        confere(esperas.registrar("c", 3) == nil, "teto atingido recusa")
        _ = esperas.remover(primeira!)
        confere(esperas.registrar("c", 3) != nil, "vaga liberada aceita de novo")
    }

    static func confere(_ condicao: Bool, _ caso: String) {
        precondition(condicao, "longpollcheck: \(caso)")
    }
}
