//
//  NotchAPIServer.swift
//  Knobler
//
//  API local: qualquer script pode publicar no notch.
//    curl -X POST localhost:4477/notify \
//      -d '{"title":"Deploy finalizado","body":"zoi-studio em produção","app":"Terminal"}'
//  /notify aceita supacodeWorktree/supacodeTab opcionais: clique na notificação
//  foca aquela sessão no Supacode (via CLI do app).
//    curl -X POST localhost:4477/activity \
//      -d '{"id":"deploy","title":"Deploy zoi-studio","detail":"rsync…","progress":0.4}'
//    curl -X POST localhost:4477/activity -d '{"id":"deploy","done":true}'
//  Atividade persiste até done/expirar (30min sem update); a mais recente é
//  exibida (anel na asinha; detalhes no hover). Escuta SÓ em 127.0.0.1.
//

import Foundation
import Network

final class NotchAPIServer {
    static let port: UInt16 = 4477
    /// Token efêmero da sessão para o protocolo de solicitações de agentes.
    /// Nil mantém os endpoints novos indisponíveis, sem afetar a API legada.
    private let agentRequestToken: String?
    private let listenPort: UInt16
    var onNotification: ((NotchNotification) -> Void)?
    /// Atividade a exibir (a de update mais recente) — nil quando não há nenhuma.
    var onActivity: ((NotchActivity?) -> Void)?
    /// Diagnóstico pro GET /status (montado pelo AppDelegate).
    var statusProvider: (() -> [String: Any])?
    /// POST /mirror — liga/desliga o espelho da câmera no notch.
    var onMirror: ((Bool) -> Void)?
    /// Pergunta interativa (POST /ask): o hook do Claude Code cria, o card
    /// no notch responde, o hook lê via GET /ask/<id> (polling).
    var onAsk: ((AskRequest) -> Void)?
    /// Cancelamento vindo do hook (timeout): tira o card da tela.
    var onAskDismiss: ((String) -> Void)?
    /// Solicitações de agentes são um domínio separado do Ask legado.
    var onAgentRequest: ((AgentRequest) -> Void)?
    var onAgentRequestResolved: ((String, AgentRequestAction, AgentRequestResponder) -> Void)?
    var onAgentRequestExpired: ((String) -> Void)?

    private var listener: NWListener?
    private var activities: [String: NotchActivity] = [:]
    private struct PendingAsk {
        enum State { case pending, answered([String: AskAnswer]), cancelled }
        var state: State
        var updatedAt: Date
    }
    /// Respostas ficam retidas até a 1ª leitura do hook (ou TTL).
    private var pendingAsks: [String: PendingAsk] = [:]
    /// Invalida callbacks de Ask já agendados quando o listener é desligado.
    private var askGeneration: UInt64 = 0
    private static let askTTL: TimeInterval = 15 * 60
    private struct PendingAgentRequest {
        var request: AgentRequest
        var result: AgentRequestResult?
        var updatedAt: Date
    }
    private var pendingAgentRequests: [String: PendingAgentRequest] = [:]
    private static let agentRequestTTL: TimeInterval = 15 * 60
    private static let maxAgentRequestBodyBytes = 32 * 1024
    private static let maxRequestBytes = 64 * 1024
    private var expiryTimer: Timer?
    private static let activityTTL: TimeInterval = 30 * 60

