//
//  NovidadesWindow.swift
//  Knobler
//
//  A página de novidades: uma NSWindow com uma WKWebView que carrega o
//  `shell.html` do bundle e recebe o corpo das versões pendentes por
//  WKUserScript. Quais versões entram é decisão do `NovidadesCatalogo`.
//
//  Por que HTML e não SwiftUI: figura com legenda, vídeo em loop, passo
//  numerado e botão de ação são baratos em CSS e caros em SwiftUI, e este
//  conteúdo muda a cada release enquanto a moldura não muda nunca.
//
//  O endurecimento segue o Sparkle (SUWKWebView.m), que resolve o mesmo
//  problema há anos — com uma diferença: lá o JavaScript do documento nasce
//  desligado porque o HTML vem de um feed remoto. Aqui o HTML é do bundle
//  assinado e a página precisa de listener de clique, então o que protege é o
//  content rule list (o documento não fala com a rede) e a allowlist de
//  navegação, não desligar JS.
//

import AppKit
import WebKit

/// O que a página pode pedir ao app. Enum fechado: string que não casa é
/// ignorada, nunca vira chamada.
enum NovidadeAcao {
    case abrirAjustes(String)
    case instalarPeca(String)
    case abrirCard

    init?(acao: String, alvo: String) {
        switch acao {
        case "abrirAjustes": self = .abrirAjustes(alvo)
        case "instalarPeca": self = .instalarPeca(alvo)
        case "abrirCard": self = .abrirCard
        default: return nil
        }
    }
}

@MainActor
protocol NovidadesAcoes: AnyObject {
    func executar(_ acao: NovidadeAcao)
}

@MainActor
final class NovidadesWindow: NSObject {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var observer: NSObjectProtocol?

    private let paginas: [String]
    private let aoFechar: () -> Void
    private weak var acoes: NovidadesAcoes?

    /// Nome do handler; o `ponte.js` fala com `webkit.messageHandlers.app`.
    private static let handler = "app"

    /// - Parameters:
    ///   - paginas: nomes de arquivo sem extensão, na ordem de exibição.
    ///   - aoFechar: roda no fechamento. É onde a versão vista é gravada.
    init(paginas: [String], acoes: NovidadesAcoes?, aoFechar: @escaping () -> Void) {
        self.paginas = paginas
        self.acoes = acoes
        self.aoFechar = aoFechar
    }

    /// Loga em vez de sumir em silêncio: sem a pasta a janela abriria em branco
    /// e o rastro seria nenhum. O log fica aqui, e não em cada `guard`, porque
    /// todos os caminhos passam por este acessor.
    private static var pasta: URL? {
        guard let url = Bundle.main.url(forResource: "Novidades", withExtension: nil) else {
            NSLog("knobler novidades: pasta Novidades ausente do bundle — página em branco")
            return nil
        }
        return url
    }

    /// Corpos das páginas, concatenados. Página que sumiu do bundle é pulada em
    /// silêncio: uma figura a menos é melhor que uma janela vazia.
    private func corpo() -> String {
        guard let pasta = Self.pasta else { return "" }
        return paginas.compactMap { nome in
            let url = pasta.appendingPathComponent("\(nome).html")
            guard let html = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            // A boas-vindas traz o próprio cabeçalho; versão ganha o dela.
            guard nome != NovidadesCatalogo.boasVindas else { return html }
            return "<section class=\"versao\"><h2>Versão \(nome)</h2>\(html)</section>"
        }.joined()
    }

    /// O corpo entra como literal JSON — que é literal JS válido — em vez de
    /// concatenação de string: aspas e barras invertidas do HTML não escapam
    /// pro código.
    private func scriptDeInjecao() -> WKUserScript? {
        guard let pasta = Self.pasta,
              let ponte = try? String(contentsOf: pasta.appendingPathComponent("ponte.js"),
                                      encoding: .utf8),
              let literal = try? JSONEncoder().encode(corpo()),
              let corpoJS = String(data: literal, encoding: .utf8)
        else { return nil }
        return WKUserScript(source: "window.KNOBLER_CORPO = \(corpoJS);\n\(ponte)",
                            injectionTime: .atDocumentEnd,
                            forMainFrameOnly: true)
    }

