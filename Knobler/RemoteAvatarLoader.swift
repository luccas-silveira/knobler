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

    private var session: URLSession?
    private var received = Data()
    private var currentURL: URL?

    /// Carrega (ou usa o cache). `nil`/inválido/desligado → `image` fica nil (fallback).
    func load(_ urlString: String?) {
        guard let urlString, let url = URL(string: urlString),
              url.scheme?.lowercased() == "https" else { image = nil; return }
        if let cached = Self.cache.object(forKey: url.absoluteString as NSString) {
            image = cached; return
        }
        currentURL = url
        received = Data()
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 8
        // ponytail: uma session por load; o loader é curto e por-card
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        session = s
        s.dataTask(with: req).resume()
    }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              let ct = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
              ct.hasPrefix("image/") else { completionHandler(.cancel); return }
        if let len = http.value(forHTTPHeaderField: "Content-Length"),
           let n = Int(len), n > Self.maxBytes { completionHandler(.cancel); return }
        completionHandler(.allow)
    }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received.append(data)
        if received.count > Self.maxBytes { dataTask.cancel() }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session = nil }
        guard error == nil, received.count <= Self.maxBytes,
              let src = CGImageSourceCreateWithData(received as CFData, nil),
              CGImageSourceGetCount(src) > 0,
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        let img = NSImage(cgImage: cg, size: .zero)
        if let url = currentURL { Self.cache.setObject(img, forKey: url.absoluteString as NSString) }
        DispatchQueue.main.async { self.image = img }
    }
}
