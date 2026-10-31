// Gate do "voltar" do preview de link (Knobler/LinkPreview.swift), com um
// WKWebView de verdade contra um servidor HTTP local nesta mesma porta efêmera
// (127.0.0.1, porta escolhida pelo kernel — nada sai da máquina).
//
// O WKWebView é um só pra sempre e o `fechar()` só carrega about:blank: a
// lista de voltar guardava as páginas de todas as sessões, e o botão voltar da
// sessão seguinte nascia ativo — primeiro uma página em branco, depois as
// páginas de um link já fechado. O gate trava a fronteira da sessão, o
// `fechar`+`abrir` em sequência e o swipe acompanhando o botão.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/LinkPreview.swift Knobler/LinkBrowser.swift tools/linkpreviewcheck.swift \
//     -o /tmp/linkpreviewcheck && /tmp/linkpreviewcheck

import AppKit
import Network
import WebKit

/// O LinkPreview é uma peça; o gate não precisa do sistema de plugins inteiro.
protocol PluginServico: AnyObject { func parar() }

private func exigir(_ cond: Bool, _ msg: String) {
    if !cond {
        print("FALHOU: \(msg)")
        exit(1)
    }
}

/// Responde qualquer caminho com uma página mínima cujo título é o caminho.
private final class Servidor {
    let listener: NWListener
    private(set) var porta: UInt16 = 0

    init() {
        let parametros = NWParameters.tcp
        parametros.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try! NWListener(using: parametros)
        listener.newConnectionHandler = { conexao in
            conexao.start(queue: .main)
            conexao.receive(minimumIncompleteLength: 1, maximumLength: 8192) { dados, _, _, _ in
                let pedido = dados.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let caminho = pedido.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                let corpo = "<html><head><title>\(caminho)</title></head><body>\(caminho)</body></html>"
                let resposta = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(corpo.utf8.count)\r\n"
                    + "Cache-Control: no-store\r\nConnection: close\r\n\r\n" + corpo
                conexao.send(content: Data(resposta.utf8), completion: .contentProcessed { _ in conexao.cancel() })
            }
        }
        listener.start(queue: .main)
        let limite = Date().addingTimeInterval(5)
        while listener.port == nil || listener.port?.rawValue == 0, Date() < limite {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        porta = listener.port?.rawValue ?? 0
        exigir(porta != 0, "o servidor local não subiu")
    }

    func url(_ caminho: String) -> URL { URL(string: "http://127.0.0.1:\(porta)/\(caminho)")! }
}

@main
enum Gate {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let servidor = Servidor()
        let lp = LinkPreview.shared

        /// Gira o run loop até a webView assentar em `alvo` (o KVO do preview
        /// também anda aqui).
        func esperar(_ alvo: URL, _ passo: String) {
            let limite = Date().addingTimeInterval(10)
            while Date() < limite {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                if !lp.webView.isLoading, lp.webView.url == alvo { break }
            }
            exigir(lp.webView.url == alvo && !lp.webView.isLoading,
                   "\(passo): a página não carregou (\(lp.webView.url?.absoluteString ?? "nil"))")
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))  // o Task do observer
        }
        func gestos() -> Bool { lp.webView.allowsBackForwardNavigationGestures }

        // Sessão 1: abre A, navega até B dentro da página.
        lp.abrir(servidor.url("a"), on: 1)
        esperar(servidor.url("a"), "abrir a")
        exigir(!lp.podeVoltar && !gestos(), "primeira página da sessão já podia voltar")
        lp.webView.load(URLRequest(url: servidor.url("b")))  // o clique num link
        esperar(servidor.url("b"), "navegar até b")
        exigir(lp.podeVoltar && gestos(), "dentro da sessão o voltar não ligou")

        // Fecha (about:blank) e abre C: a sessão nova não enxerga A, B nem o branco.
        lp.fechar()
        esperar(URL(string: "about:blank")!, "fechar")
        exigir(!lp.podeVoltar, "fechado, o preview ainda dizia poder voltar")
        lp.abrir(servidor.url("c"), on: 1)
        esperar(servidor.url("c"), "abrir c")
        exigir(lp.webView.canGoBack, "preparo: a lista do WebKit devia guardar a sessão anterior")
        exigir(!lp.podeVoltar, "sessão nova nasceu podendo voltar pra sessão fechada "
               + "(\(lp.webView.backForwardList.backList.map { $0.url.absoluteString }))")
        exigir(!gestos(), "sessão nova nasceu com o swipe de voltar ligado")
        lp.voltar()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        exigir(lp.webView.url == servidor.url("c"), "voltar() atravessou a fronteira: \(lp.webView.url?.absoluteString ?? "nil")")

        // Dentro da sessão nova, o voltar vale até a primeira página dela.
        lp.webView.load(URLRequest(url: servidor.url("d")))
        esperar(servidor.url("d"), "navegar até d")
        exigir(lp.podeVoltar && gestos(), "dentro da sessão nova o voltar não ligou")
        lp.voltar()
        esperar(servidor.url("c"), "voltar de d")
        exigir(!lp.podeVoltar && !gestos(), "de volta à primeira página, o voltar continuou ligado")

        // Fechar e abrir em sequência, sem o about:blank assentar.
        lp.fechar()
        lp.abrir(servidor.url("e"), on: 1)
        esperar(servidor.url("e"), "fechar+abrir e")
        exigir(!lp.podeVoltar, "fechar+abrir em sequência deixou voltar pra sessão anterior")

        // Trocar de link com um aberto é a mesma sessão: voltar leva ao anterior.
        lp.abrir(servidor.url("f"), on: 1)
        esperar(servidor.url("f"), "trocar pra f")
        exigir(lp.podeVoltar, "trocar de link perdeu o voltar pro link anterior")

        lp.fechar()
        servidor.listener.cancel()
        print("linkpreviewcheck ok — o voltar não atravessa a sessão")
    }
}