    init(agentRequestToken: String? = nil, port: UInt16 = NotchAPIServer.port) {
        self.agentRequestToken = agentRequestToken
        self.listenPort = port
    }

    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: listenPort)!)
        guard let listener = try? NWListener(using: parameters) else {
            NSLog("knobler api: porta \(listenPort) indisponível")
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: .main)
        self.listener = listener
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {
            [weak self] _ in self?.pruneExpired()
        }
        NSLog("knobler api: escutando em 127.0.0.1:\(listenPort)")
    }

    func stop() {
        askGeneration &+= 1
        listener?.cancel()
        listener = nil
        expiryTimer?.invalidate()
        expiryTimer = nil
        activities.removeAll()
        pendingAsks.removeAll()
        pendingAgentRequests.removeAll()
        emitActivity()
    }

    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-Self.activityTTL)
        let before = activities.count
        activities = activities.filter { $0.value.updatedAt > cutoff }
        if activities.count != before { emitActivity() }
        // asks órfãos (hook morreu sem cancelar) também expiram
        let askCutoff = Date().addingTimeInterval(-Self.askTTL)
        pendingAsks = pendingAsks.filter { $0.value.updatedAt > askCutoff }

        let agentCutoff = Date().addingTimeInterval(-Self.agentRequestTTL)
        for (id, entry) in pendingAgentRequests where entry.updatedAt <= agentCutoff && entry.result == nil {
            pendingAgentRequests[id] = PendingAgentRequest(
                request: entry.request,
                result: AgentRequestResult(action: .cancel, responder: .system, state: .expired),
                updatedAt: Date()
            )
            onAgentRequestExpired?(id)
        }
        pendingAgentRequests = pendingAgentRequests.filter { $0.value.updatedAt > agentCutoff }
    }

    private func emitActivity() {
        let display = activities.values.max { $0.updatedAt < $1.updatedAt }
        DispatchQueue.main.async { [weak self] in
            self?.onActivity?(display)
        }
    }

    /// Card respondeu — primeira resposta vence; chamadas repetidas são no-op.
    func resolveAsk(id: String, answers: [String: AskAnswer]) {
        guard case .pending = pendingAsks[id]?.state else { return }
        pendingAsks[id] = PendingAsk(state: .answered(answers), updatedAt: Date())
    }

    /// ✕ no card: o hook lê cancelled e deixa a pergunta cair no terminal.
    @discardableResult
    func cancelAsk(id: String) -> Bool {
        guard case .pending = pendingAsks[id]?.state else { return false }
        pendingAsks[id] = PendingAsk(state: .cancelled, updatedAt: Date())
        return true
    }

    var askDiagnostics: [String: Any] {
        ["pending": pendingAsks.count]
    }

    var agentRequestDiagnostics: [String: Any] {
        let entries = pendingAgentRequests.values
        return [
            "pending": entries.filter { $0.result == nil }.count,
            "completed": entries.filter { $0.result != nil }.count,
        ]
    }

    /// Primeira resposta válida vence. O UI chama este método diretamente; os
    /// endpoints HTTP usam o mesmo caminho e, portanto, não podem sobrescrever.
    @discardableResult
    func resolveAgentRequest(
        id: String,
        action: AgentRequestAction,
        responder: AgentRequestResponder
    ) -> Bool {
        guard var entry = pendingAgentRequests[id],
              entry.result == nil,
              entry.request.actions.contains(action)
        else { return false }
        entry.request.state = .resolved
        entry.result = AgentRequestResult(action: action, responder: responder)
        entry.updatedAt = Date()
        pendingAgentRequests[id] = entry
        onAgentRequestResolved?(id, action, responder)
        return true
    }

    @discardableResult
    func dismissAgentRequest(id: String, responder: AgentRequestResponder) -> Bool {
        guard var entry = pendingAgentRequests[id], entry.result == nil else { return false }
        entry.request.state = .dismissed
        entry.result = AgentRequestResult(action: .cancel, responder: responder, state: .dismissed)
        entry.updatedAt = Date()
        pendingAgentRequests[id] = entry
        onAgentRequestResolved?(id, .cancel, responder)
        return true
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveRequest(on: connection, buffer: Data())
    }

    /// NWConnection pode entregar cabeçalho e corpo em receives separados.
    /// Junta somente até Content-Length, mantendo o teto legado de 64 KiB.
    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxRequestBytes) {
            [weak self] data, _, isComplete, _ in
            guard let self, let data else { connection.cancel(); return }
            var buffer = buffer
            buffer.append(data)
            guard buffer.count <= Self.maxRequestBytes else {
                self.send(Self.payloadTooLarge, on: connection)
                return
            }
            guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if isComplete { self.send(Self.badRequest("HTTP inválido"), on: connection) }
                else { self.receiveRequest(on: connection, buffer: buffer) }
                return
            }
            let headerData = buffer[..<headerRange.lowerBound]
            let header = String(data: headerData, encoding: .utf8) ?? ""
            let bodyLength = Self.contentLength(in: header) ?? 0
            guard bodyLength >= 0 else {
                self.send(Self.badRequest("Content-Length inválido"), on: connection)
                return
            }
            guard bodyLength <= Self.maxRequestBytes - headerRange.upperBound else {
                self.send(Self.payloadTooLarge, on: connection)
                return
            }
            let requiredBytes = headerRange.upperBound + bodyLength
            guard buffer.count >= requiredBytes || isComplete else {
                self.receiveRequest(on: connection, buffer: buffer)
                return
            }
            guard let request = String(data: buffer.prefix(requiredBytes), encoding: .utf8) else {
                self.send(Self.badRequest("HTTP inválido"), on: connection)
                return
            }
            self.send(self.respond(to: request), on: connection)
        }
    }

    private func send(_ response: String, on connection: NWConnection) {
        connection.send(
            content: response.data(using: .utf8),
            completion: .contentProcessed { _ in connection.cancel() })
    }

    private func respond(to request: String) -> String {
        let json: [String: Any]? = request.range(of: "\r\n\r\n").flatMap {
            try? JSONSerialization.jsonObject(
                with: Data(request[$0.upperBound...].utf8)) as? [String: Any]
        }

        if let route = Self.agentRequestRoute(in: request) {
            if Self.agentRequestBodyIsTooLarge(request) {
                return Self.payloadTooLarge
            }
            guard let agentRequestToken, Self.hasValidAgentToken(in: request, token: agentRequestToken) else {
                return Self.unauthorized
            }
            return respondToAgentRequest(route, json: json)
        }

        if request.hasPrefix("POST /notify") {
            guard let json, let title = json["title"] as? String, !title.isEmpty else {
                return Self.badRequest("JSON inválido ou sem title")
            }
            let notification = NotchNotification(
                appName: json["app"] as? String,
                title: title,
                body: json["body"] as? String ?? "",
                supacodeWorktree: json["supacodeWorktree"] as? String,
                supacodeTab: json["supacodeTab"] as? String
            )
            DispatchQueue.main.async { [weak self] in
                self?.onNotification?(notification)
            }
            return Self.ok
        }

        if request.hasPrefix("POST /activity") {
            guard let json else { return Self.badRequest("JSON inválido") }
            let id = json["id"] as? String ?? "default"

            if json["done"] as? Bool == true {
                activities[id] = nil
                emitActivity()
                return Self.ok
            }

            guard let title = json["title"] as? String, !title.isEmpty else {
                return Self.badRequest("sem title (ou use done:true pra encerrar)")
            }
            var progress = json["progress"] as? Double
            if let value = progress, value > 1 { progress = value / 100 } // aceita 0–100
            activities[id] = NotchActivity(
                id: id,
                title: title,
                detail: json["detail"] as? String ?? "",
                progress: progress.map { min(1, max(0, $0)) },
                updatedAt: Date()
            )
            emitActivity()
            return Self.ok
        }

        if request.hasPrefix("POST /mirror") {
            let on = json?["on"] as? Bool ?? true
            DispatchQueue.main.async { [weak self] in
                self?.onMirror?(on)
            }
            return Self.ok
        }

        // ordem importa: "POST /ask " (com espaço) não colide com "POST /ask/<id>/cancel"
        if request.hasPrefix("POST /ask ") {
            guard let json,
                  let id = json["id"] as? String, !id.isEmpty,
                  let rawQuestions = json["questions"] as? [[String: Any]],
                  !rawQuestions.isEmpty
            else { return Self.badRequest("precisa de id e questions") }

            var questions: [AskQuestion] = []
            for raw in rawQuestions {
                guard let text = raw["question"] as? String,
                      let rawOptions = raw["options"] as? [[String: Any]]
                else { return Self.badRequest("question/options malformados") }
                let options: [AskOption] = rawOptions.compactMap { opt in
                    guard let label = opt["label"] as? String else { return nil }
                    return AskOption(
                        label: label,
                        description: opt["description"] as? String ?? "",
                        preview: opt["preview"] as? String
                    )
                }
                guard !options.isEmpty else { return Self.badRequest("opções sem label") }
                questions.append(AskQuestion(
                    question: text,
                    header: raw["header"] as? String ?? "",
                    multiSelect: raw["multiSelect"] as? Bool ?? false,
                    options: options
                ))
            }

            pendingAsks[id] = PendingAsk(state: .pending, updatedAt: Date())
            let source = (json["source"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let ask = AskRequest(
                id: id, questions: questions, receivedAt: Date(), source: source)
            let generation = askGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.askGeneration == generation,
                      case .pending = self.pendingAsks[id]?.state
                else { return }
                self.onAsk?(ask)
            }
            return Self.ok
        }

        if request.hasPrefix("GET /ask/") {
            let id = String(request.dropFirst("GET /ask/".count).prefix { $0 != " " })
            guard let entry = pendingAsks[id] else {
                return Self.http(status: "404 Not Found",
                                 body: #"{"ok":false,"error":"ask desconhecido"}"#)
            }
            switch entry.state {
            case .pending:
                return Self.http(status: "200 OK", body: #"{"answered":false}"#)
            case .cancelled:
                pendingAsks[id] = nil
                return Self.http(status: "200 OK", body: #"{"cancelled":true}"#)
            case .answered(let answers):
                pendingAsks[id] = nil // resposta é lida uma única vez
                let payload: [String: Any] = [
                    "answered": true,
                    "answers": answers.mapValues { answer -> [String: Any] in
                        var out: [String: Any] = ["labels": answer.labels]
                        if let text = answer.text { out["text"] = text }
                        return out
                    },
                ]
                let body = (try? JSONSerialization.data(withJSONObject: payload))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                return Self.http(status: "200 OK", body: body)
            }
        }

        if request.hasPrefix("POST /ask/"),
           request.prefix(while: { $0 != "\r" }).contains("/cancel") {
            let id = String(request.dropFirst("POST /ask/".count).prefix { $0 != "/" })
            if cancelAsk(id: id) {
                let generation = askGeneration
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.askGeneration == generation else { return }
                    self.onAskDismiss?(id)
                }
            }
            return Self.ok
        }

        if request.hasPrefix("GET /status") {
            let status = statusProvider?() ?? [:]
            let body = (try? JSONSerialization.data(withJSONObject: status))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return Self.http(status: "200 OK", body: body)
        }

        return Self.http(
            status: "404 Not Found",
            body: #"{"ok":false,"usage":["POST /notify {title, body?, app?, supacodeWorktree?, supacodeTab?}","POST /activity {id?, title, detail?, progress?, done?}","POST /mirror {on?}","POST /ask {id, questions}","GET /ask/<id>","POST /ask/<id>/cancel","GET /status"]}"#
        )
    }

    private func respondToAgentRequest(_ route: AgentRequestRoute, json: [String: Any]?) -> String {
        switch route {
        case .publish:
            guard let json, let request = Self.decodeAgentRequest(json) else {
                return Self.badRequest("solicitação de agente inválida")
            }
            guard pendingAgentRequests[request.id] == nil else {
                return Self.conflict("solicitação de agente já existe")
            }
            pendingAgentRequests[request.id] = PendingAgentRequest(
                request: request, result: nil, updatedAt: Date())
            onAgentRequest?(request)
            return Self.ok

        case .read(let id):
            guard let entry = pendingAgentRequests[id] else {
                return Self.notFound("solicitação de agente desconhecida")
            }
            guard let result = entry.result else {
                return Self.json(status: "200 OK", object: ["id": id, "state": AgentRequestStatus.pending.rawValue])
            }
            pendingAgentRequests[id] = nil // resultado final tem leitura única
            guard let data = try? JSONEncoder().encode(result),
                  let resultObject = try? JSONSerialization.jsonObject(with: data) else {
                return Self.badRequest("resultado indisponível")
            }
            return Self.json(status: "200 OK", object: [
                "id": id,
                "state": result.state.rawValue,
                "result": resultObject,
            ])

        case .resolve(let id):
            guard let json,
                  let action = Self.decodeAgentAction(json),
                  resolveAgentRequest(id: id, action: action, responder: .terminal) || pendingAgentRequests[id] != nil
            else { return Self.badRequest("resolução inválida") }
            return Self.ok

        case .dismiss(let id):
            guard pendingAgentRequests[id] != nil else {
                return Self.notFound("solicitação de agente desconhecida")
            }
            _ = dismissAgentRequest(id: id, responder: .terminal)
            return Self.ok
        }
    }

    private enum AgentRequestRoute {
        case publish
        case read(String)
        case resolve(String)
        case dismiss(String)
    }

    private static func agentRequestRoute(in request: String) -> AgentRequestRoute? {
        guard let firstLine = request.components(separatedBy: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let method = parts[0]
        let path = String(parts[1])
        if method == "POST", path == "/agent-requests" { return .publish }
        guard path.hasPrefix("/agent-requests/") else { return nil }
        let suffix = path.dropFirst("/agent-requests/".count).split(separator: "/", omittingEmptySubsequences: false)
        guard let first = suffix.first, validAgentRequestID(String(first)) else { return nil }
        let id = String(first)
        if method == "GET", suffix.count == 1 { return .read(id) }
        if method == "POST", suffix.count == 2, suffix[1] == "resolve" { return .resolve(id) }
        if method == "POST", suffix.count == 2, suffix[1] == "dismiss" { return .dismiss(id) }
        return nil
    }

    private static func hasValidAgentToken(in request: String, token: String) -> Bool {
        guard let headers = request.range(of: "\r\n\r\n").map({ String(request[..<$0.lowerBound]) }) else {
            return false
        }
        let authorization = headers.components(separatedBy: "\r\n").compactMap { line -> String? in
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "authorization"
            else { return nil }
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
        guard authorization.count == 1 else { return false }
        let credential = authorization[0].split(whereSeparator: \.isWhitespace)
        return credential.count == 2
            && credential[0].lowercased() == "bearer"
            && String(credential[1]) == token
    }

    private static func agentRequestBodyIsTooLarge(_ request: String) -> Bool {
        let bodyLength = request.range(of: "\r\n\r\n").map { request[$0.upperBound...].utf8.count } ?? 0
        let headers = request.range(of: "\r\n\r\n").map { String(request[..<$0.lowerBound]) } ?? request
        let declaredLength = contentLength(in: headers)
        return bodyLength > maxAgentRequestBodyBytes || (declaredLength ?? 0) > maxAgentRequestBodyBytes
    }

    private static func contentLength(in headers: String) -> Int? {
        headers.components(separatedBy: "\r\n").first { line in
            line.lowercased().hasPrefix("content-length:")
        }.flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) }
    }

    private static func decodeAgentRequest(_ json: [String: Any]) -> AgentRequest? {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let payload = try? JSONDecoder().decode(AgentRequestPayload.self, from: data),
              validAgentRequestID(payload.id),
              validAgentText(payload.title, max: 512),
              validAgentText(payload.summary, max: 4 * 1024),
              payload.details.map({ $0.count <= 16 * 1024 }) ?? true,
              !payload.actions.isEmpty,
              payload.actions.count <= 8,
              payload.actions.allSatisfy(validAgentAction)
        else { return nil }
        return AgentRequest(
            id: payload.id, agent: payload.agent, kind: payload.kind,
            title: payload.title, summary: payload.summary, details: payload.details,
            source: payload.source, actions: payload.actions
        )
    }

    private static func decodeAgentAction(_ json: [String: Any]) -> AgentRequestAction? {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let action = try? JSONDecoder().decode(AgentRequestAction.self, from: data),
              validAgentAction(action)
        else { return nil }
        return action
    }

    private static func validAgentAction(_ action: AgentRequestAction) -> Bool {
        switch action {
        case .option(let value), .text(let value): return validAgentText(value, max: 4 * 1024)
        default: return true
        }
    }

    private static func validAgentText(_ value: String, max: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= max
    }

    private static func validAgentRequestID(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= 128 else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) || (65...90).contains(scalar.value)
                || (97...122).contains(scalar.value) || scalar == "-" || scalar == "_" || scalar == "."
        }
    }

    private struct AgentRequestPayload: Decodable {
        let id: String
        let agent: AgentName
        let kind: AgentRequestKind
        let title: String
        let summary: String
        let details: String?
        let source: AgentRequestSource
        let actions: [AgentRequestAction]
    }

    private static let ok = http(status: "200 OK", body: #"{"ok":true}"#)
    private static let unauthorized = http(status: "401 Unauthorized", body: #"{"ok":false,"error":"não autorizado"}"#)
    private static let payloadTooLarge = http(status: "413 Payload Too Large", body: #"{"ok":false,"error":"payload grande demais"}"#)

    private static func badRequest(_ error: String) -> String {
        http(status: "400 Bad Request", body: #"{"ok":false,"error":"\#(error)"}"#)
    }

    private static func notFound(_ error: String) -> String {
        http(status: "404 Not Found", body: #"{"ok":false,"error":"\#(error)"}"#)
    }

    private static func conflict(_ error: String) -> String {
        http(status: "409 Conflict", body: #"{"ok":false,"error":"\#(error)"}"#)
    }

    private static func json(status: String, object: [String: Any]) -> String {
        let body = (try? JSONSerialization.data(withJSONObject: object))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return http(status: status, body: body)
    }

    private static func http(status: String, body: String) -> String {
        "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }
}
