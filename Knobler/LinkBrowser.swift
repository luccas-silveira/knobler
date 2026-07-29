//
//  LinkBrowser.swift
//  Knobler
//
//  Utilitário de endereço do preview de link. A página em si é desenhada pela
//  LinkPreviewView, dentro do card do notch — não há janela de navegador.
//

import Foundation

enum LinkBrowser {
    /// Link de verdade — `http`/`https` com host. Descarta `file:` (isso é
    /// arquivo e entra pelo outro caminho do drop) e esquemas que não abrem
    /// numa webview.
    static func isWebLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && !(url.host ?? "").isEmpty
    }

    /// Texto → URL. Sem esquema vira `https://`; o que não parece domínio vai
    /// pra busca. Existe separado da view porque é a única parte com regra —
    /// e regra sem teste é onde nasce "digitei e não foi".
    static func url(deEntrada texto: String) -> URL? {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else { return nil }

        if let url = URL(string: limpo), LinkBrowser.isWebLink(url) { return url }
        // "exemplo.com/x" — tem ponto, não tem espaço: é endereço, não busca
        if !limpo.contains(" "), limpo.contains("."),
           let url = URL(string: "https://\(limpo)"),
           LinkBrowser.isWebLink(url) {
            return url
        }
        var busca = URLComponents(string: "https://duckduckgo.com/")
        busca?.queryItems = [URLQueryItem(name: "q", value: limpo)]
        return busca?.url
    }
}
