//
//  NotchAPIServer.swift
//  Knobler
//
//  API local: qualquer script pode publicar no notch.
//    curl -X POST localhost:4477/notify \
//      -d '{"title":"Deploy finalizado","body":"zoi-studio em produção","app":"Terminal"}'
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

    private var listener: NWListener?
    private var activities: [String: NotchActivity] = [:]
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
        emitActivity()
    }

    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-Self.activityTTL)
        let before = activities.count
        activities = activities.filter { $0.value.updatedAt > cutoff }
        if activities.count != before { emitActivity() }
    }

    private func emitActivity() {
        let display = activities.values.max { $0.updatedAt < $1.updatedAt }
        DispatchQueue.main.async { [weak self] in
            self?.onActivity?(display)
        }
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
                body: json["body"] as? String ?? ""
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

        if request.hasPrefix("GET /status") {
            let status = statusProvider?() ?? [:]
            let body = (try? JSONSerialization.data(withJSONObject: status))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return Self.http(status: "200 OK", body: body)
        }

        return Self.http(
            status: "404 Not Found",
            body: #"{"ok":false,"usage":["POST /notify {title, body?, app?}","POST /activity {id?, title, detail?, progress?, done?}","GET /status"]}"#
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
