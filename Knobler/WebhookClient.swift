//
//  WebhookClient.swift
//  Knobler
//
//  Liga o app ao relay (push.appzoi.com.br): pareia o device (POST /register →
//  Keychain), mantém um WebSocket vivo (auth por header), reconecta sozinho, e
//  entrega cada notificação recebida. Ver a pesquisa (R3) para o racional dos
//  contornos de bugs do URLSessionWebSocketTask (detecção lenta, double-pong).
//

import Foundation
import AppKit
import Network
import os

private struct PushNotification: Decodable {
    let type: String
    let title: String?; let body: String?; let iconURL: String?
    let iconEmoji: String?
    let url: String?; let sound: Bool?; let id: String?
}

final class WebhookClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published private(set) var connected = false
    @Published private(set) var link: String?
    var onNotify: ((NotchNotification) -> Void)?

    private let base = URL(string: "https://push.appzoi.com.br")!
    private let wsURL = URL(string: "wss://push.appzoi.com.br/ws")!
    private let log = Logger(subsystem: "com.zoi.knobler", category: "webhook")
    private let queue = DispatchQueue(label: "com.zoi.knobler.webhook")

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default          // NUNCA .background
        c.waitsForConnectivity = true; c.timeoutIntervalForRequest = 30
        let dq = OperationQueue(); dq.maxConcurrentOperationCount = 1
        return URLSession(configuration: c, delegate: self, delegateQueue: dq)
    }()

    private var task: URLSessionWebSocketTask?
    private var running = false
    private var epoch: UInt64 = 0
    private var attempt = 0
    private var pingWork, pongWork, reconnectWork: DispatchWorkItem?
    private let pingInterval: TimeInterval = 25, pongTimeout: TimeInterval = 10
    private let backoffCap: TimeInterval = 30
    private let path = NWPathMonitor(); private var online = true
    private var activity: NSObjectProtocol?
    private var observersInstalled = false

    // MARK: API pública

    func start() {
        queue.async {
            guard !self.running else { return }
            self.running = true
            self.installObservers()
            self.ensurePairedThenConnect()
        }
    }

    func stop() {
        queue.async {
            self.running = false
            self.teardown(reconnect: false)
            self.endActivity()
            DispatchQueue.main.async { self.connected = false }
        }
    }

    func shutdown() {
        stop()
        path.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        session.invalidateAndCancel()
    }

    /// Rotaciona o publishToken (link novo); o WS não cai (usa o deviceSecret).
    func rotate() {
        queue.async {
            guard let secret = WebhookKeychainStore.load(.deviceSecret) else { return }
            var req = URLRequest(url: self.base.appendingPathComponent("rotate"))
            req.httpMethod = "POST"
            req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            self.session.dataTask(with: req) { [weak self] data, _, _ in
                guard let self, let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pub = obj["publishToken"] as? String else { return }
                WebhookKeychainStore.save(pub, .publishToken)
                self.publishLink(pub)
            }.resume()
        }
    }

    // MARK: Pareamento

    private func ensurePairedThenConnect() {
        if let pub = WebhookKeychainStore.load(.publishToken),
           WebhookKeychainStore.load(.deviceSecret) != nil {
            publishLink(pub); connect(); return
        }
        // 1º uso: registra
        var req = URLRequest(url: base.appendingPathComponent("register"))
        req.httpMethod = "POST"
        session.dataTask(with: req) { [weak self] data, _, err in
            guard let self else { return }
            self.queue.async {
                guard self.running else { return }
                guard err == nil, let data,
                      let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let did = o["deviceId"] as? String,
                      let sec = o["deviceSecret"] as? String,
                      let pub = o["publishToken"] as? String else {
                    self.log.error("register falhou; retry")
                    self.queue.asyncAfter(deadline: .now() + 5) { self.ensurePairedThenConnect() }
                    return
                }
                WebhookKeychainStore.save(did, .deviceId)
                WebhookKeychainStore.save(sec, .deviceSecret)
                WebhookKeychainStore.save(pub, .publishToken)
                self.publishLink(pub)
                self.connect()
            }
        }.resume()
    }

    private func publishLink(_ pub: String) {
        let l = base.appendingPathComponent("w").appendingPathComponent(pub).absoluteString
        DispatchQueue.main.async { self.link = l }
    }

    // MARK: Conexão

    private func connect() {
        guard running, let secret = WebhookKeychainStore.load(.deviceSecret) else { return }
        reconnectWork?.cancel(); reconnectWork = nil
        epoch &+= 1
        task?.cancel(with: .goingAway, reason: nil); task = nil   // sem task órfão
        var req = URLRequest(url: wsURL)
        req.timeoutInterval = 15
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        let t = session.webSocketTask(with: req)
        t.maximumMessageSize = 1 << 20
        task = t; t.resume()
    }

    private func teardown(reconnect: Bool) {
        epoch &+= 1
        pingWork?.cancel(); pongWork?.cancel()
        reconnectWork?.cancel(); reconnectWork = nil   // evita reconnect órfão duplicado
        task?.cancel(with: .goingAway, reason: nil); task = nil
        DispatchQueue.main.async { self.connected = false }
        if reconnect { scheduleReconnect() }
    }

    private func handleDrop(_ reason: String) {
        guard running else { return }
        log.notice("drop: \(reason, privacy: .public)")
        teardown(reconnect: true)
    }

    private func scheduleReconnect() {
        guard running, online else { return }
        let ceil = min(backoffCap, pow(2, Double(attempt))); attempt += 1
        let delay = Double.random(in: 0...ceil)
        let item = DispatchWorkItem { [weak self] in guard let s = self, s.running, s.online else { return }; s.connect() }
        reconnectWork = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func forceReconnect() {
        guard running else { return }
        attempt = 0
        teardown(reconnect: false)
        let item = DispatchWorkItem { [weak self] in guard let s = self, s.running, s.online else { return }; s.connect() }
        reconnectWork = item
        queue.asyncAfter(deadline: .now() + Double.random(in: 0...1.5), execute: item)
    }

    // MARK: receive / ping

    private func receiveNext(_ e: UInt64) {
        guard let task, e == epoch else { return }
        task.receive { [weak self] r in self?.queue.async {
            guard let s = self, e == s.epoch else { return }
            switch r {
            case .success(let m): s.handle(m); s.receiveNext(e)
            case .failure(let err): s.handleDrop("receive \(err)")
            }
        } }
    }

    private func schedulePing(_ e: UInt64) {
        let item = DispatchWorkItem { [weak self] in
            guard let s = self, e == s.epoch, let t = s.task, s.running else { return }
            s.armPong(e)
            t.sendPing { [weak self] err in self?.queue.async {
                guard let s = self, e == s.epoch else { return }
                s.pongWork?.cancel()
                if let err { s.handleDrop("pong \(err)") } else { s.schedulePing(e) }
            } }
        }
        pingWork = item
        queue.asyncAfter(deadline: .now() + pingInterval, execute: item)
    }

    private func armPong(_ e: UInt64) {
        let item = DispatchWorkItem { [weak self] in
            guard let s = self, e == s.epoch, s.running else { return }
            s.handleDrop("pong timeout")
        }
        pongWork = item
        queue.asyncAfter(deadline: .now() + pongTimeout, execute: item)
    }

    // MARK: entrega

    private func handle(_ m: URLSessionWebSocketTask.Message) {
        let data: Data
        switch m { case .string(let s): data = Data(s.utf8); case .data(let d): data = d; @unknown default: return }
        guard let n = try? JSONDecoder().decode(PushNotification.self, from: data), n.type == "notify",
              let title = n.title, !title.isEmpty else { return }
        // ordem dos args = ordem de declaração na struct (memberwise init é sensível à ordem):
        // appName, title, body, [bundleID], [supacode*], openURL, iconURL, iconEmoji, webhookID
        let note = NotchNotification(
            appName: nil, title: title, body: n.body ?? "",
            openURL: n.url, iconURL: n.iconURL, iconEmoji: n.iconEmoji, webhookID: n.id)
        let playSound = n.sound ?? false
        DispatchQueue.main.async {
            if playSound { NSSound(named: "Pop")?.play() }
            self.onNotify?(note)
        }
    }

    // MARK: observers (wake / rede) + App Nap

    private func installObservers() {
        beginActivity()
        guard !observersInstalled else { return }
        observersInstalled = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        path.pathUpdateHandler = { [weak self] p in self?.queue.async {
            guard let s = self else { return }
            let ok = p.status == .satisfied, was = s.online; s.online = ok
            if ok && !was { s.forceReconnect() }
            else if !ok, s.running { s.teardown(reconnect: false) }
        } }
        path.start(queue: queue)
    }

    @objc private func didWake() { queue.async { self.forceReconnect() } }

    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "socket de push do Knobler")
    }
    private func endActivity() {
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask, didOpenWithProtocol p: String?) {
        queue.async {
            guard t === self.task else { return }
            self.attempt = 0
            DispatchQueue.main.async { self.connected = true }
            let e = self.epoch
            self.receiveNext(e); self.schedulePing(e)
            self.log.notice("conectado")
        }
    }
    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask, didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.async { guard t === self.task else { return }; self.handleDrop("close \(code.rawValue)") }
    }
    func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError e: Error?) {
        queue.async { guard t === self.task else { return }; self.handleDrop("complete \(e?.localizedDescription ?? "nil")") }
    }

    // MARK: API de perfis (HTTP autenticado pelo deviceSecret)

    struct WebhookProfile: Identifiable {
        let id: String
        var name: String
        var hasMapping: Bool
        var icon: String?
    }

    struct ProfileDetail {
        var name: String
        var mapping: String?
        var icon: String?
        var lastPayload: String?
    }

    /// Request autenticado ao relay (Bearer deviceSecret). Retorna o corpo cru ou nil.
    private func authed(_ path: String, method: String = "GET", body: Data? = nil) async -> Data? {
        guard let secret = WebhookKeychainStore.load(.deviceSecret) else { return nil }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try? await session.data(for: req).0
    }

    func listProfiles() async -> [WebhookProfile] {
        guard let d = await authed("profiles"),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        return arr.map {
            WebhookProfile(id: $0["profileId"] as? String ?? "", name: $0["name"] as? String ?? "",
                           hasMapping: $0["hasMapping"] as? Bool ?? false, icon: $0["icon"] as? String)
        }
    }

    /// Cria um perfil; guarda o publishToken no Keychain e retorna o profileId.
    func createProfile(name: String) async -> String? {
        guard let d = await authed("profiles", method: "POST", body: try? JSONSerialization.data(withJSONObject: ["name": name])),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let id = o["profileId"] as? String, let tok = o["publishToken"] as? String else { return nil }
        WebhookKeychainStore.saveProfileToken(tok, id)
        return id
    }

    func getProfile(_ id: String) async -> ProfileDetail? {
        guard let d = await authed("profiles/\(id)"),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return ProfileDetail(name: o["name"] as? String ?? "", mapping: o["mapping"] as? String,
                             icon: o["icon"] as? String, lastPayload: o["lastPayload"] as? String)
    }

    func updateProfile(_ id: String, name: String? = nil, mapping: String? = nil, icon: String? = nil) async {
        var b: [String: Any] = [:]
        if let name { b["name"] = name }
        if let mapping { b["mapping"] = mapping }
        if let icon { b["icon"] = icon }
        _ = await authed("profiles/\(id)", method: "PUT", body: try? JSONSerialization.data(withJSONObject: b))
    }

    func deleteProfile(_ id: String) async {
        _ = await authed("profiles/\(id)", method: "DELETE")
        WebhookKeychainStore.deleteProfileToken(id)
    }

    /// Rotaciona o token do perfil e guarda o novo no Keychain.
    func rotateProfile(_ id: String) async {
        guard let d = await authed("profiles/\(id)/rotate", method: "POST"),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let tok = o["publishToken"] as? String else { return }
        WebhookKeychainStore.saveProfileToken(tok, id)
    }

    /// Monta o link público do perfil (…/w/<token>) a partir do Keychain.
    func link(for id: String) -> String? {
        guard let tok = WebhookKeychainStore.loadProfileToken(id) else { return nil }
        return base.appendingPathComponent("w").appendingPathComponent(tok).absoluteString
    }
}