    func mostrar() {
        if window == nil { montar() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func montar() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        if let script = scriptDeInjecao() {
            config.userContentController.addUserScript(script)
        }
        config.userContentController.add(self, name: Self.handler)

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = false
        webView = web

        // A carga só começa depois do bloqueio de rede estar instalado — o
        // compile é assíncrono, e carregar antes deixaria a primeira (e única)
        // navegação passar sem filtro.
        aplicarBloqueioDeRede(em: web) { [weak self] in
            guard let self, let pasta = Self.pasta, self.webView === web else { return }
            web.loadFileURL(pasta.appendingPathComponent("shell.html"),
                            allowingReadAccessTo: pasta)
        }

        let window = NSWindow(contentRect: .zero,
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Novidades do Knobler"
        window.contentView = web
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 820, height: 620))
        window.center()
        self.window = window

        // Nenhuma janela do projeto tem delegate: o X e o ⌘W caem todos aqui.
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            // `queue: .main` garante a main **thread**, não a isolação estática:
            // o salto explícito troca um `assumeIsolated` (que aborta se o
            // contrato mudar) por um hop que no pior caso só atrasa um ciclo.
            Task { @MainActor in self?.desmontar() }
        }
    }

    /// A WKWebView morre com a janela. O WKUserContentController retém o
    /// handler forte — sem o remove aqui, o ciclo vaza e reabrir a janela com o
    /// mesmo nome de handler é erro, não warning.
    private func desmontar() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: Self.handler)
        webView?.navigationDelegate = nil
        webView = nil
        window = nil
        aoFechar()
    }

    /// Bloqueia toda requisição de **rede** do documento. Mais forte que CSP:
    /// não depende de o HTML cooperar. A página é 100% local; se algum dia um
    /// `<img>` apontar pra fora, ele simplesmente não carrega.
    ///
    /// O filtro casa esquema de rede em vez de `.*` de propósito: `.*` casaria
    /// também os `file://` do shell, do `estilo.css` e de `midia/*.png`, e o
    /// que o WebKit faz com content rule list sobre `file://` não é
    /// documentado. Bloquear o que se quer bloquear é mais barato que apostar.
    ///
    /// Uma regra por esquema, e não uma alternação: o `url-filter` aceita só um
    /// subconjunto de regex (classes, ranges, `.`, `*`, `+`, `?`, `^`, `$`) —
    /// grupo e `|` viram `Disjunctions are not supported yet` e a compilação
    /// inteira falha em silêncio. `?` é suportado, e o filtro já ignora caixa.
    ///
    /// `depois` roda sempre — inclusive se a compilação falhar: uma página sem
    /// o filtro é melhor que uma janela em branco, já que o conteúdo é do
    /// bundle assinado. Mas falha loga: foi o `_` no lugar do erro que deixou a
    /// regra anterior inerte sem ninguém notar.
    private func aplicarBloqueioDeRede(em web: WKWebView, depois: @escaping () -> Void) {
        let regra = #"""
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},
         {"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}},
         {"trigger":{"url-filter":"^ftp://"},"action":{"type":"block"}}]
        """#
        guard let store = WKContentRuleListStore.default() else { depois(); return }
        store.compileContentRuleList(forIdentifier: "novidades-sem-rede",
                                     encodedContentRuleList: regra) { lista, erro in
            if let erro {
                NSLog("knobler novidades: bloqueio de rede não compilou — %@",
                      erro.localizedDescription)
            }
            // A API não documenta em que fila o completion chega, então o salto
            // é explícito em vez de `MainActor.assumeIsolated` — que abortaria
            // o processo se um dia vier de outra fila.
            DispatchQueue.main.async {
                if let lista { web.configuration.userContentController.add(lista) }
                depois()
            }
        }
    }
}

extension NovidadesWindow: WKScriptMessageHandler {
    // Sem `nonisolated` e sem salto: o SDK declara `WKScriptMessage.body` como
    // main actor-isolated, ou seja, o próprio WebKit garante a main thread
    // aqui. Marcar o método `nonisolated` só produziria warning e obrigaria a
    // um `assumeIsolated` que pode abortar.
    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let corpo = message.body as? [String: Any],
              let nome = corpo["acao"] as? String else { return }
        let alvo = corpo["alvo"] as? String ?? ""
        guard let acao = NovidadeAcao(acao: nome, alvo: alvo) else { return }
        acoes?.executar(acao)
    }
}

extension NovidadesWindow: WKNavigationDelegate {
    // Idem: `WKNavigationAction.request`/`.navigationType` são main
    // actor-isolated no SDK, então o delegate é main por contrato do WebKit.
    func webView(_ webView: WKWebView,
                 decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        // A única navegação permitida é a carga do próprio shell, que o
        // `montar()` dispara: `.other` (nenhum gesto do usuário) + file://
        // dentro da pasta Novidades do bundle. Clique em link, formulário e
        // qualquer esquema de fora caem no cancel abaixo.
        if action.navigationType == .other, url?.isFileURL == true {
            decisionHandler(.allow); return
        }
        if let url, url.scheme == "https" || url.scheme == "http" {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    /// Carga que morre deixa rastro: sem isto a janela abre em branco e não há
    /// o que investigar. Os dois casos existem porque o WebKit separa a falha
    /// antes de a resposta chegar (provisional) da falha depois dela.
    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        NSLog("knobler novidades: carga do shell falhou — %@", error.localizedDescription)
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        NSLog("knobler novidades: navegação falhou — %@", error.localizedDescription)
    }
}
