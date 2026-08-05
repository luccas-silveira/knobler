//
//  LinkPreview.swift
//  Knobler
//
//  Link arrastado pro notch abre a página DENTRO do card, sem janela e sem
//  barra de navegador.
//
//  Singleton com tela dona, igual à nota rápida e pelo mesmo motivo: existe um
//  `NotchViewModel` por monitor, e um `WKWebView` por tela significaria N
//  páginas carregando a mesma coisa — cada uma gastando rede e CPU.
//

import AppKit
import Combine
import WebKit

@MainActor
final class LinkPreview: ObservableObject {
    static let shared = LinkPreview()

    /// nil = nenhum link aberto; a seção some da faixa.
    nonisolated(unsafe) private(set) var urlAtiva: URL?
    @Published private(set) var url: URL? { didSet { urlAtiva = url } }
    @Published private(set) var titulo = ""
    @Published private(set) var carregando = false
    @Published private(set) var progresso: Double = 0

    /// Tela que mostra o preview — escolhida pelo ponteiro na hora de abrir.
    /// Sem dono, arrastar um link expandiria todos os monitores.
    nonisolated(unsafe) private(set) var hostDisplayID: CGDirectDisplayID?

    /// Largura de viewport que o site enxerga, em pixels CSS. É o que decide se
    /// a página entrega o layout de desktop ou o de celular: o card tem ~736 pt,
    /// e nessa largura quase todo site cai no breakpoint mobile. Renderizar em
    /// 1280 e **encolher com zoom** preserva o desenho original.
    static let larguraCSS: CGFloat = 1280

    /// Um só, reusado entre links: criar `WKWebView` é caro e o processo de
    /// conteúdo demora a subir.
    private(set) lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        // barra horizontal nunca: o corte é no elemento raiz, então carrossel
        // interno da página (que rola sozinho) continua funcionando
        config.userContentController.addUserScript(WKUserScript(
            source: """
            (function () {
              var css = 'html{overflow-x:hidden !important;}';
              var tag = document.createElement('style');
              tag.appendChild(document.createTextNode(css));
              (document.head || document.documentElement).appendChild(tag);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true))

        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        // fundo escuro combina com o card; sem isto pisca branco a cada página
        web.setValue(false, forKey: "drawsBackground")
        observar(web)
        return web
    }()

    /// Ajusta o zoom pra que a página se comporte como se a janela tivesse
    /// `larguraCSS` de largura. Chamado pela view quando o card muda de tamanho.
    func ajustarZoom(paraLargura largura: CGFloat) {
        guard largura > 0 else { return }
        let novo = largura / Self.larguraCSS
        guard abs(webView.pageZoom - novo) > 0.001 else { return }
        webView.pageZoom = novo
    }

    private var observers: [NSKeyValueObservation] = []
    private init() {}

    /// `nonisolated`: o VM consulta isto de contexto síncrono (o mesmo motivo
    /// pelo qual `QuickNote.hosted` é barato). Só lê duas propriedades.
    nonisolated func hosted(by display: CGDirectDisplayID?) -> Bool {
        urlAtiva != nil && hostDisplayID != nil && hostDisplayID == display
    }

    /// Abre (ou troca) o link no card da tela indicada.
    func abrir(_ link: URL, on display: CGDirectDisplayID?) {
        guard LinkBrowser.isWebLink(link) else { return }
        hostDisplayID = display
        url = link
        titulo = link.host ?? ""
        webView.load(URLRequest(url: link))
        instalarAtalhos()
    }

    func fechar() {
        resetarEstado()
        removerAtalhos()
        // about:blank em vez de soltar a webView: para o áudio/vídeo da página
        // na hora, e o processo de conteúdo fica quente pro próximo link
        webView.load(URLRequest(url: URL(string: "about:blank")!))
    }

    /// Separado de `fechar()` só pra `_fecharSelfCheck()` provar o reset de
    /// estado sem tocar a `webView` (lazy: acessá-la instanciaria um
    /// `WKWebView` de verdade, que o self-check não pode fazer).
    private func resetarEstado() {
        url = nil
        hostDisplayID = nil
        titulo = ""
    }

    // MARK: - Atalhos de edição

    private var atalhoMonitor: Any?

    /// ⌘C/⌘V/⌘X/⌘A dentro da página.
    ///
    /// O app é `LSUIElement` e **não tem menu bar**, então os key equivalents do
    /// menu Edit não existem: sem isto, copiar e colar não funcionam nem com a
    /// janela-chave. O monitor traduz cada atalho no seletor correspondente e
    /// deixa o responder chain resolver — é o `WKWebView` que executa.
    ///
    /// Molde: `DescansoController.installEscMonitor`.
    func instalarAtalhos() {
        guard atalhoMonitor == nil else { return }
        atalhoMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command),
                  let tecla = event.charactersIgnoringModifiers?.lowercased()
            else { return event }
            let seletor: Selector
            switch tecla {
            case "c": seletor = #selector(NSText.copy(_:))
            case "v": seletor = #selector(NSText.paste(_:))
            case "x": seletor = #selector(NSText.cut(_:))
            case "a": seletor = #selector(NSText.selectAll(_:))
            default: return event
            }
            // não engole o evento se ninguém tratou: com o notch sem foco o
            // atalho tem que continuar valendo pro app de trás
            return NSApp.sendAction(seletor, to: nil, from: nil) ? nil : event
        }
    }

    func removerAtalhos() {
        guard let atalhoMonitor else { return }
        NSEvent.removeMonitor(atalhoMonitor)
        self.atalhoMonitor = nil
    }

    func voltar() { webView.goBack() }
    var podeVoltar: Bool { webView.canGoBack }

    func abrirFora() {
        guard let atual = webView.url ?? url else { return }
        NSWorkspace.shared.open(atual)
        fechar()
    }

    private func observar(_ web: WKWebView) {
        observers = [
            web.observe(\.isLoading, options: [.new]) { [weak self] w, _ in
                Task { @MainActor in self?.carregando = w.isLoading }
            },
            web.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in
                Task { @MainActor in self?.progresso = w.estimatedProgress }
            },
            web.observe(\.title, options: [.new]) { [weak self] w, _ in
                Task { @MainActor in
                    guard let t = w.title, !t.isEmpty else { return }
                    self?.titulo = t
                }
            },
        ]
    }
}

/// A décima conversão (tarefa 9): sem tipo próprio nascendo (o singleton já
/// existe) e sem `start()` — o preview nasce dormente (nenhum link aberto),
/// igual à Nota rápida. `parar()` fecha o preview aberto, se houver.
extension LinkPreview: PluginServico {
    func parar() { fechar() }
}

extension LinkPreview {
    /// Prova o `parar()` da peça (`PluginServico`, ver `Plugin.swift`): abre
    /// (estado direto, sem passar por `abrir()`) e fecha, checando que o
    /// estado zera. **Lacuna conhecida**: não exercita `abrir()`/`webView`
    /// de verdade — `abrir()` chama `webView.load` com a URL real (rede de
    /// verdade, proibido aqui) e `fechar()` toca a `webView` lazy só depois
    /// do reset de estado (`resetarEstado()`, coberto). O caminho WKWebView
    /// fica descoberto pelo self-check.
    static func _fecharSelfCheck() -> Bool {
        let lp = LinkPreview.shared
        lp.url = URL(string: "https://exemplo.com")
        lp.hostDisplayID = 1
        lp.titulo = "exemplo"
        lp.resetarEstado()
        return lp.url == nil && lp.urlAtiva == nil && lp.hostDisplayID == nil && lp.titulo.isEmpty
    }
}
