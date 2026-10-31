// Self-check do NotchAPIServer de verdade, numa porta alternativa (nunca a
// 4477): contrato autenticado de /agent-requests e o long-poll
// (X-Knobler-Wait) de GET /ask/<id> e GET /agent-requests/<id>.
// O launcher tools/agentrequest-api-check.swift compila este arquivo; o
// tools/check.sh compila direto:
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/AgentRequestModels.swift Knobler/AskModels.swift \
//     Knobler/NotchAPIServer.swift Knobler/NotchAPIGuard.swift \
//     Knobler/NotchAPILongPoll.swift tools/agentrequest-api-server-check.swift \
//     -o /tmp/apiservercheck && /tmp/apiservercheck

import Foundation
import Network

struct NotchNotification {
    let appName: String?
    let title: String
    let body: String
    var supacodeWorktree: String?
    var supacodeTab: String?
}
struct NotchActivity {
    var id: String
    var title: String
    var detail: String
    var progress: Double?
    var updatedAt: Date
}
// /mirror é rota de peça; o harness não precisa do sistema de plugins inteiro.
enum PluginID { case espelho }
final class PluginHost {
    static let shared = PluginHost()
    func estaInstalado(_ id: PluginID) -> Bool { false }
}

@main
struct AgentRequestAPIServerCheck {
    static let token = "agent-request-check-token"
    static let port: UInt16 = 44877

