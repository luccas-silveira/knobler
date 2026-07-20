//
//  RemoteAvatarLoader.swift
//  Knobler
//
//  Carrega o avatar remoto de uma notificação de webhook com guardas de
//  segurança (o remetente não é confiável): só https, content-type de imagem,
//  teto de tamanho, timeout curto, validação real dos bytes, cache em memória.
//

import AppKit
import ImageIO

final class RemoteAvatarLoader: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published private(set) var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()
    private static let maxBytes = 512 * 1024

    /// Recusa host que é IP literal privado/loopback/link-local (reduz superfície de SSRF).
    /// Nomes DNS que resolvem pra IP privado (rebind) NÃO são cobertos — residual aceito.
    private static func isPrivateHost(_ host: String?) -> Bool {
        guard let host else { return false }
        if host.contains(":") {   // literal IPv6
            return host == "::1" || host.hasPrefix("fe80:")
                || host.hasPrefix("fc") || host.hasPrefix("fd")
        }
        let parts = host.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ Int($0) != nil }),
              let a = Int(parts[0]), let b = Int(parts[1]) else { return false } // hostname → permite
        if a == 127 || a == 10 || a == 0 { return true }
        if a == 172 && (16...31).contains(b) { return true }
        if a == 192 && b == 168 { return true }
        if a == 169 && b == 254 { return true }
        return false
    }

    private var session: URLSession?
    private var received = Data()
    private var currentURL: URL?

    /// Carrega (ou usa o cache). `nil`/inválido/host-privado/desligado → `image` nil (fallback).
    func load(_ urlString: String?) {
        session?.invalidateAndCancel()   // cancela request anterior em voo (sem corrida)
        session = nil
        guard let urlString, let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              !Self.isPrivateHost(url.host) else { image = nil; return }
        if let cached = Self.cache.object(forKey: url.absoluteString as NSString) {
            image = cached; return
        }
        image = nil                      // limpa avatar anterior enquanto baixa (sem stale)
        currentURL = url
        received = Data()
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 8
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        session = s
        s.dataTask(with: req).resume()
    }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard s === session else { return }   // ignora callback de sessão superada
        guard let http = response as? HTTPURLResponse,
              let ct = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
              ct.hasPrefix("image/") else { completionHandler(.cancel); return }
        if let len = http.value(forHTTPHeaderField: "Content-Length"),
           let n = Int(len), n > Self.maxBytes { completionHandler(.cancel); return }
        completionHandler(.allow)
    }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard s === session else { return }   // ignora callback de sessão superada
        received.append(data)
        if received.count > Self.maxBytes { dataTask.cancel() }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest req: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard s === session else { completionHandler(nil); return }   // ignora callback de sessão superada
        // só segue o redirect se continuar https e o host não for privado
        if req.url?.scheme?.lowercased() == "https", !Self.isPrivateHost(req.url?.host) {
            completionHandler(req)
        } else {
            completionHandler(nil)   // recusa o redirect (anti-downgrade / anti-SSRF)
        }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard s === session else { return }   // ignora callback de sessão superada
        defer { session = nil }
        guard error == nil, received.count <= Self.maxBytes,
              let src = CGImageSourceCreateWithData(received as CFData, nil),
              CGImageSourceGetCount(src) > 0,
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            DispatchQueue.main.async { self.image = nil }   // falha → fallback, nunca stale
            return
        }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        if let url = currentURL { Self.cache.setObject(img, forKey: url.absoluteString as NSString) }
        DispatchQueue.main.async { self.image = img }
    }
}
