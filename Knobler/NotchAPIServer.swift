//
//  NotchAPIServer.swift
//  Knobler
//
//  API local: qualquer script pode publicar um card no notch.
//    curl -X POST localhost:4477/notify \
//      -d '{"title":"Deploy finalizado","body":"zoi-studio em produção","app":"Terminal"}'
//  Escuta SÓ em 127.0.0.1. HTTP mínimo (uma leitura, requests pequenos).
//  ponytail: v1 é notificação; atividade persistente com progresso fica pra v2.
//

import Foundation
import Network

final class NotchAPIServer {
    static let port: UInt16 = 4477
    var onNotification: ((NotchNotification) -> Void)?

    private var listener: NWListener?

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
        NSLog("knobler api: escutando em 127.0.0.1:\(Self.port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
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
        guard request.hasPrefix("POST /notify") else {
            return Self.http(
                status: "404 Not Found",
                body: #"{"ok":false,"usage":"POST /notify {\"title\":\"...\",\"body\":\"...\",\"app\":\"...\"}"}"#
            )
        }
        guard let bodyStart = request.range(of: "\r\n\r\n")?.upperBound,
              let json = try? JSONSerialization.jsonObject(
                  with: Data(request[bodyStart...].utf8)) as? [String: Any],
              let title = json["title"] as? String, !title.isEmpty
        else {
            return Self.http(
                status: "400 Bad Request",
                body: #"{"ok":false,"error":"JSON inválido ou sem title"}"#
            )
        }

        let notification = NotchNotification(
            appName: json["app"] as? String,
            title: title,
            body: json["body"] as? String ?? ""
        )
        DispatchQueue.main.async { [weak self] in
            self?.onNotification?(notification)
        }
        return Self.http(status: "200 OK", body: #"{"ok":true}"#)
    }

    private static func http(status: String, body: String) -> String {
        "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }
}
