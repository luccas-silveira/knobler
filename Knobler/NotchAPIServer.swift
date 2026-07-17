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

    private var listener: NWListener?
    private var activities: [String: NotchActivity] = [:]
    private struct PendingAsk {
        enum State { case pending, answered([String: AskAnswer]), cancelled }
        var state: State
        var updatedAt: Date
    }
    /// Respostas ficam retidas até a 1ª leitura do hook (ou TTL).
    private var pendingAsks: [String: PendingAsk] = [:]
    private static let askTTL: TimeInterval = 15 * 60
    private var expiryTimer: Timer?
    private static let activityTTL: TimeInterval = 30 * 60

    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        guard let listener = try? NWListener(using: parameters) else {
            NSLog("knobler api: porta \(Self.port) indisponível")
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
        NSLog("knobler api: escutando em 127.0.0.1:\(Self.port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        expiryTimer?.invalidate()
        expiryTimer = nil
        activities.removeAll()
        pendingAsks.removeAll()
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
    func cancelAsk(id: String) {
        guard case .pending = pendingAsks[id]?.state else { return }
        pendingAsks[id] = PendingAsk(state: .cancelled, updatedAt: Date())
    }

    var askDiagnostics: [String: Any] {
        ["pending": pendingAsks.count]
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, _, _ in
            guard let self, let data,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let response = self.respond(to: request)
            connection.send(
                content: response.data(using: .utf8),
                completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func respond(to request: String) -> String {
        let json: [String: Any]? = request.range(of: "\r\n\r\n").flatMap {
            try? JSONSerialization.jsonObject(
                with: Data(request[$0.upperBound...].utf8)) as? [String: Any]
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
            let ask = AskRequest(id: id, questions: questions, receivedAt: Date())
            DispatchQueue.main.async { [weak self] in self?.onAsk?(ask) }
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
            pendingAsks[id] = nil
            DispatchQueue.main.async { [weak self] in self?.onAskDismiss?(id) }
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

    private static let ok = http(status: "200 OK", body: #"{"ok":true}"#)

    private static func badRequest(_ error: String) -> String {
        http(status: "400 Bad Request", body: #"{"ok":false,"error":"\#(error)"}"#)
    }

    private static func http(status: String, body: String) -> String {
        "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }
}