    static func main() {
        let server = NotchAPIServer(agentRequestToken: token, port: port)
        server.start()
        defer { server.stop() }

        let valid = #"{"id":"check-1","agent":"claude","kind":"permission","title":"Read","summary":"README.md","source":"terminal","actions":[{"action":"allow"},{"action":"deny"}]}"#
        check(rawRequest("POST /agent-requests HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: -1\r\n\r\n") == 400, "negative Content-Length")
        let create = request("POST", "/agent-requests", body: valid, token: token)
        check(create.status == 200, "valid create")
        check(request("POST", "/agent-requests", body: "{", token: token).status == 400, "duplicate still validates JSON")
        check(request("POST", "/agent-requests", body: valid, token: token).status == 409, "duplicate publish conflicts")
        check(request("GET", "/agent-requests/check-1").status == 401, "missing token")
        check(request("GET", "/agent-requests/check-1", token: token.uppercased()).status == 401, "token casing is exact")
        check(request("GET", "/agent-requests/check-1", token: token + "-suffix").status == 401, "token suffix is rejected")
        check(rawRequest("GET /agent-requests/check-1 HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: bEaReR \(token)\r\n\r\n") == 200, "bearer scheme is case-insensitive")
        check(request("GET", "/agent-requests/check-1", token: token).status == 200, "valid token")
        check(request("POST", "/agent-requests/check-1/resolve", body: #"{"action":"allow"}"#, token: token).status == 200, "resolve")
        let firstRead = request("GET", "/agent-requests/check-1", token: token)
        check(firstRead.status == 200 && firstRead.body.contains(#""state":"resolved""#), "read-once result")
        check(request("GET", "/agent-requests/check-1", token: token).status == 404, "consumed result")
        check(request("POST", "/agent-requests", body: "{", token: token).status == 400, "malformed JSON")
        check(request("POST", "/agent-requests", body: String(repeating: "x", count: 32 * 1024 + 1), token: token).status == 413, "oversized body")

        longPollAsk(server)
        longPollAgentRequest(server)
        longPollStop(server) // por último: desliga o listener
        print("agentrequest-api-check: OK")
    }

    // MARK: - Long-poll

    static func longPollAsk(_ server: NotchAPIServer) {
        publishAsk("lp-ask-1")
        let semEspera = request("GET", "/ask/lp-ask-1")
        check(semEspera.body == #"{"answered":false}"# && semEspera.elapsed < 1, "ask: sem header responde na hora")

        let prazo = request("GET", "/ask/lp-ask-1", wait: "1")
        check(prazo.status == 200 && prazo.body == #"{"answered":false}"#, "ask: prazo vencido devolve pendente")
        check(prazo.elapsed >= 0.9 && prazo.elapsed < 2.5, "ask: segurou ~1 s (foram \(prazo.elapsed))")
        check(waiting(server.askDiagnostics) == 0, "ask: prazo libera a vaga")

        // card respondido no notch acorda quem espera
        let respondida = start("GET", "/ask/lp-ask-1", wait: "10")
        spin(0.3)
        check(waiting(server.askDiagnostics) == 1, "ask: conexão segurada")
        server.resolveAsk(id: "lp-ask-1", answers: ["Q?": AskAnswer(labels: ["Sim"], text: nil)])
        let resposta = finish(respondida, timeout: 3)
        check(resposta.status == 200 && resposta.body.contains(#""answered":true"#) && resposta.body.contains("Sim"),
              "ask: resposta chega pelo long-poll (\(resposta.body))")
        check(resposta.elapsed < 2, "ask: resposta não espera o prazo (foram \(resposta.elapsed))")
        check(waiting(server.askDiagnostics) == 0, "ask: flush libera a vaga")
        check(request("GET", "/ask/lp-ask-1").status == 404, "ask: leitura única vale no long-poll")

        // cancelamento por HTTP (timeout de outro hook, ✕) também acorda
        publishAsk("lp-ask-2")
        let cancelada = start("GET", "/ask/lp-ask-2", wait: "10")
        spin(0.3)
        check(request("POST", "/ask/lp-ask-2/cancel").status == 200, "ask: cancel")
        let cancelamento = finish(cancelada, timeout: 3)
        check(cancelamento.body == #"{"cancelled":true}"# && cancelamento.elapsed < 2, "ask: cancel acorda a espera")

        // já final: responde na hora mesmo pedindo espera
        publishAsk("lp-ask-3")
        _ = server.cancelAsk(id: "lp-ask-3")
        let final = request("GET", "/ask/lp-ask-3", wait: "10")
        check(final.body == #"{"cancelled":true}"# && final.elapsed < 1, "ask: estado final não segura")
        let desconhecida = request("GET", "/ask/nao-existe", wait: "10")
        check(desconhecida.status == 404 && desconhecida.elapsed < 1, "ask: id desconhecido não segura")

        // guard antes de segurar: Host de outro domínio é 403 na hora
        publishAsk("lp-ask-4")
        let inicio = Date()
        check(rawRequest("GET /ask/lp-ask-4 HTTP/1.1\r\nHost: evil.com\r\nX-Knobler-Wait: 10\r\n\r\n") == 403
              && Date().timeIntervalSince(inicio) < 1, "ask: guard recusa antes de segurar")

        // cliente que desiste (Ctrl-C) libera a vaga sem consumir a resposta
        publishAsk("lp-ask-5")
        let cliente = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        cliente.start(queue: .global())
        cliente.send(content: Data("GET /ask/lp-ask-5 HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Knobler-Wait: 10\r\n\r\n".utf8),
                     completion: .contentProcessed { _ in })
        spin(0.3)
        check(waiting(server.askDiagnostics) == 1, "ask: conexão crua segurada")
        cliente.cancel()
        spin(until: 2) { waiting(server.askDiagnostics) == 0 }
        check(waiting(server.askDiagnostics) == 0, "ask: desconexão libera a vaga")
        check(request("GET", "/ask/lp-ask-5").body == #"{"answered":false}"#, "ask: desconexão não mexe no estado")

        // TTL: a pergunta some e quem espera lê 404, como no polling
        let orfa = start("GET", "/ask/lp-ask-5", wait: "10")
        spin(0.3)
        server.pruneExpired(agora: Date().addingTimeInterval(16 * 60))
        let expirada = finish(orfa, timeout: 3)
        check(expirada.status == 404 && expirada.elapsed < 2, "ask: TTL acorda com 404")
    }

    static func longPollAgentRequest(_ server: NotchAPIServer) {
        publishAgent("lp-agent-1")
        let semEspera = request("GET", "/agent-requests/lp-agent-1", token: token)
        check(semEspera.body.contains(#""state":"pending""#) && semEspera.elapsed < 1, "agente: sem header responde na hora")

        // Bearer vale antes de segurar
        let anonimo = request("GET", "/agent-requests/lp-agent-1", wait: "10")
        check(anonimo.status == 401 && anonimo.elapsed < 1, "agente: sem token é 401 na hora")
        let errado = request("GET", "/agent-requests/lp-agent-1", token: "errado", wait: "10")
        check(errado.status == 401 && errado.elapsed < 1, "agente: token errado é 401 na hora")

        let prazo = request("GET", "/agent-requests/lp-agent-1", token: token, wait: "1")
        check(prazo.body.contains(#""state":"pending""#), "agente: prazo vencido devolve pendente")
        check(prazo.elapsed >= 0.9 && prazo.elapsed < 2.5, "agente: segurou ~1 s (foram \(prazo.elapsed))")

        // resolve pelo terminal (HTTP) acorda quem espera
        let resolvida = start("GET", "/agent-requests/lp-agent-1", token: token, wait: "10")
        spin(0.3)
        check(waiting(server.agentRequestDiagnostics) == 1, "agente: conexão segurada")
        check(request("POST", "/agent-requests/lp-agent-1/resolve", body: #"{"action":"allow"}"#, token: token).status == 200,
              "agente: resolve")
        let resposta = finish(resolvida, timeout: 3)
        check(resposta.body.contains(#""state":"resolved""#) && resposta.body.contains(#""action":"allow""#),
              "agente: resultado chega pelo long-poll (\(resposta.body))")
        check(resposta.elapsed < 2, "agente: resultado não espera o prazo")
        check(request("GET", "/agent-requests/lp-agent-1", token: token).status == 404, "agente: leitura única vale no long-poll")

        // dismiss pelo notch
        publishAgent("lp-agent-2")
        let dispensada = start("GET", "/agent-requests/lp-agent-2", token: token, wait: "10")
        spin(0.3)
        _ = server.dismissAgentRequest(id: "lp-agent-2", responder: .nob)
        let dispensa = finish(dispensada, timeout: 3)
        check(dispensa.body.contains(#""state":"dismissed""#) && dispensa.elapsed < 2, "agente: dismiss acorda a espera")

        // TTL vira expired e acorda
        publishAgent("lp-agent-3")
        let orfa = start("GET", "/agent-requests/lp-agent-3", token: token, wait: "10")
        spin(0.3)
        server.pruneExpired(agora: Date().addingTimeInterval(16 * 60))
        let expirada = finish(orfa, timeout: 3)
        check(expirada.body.contains(#""state":"expired""#) && expirada.elapsed < 2, "agente: TTL acorda com expired")
        check(waiting(server.agentRequestDiagnostics) == 0, "agente: nenhuma conexão sobrando")
    }

    /// Desligar a API derruba quem espera, como o GET que chegasse depois.
    static func longPollStop(_ server: NotchAPIServer) {
        publishAsk("lp-ask-stop")
        let pendente = start("GET", "/ask/lp-ask-stop", wait: "10")
        spin(0.3)
        check(waiting(server.askDiagnostics) == 1, "stop: conexão segurada")
        server.stop()
        let resultado = finish(pendente, timeout: 3)
        check(resultado.status == 0 && resultado.elapsed < 2, "stop: conexão segurada cai junto")
        check(waiting(server.askDiagnostics) == 0, "stop: nenhuma conexão sobrando")
    }

    static func publishAsk(_ id: String) {
        let body = #"{"id":"\#(id)","questions":[{"question":"Q?","options":[{"label":"Sim"}]}]}"#
        check(request("POST", "/ask", body: body).status == 200, "publica ask \(id)")
    }

    static func publishAgent(_ id: String) {
        let body = #"{"id":"\#(id)","agent":"claude","kind":"permission","title":"Read","summary":"README.md","source":"terminal","actions":[{"action":"allow"},{"action":"deny"}]}"#
        check(request("POST", "/agent-requests", body: body, token: token).status == 200, "publica agente \(id)")
    }

    static func waiting(_ diagnostics: [String: Any]) -> Int {
        diagnostics["waiting"] as? Int ?? -1
    }

    // MARK: - HTTP

    struct Resposta {
        var status = 0
        var body = ""
        var elapsed: TimeInterval = 0
    }

    /// Requisição em voo; o semáforo publica o resultado pra main.
    final class EmVoo {
        let semaphore = DispatchSemaphore(value: 0)
        let started = Date()
        var resposta = Resposta()
    }

    private static func start(_ method: String, _ path: String, body: String? = nil,
                              token: String? = nil, wait: String? = nil) -> EmVoo {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        request.httpBody = body?.data(using: .utf8)
        request.timeoutInterval = 30
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let wait { request.setValue(wait, forHTTPHeaderField: "X-Knobler-Wait") }
        let voo = EmVoo()
        URLSession.shared.dataTask(with: request) { data, response, _ in
            voo.resposta = Resposta(
                status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                body: String(data: data ?? Data(), encoding: .utf8) ?? "",
                elapsed: Date().timeIntervalSince(voo.started))
            voo.semaphore.signal()
        }.resume()
        return voo
    }

    /// Roda a main (onde o servidor vive) até a resposta chegar.
    private static func finish(_ voo: EmVoo, timeout: TimeInterval) -> Resposta {
        let deadline = Date().addingTimeInterval(timeout)
        while voo.semaphore.wait(timeout: .now()) == .timedOut {
            guard Date() < deadline else { return Resposta(status: -1, body: "sem resposta", elapsed: timeout) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return voo.resposta
    }

    private static func request(_ method: String, _ path: String, body: String? = nil,
                                token: String? = nil, wait: String? = nil) -> Resposta {
        finish(start(method, path, body: body, token: token, wait: wait), timeout: 5)
    }

    private static func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private static func spin(until timeout: TimeInterval, _ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() && Date() < deadline { spin(0.01) }
    }

    private static func rawRequest(_ request: String) -> Int {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        var status = 0
        connection.start(queue: .global())
        connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                if let data, let response = String(data: data, encoding: .utf8) {
                    status = Int(response.split(separator: " ").dropFirst().first ?? "") ?? 0
                }
                semaphore.signal()
                connection.cancel()
            }
        })
        let deadline = Date().addingTimeInterval(3)
        while semaphore.wait(timeout: .now()) == .timedOut && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return status
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
