// Support source compiled only by agentrequest-api-check.swift.

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
        check(request("GET", "/agent-requests/check-1", token: token).status == 200, "valid token")
        check(request("POST", "/agent-requests/check-1/resolve", body: #"{"action":"allow"}"#, token: token).status == 200, "resolve")
        let firstRead = request("GET", "/agent-requests/check-1", token: token)
        check(firstRead.status == 200 && firstRead.body.contains(#""state":"resolved""#), "read-once result")
        check(request("GET", "/agent-requests/check-1", token: token).status == 404, "consumed result")
        check(request("POST", "/agent-requests", body: "{", token: token).status == 400, "malformed JSON")
        check(request("POST", "/agent-requests", body: String(repeating: "x", count: 32 * 1024 + 1), token: token).status == 413, "oversized body")
        print("agentrequest-api-check: OK")
    }

    private static func request(_ method: String, _ path: String, body: String? = nil, token: String? = nil) -> (status: Int, body: String) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        request.httpBody = body?.data(using: .utf8)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let semaphore = DispatchSemaphore(value: 0)
        var result: (Int, String) = (0, "")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            result = ((response as? HTTPURLResponse)?.statusCode ?? 0, String(data: data ?? Data(), encoding: .utf8) ?? "")
            semaphore.signal()
        }.resume()
        let deadline = Date().addingTimeInterval(3)
        while semaphore.wait(timeout: .now()) == .timedOut && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return result
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
