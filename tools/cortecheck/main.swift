//
//  tools/cortecheck/main.swift — harness de TRANSIÇÃO da NotchView
//
//  O tools/main.swift renderiza POSES (ImageRenderer, estado parado). Este aqui
//  dirige TRANSIÇÕES: hospeda a NotchView de verdade numa NSHostingView dentro
//  de uma NSWindow fora da tela, muda o estado pelos mesmos pontos de entrada
//  que o app usa, e fotografa o resultado a cada ~30 ms enquanto a animação
//  corre. Cada quadro é classificado por pixel em três classes — fundo,
//  moldura e conteúdo — e o quadro é marcado como CORTE quando a moldura
//  desenhada não cobre o conteúdo desenhado.
//
//  Compilar e rodar: tools/cortecheck.sh
//
//  Fundo magenta puro de propósito: a sombra do card (preto a 35%) escurece o
//  magenta mas nunca chega perto do preto, então "quase preto" identifica a
//  moldura sem falso positivo de sombra, e todo pixel na reta preto→magenta
//  (as bordas antialiased da forma) continua caindo em fundo.
//

import AppKit
import ImageIO
import Network
import SwiftUI
import UniformTypeIdentifiers

// Mesmo dublê do harness de snapshot: `PluginsSettingsPane` alcança
// `KnoblerMain.delegate`, e `KnoblerApp.swift` não entra nesta compilação (o
// `@main` de lá brigaria com o código top-level deste arquivo).
// ponytail: dublê sem lógica — teto é uma chamada nova à vitrine de Ajustes,
// que quebra a compilação do harness. Upgrade: injetar as ações por protocolo.
@MainActor
enum KnoblerMain {
    struct DubleDeAppDelegate {
        func viewModelPrincipal() -> NotchViewModel? { nil }
        func ligarDesligarNota(em screen: NSScreen?) {}
    }
    static let delegate = DubleDeAppDelegate()
}

// MARK: - Medida de um quadro

/// Tolerância em pixels do bitmap (escala 2 ⇒ 4 px = 2 pt). Absorve o
/// antialias da borda inferior da forma sem engolir divergência de verdade:
/// o menor delta da Lista 3 da medição 002 é 22 pt.
let toleranciaPx = 4

struct Quadro {
    /// Primeira linha (de cima pra baixo) com pixel de moldura. > 0 = falta o topo.
    let topoMoldura: Int
    /// Última linha com pixel de moldura.
    let fimMoldura: Int
    /// Última linha com pixel de conteúdo.
    let fimConteudo: Int
    let escala: Int

    var vazio: Bool { fimMoldura < 0 }
    /// Quanto o conteúdo passa da moldura, em pontos. Negativo = cabe.
    var excedentePt: Double { Double(fimConteudo - fimMoldura) / Double(escala) }
    var alturaMolduraPt: Double { Double(fimMoldura - topoMoldura + 1) / Double(escala) }
    var lacunaTopoPt: Double { Double(topoMoldura) / Double(escala) }

    /// Moldura nenhuma COM conteúdo desenhado é o caso extremo de "a moldura não
    /// cobre o conteúdo" — não pode cair na guarda de quadro vazio.
    var molduraSumiuComConteudo: Bool { vazio && fimConteudo >= 0 }

    var temCorte: Bool {
        if molduraSumiuComConteudo { return true }
        guard !vazio else { return false }
        return (fimConteudo - fimMoldura) > toleranciaPx || topoMoldura > toleranciaPx
    }
}

/// Onde os quadros suspeitos (corte ou vazio) são gravados em PNG, pra olho
/// humano decidir se é defeito ou artefato de captura.
let pastaDeProvas = "/tmp/cortecheck-quadros"

/// Fotografa a view e classifica cada pixel. Varre coluna sim, coluna não —
/// o defeito é uma faixa inteira de altura, não um pixel solto.
@MainActor
func medir(_ host: NSView, escala: Int, etiqueta: String) -> Quadro {
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        return Quadro(topoMoldura: 0, fimMoldura: -1, fimConteudo: -1, escala: escala)
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let base = rep.bitmapData else {
        return Quadro(topoMoldura: 0, fimMoldura: -1, fimConteudo: -1, escala: escala)
    }
    let bpr = rep.bytesPerRow
    let bpp = rep.bitsPerPixel / 8
    var topoMoldura = -1, fimMoldura = -1, fimConteudo = -1

    for y in 0..<rep.pixelsHigh {
        var temMoldura = false, temConteudo = false
        var x = 0
        while x < rep.pixelsWide {
            let p = base + y * bpr + x * bpp
            let r = Int(p[0]), g = Int(p[1]), b = Int(p[2])
            if max(r, max(g, b)) < 16 {
                temMoldura = true
            } else if abs(r - b) < 31 && (min(r, b) - g) > 10 {
                // fundo (magenta puro, magenta com sombra, borda antialiased)
            } else {
                temConteudo = true
            }
            x += 2
        }
        if temMoldura {
            if topoMoldura < 0 { topoMoldura = y }
            fimMoldura = y
        }
        if temConteudo { fimConteudo = y }
    }
    let q = Quadro(topoMoldura: max(topoMoldura, 0), fimMoldura: fimMoldura,
                   fimConteudo: fimConteudo, escala: escala)
    if q.temCorte || q.vazio { gravarProva(rep, etiqueta: etiqueta) }
    return q
}

/// Grava o quadro suspeito. Sem isto, "moldura ausente" viraria um zero na
/// tabela e ninguém saberia se foi buffer não renderizado ou o piscar de verdade.
@MainActor
func gravarProva(_ rep: NSBitmapImageRep, etiqueta: String) {
    try? FileManager.default.createDirectory(atPath: pastaDeProvas,
                                             withIntermediateDirectories: true)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    let alvo = "\(pastaDeProvas)/\(etiqueta).png"
    try? png.write(to: URL(fileURLWithPath: alvo))
}

// MARK: - Cena

/// Tudo que uma transição precisa mexer. Recriada por transição: os stores com
/// singleton (`QuickNote`, `LinkPreview`, `NotificationHistory`) não são, então
/// o `limpar()` desfaz o que a transição anterior deixou ligado.
@MainActor
final class Cena {
    let vm = NotchViewModel()
    let media = MediaController()
    let shelf = ShelfStore()
    let lan = LANMessaging()
    let mensagens = MessageStore(carregando: false)
    let askStore = AskStore(dependencies: .init(resolve: { _, _ in }, cancel: { _ in }))
    let agentRequestStore = AgentRequestStore(resolveRemote: { _, _ in false },
                                              dismissRemote: { _ in })

    init(notchReal: Bool) {
        vm.displayID = 1
        vm.hasRealNotch = notchReal
        vm.notchSize = notchReal ? CGSize(width: 200, height: 32)
                                 : CGSize(width: 190, height: 30)
        media.injectPreview(state: musicaFalsa(), artwork: nil)
    }

    /// Desliga a persistência do histórico ANTES de qualquer notificação: o
    /// `vm.enqueue` (o ponto de entrada de verdade) chama
    /// `NotificationHistory.shared.record`, que grava no Application Support do
    /// usuário. Com `arquivo = nil` o `scheduleSave` volta na guarda e o harness
    /// não suja a caixa de ninguém. Também esvazia o que veio do disco: item
    /// herdado ligaria a seção `.historico` e mudaria a ordem das seções.
    static func isolarDisco() {
        NotificationHistory.shared.arquivo = nil
        NotificationHistory.shared.limpar()
    }

    static func limpar() {
        LinkPreview.shared.fechar()
        QuickNote.shared.active = false
        QuickNote.shared.text = ""
        QuickNote.shared.hostDisplayID = nil
    }
}

func musicaFalsa() -> MediaController.PlaybackState {
    .init(isPlaying: true, title: "Paranoid Android", artist: "Radiohead",
          album: "OK Computer", duration: 386, position: 143,
          fetchedAt: Date(), artworkURL: nil)
}

/// `https` porque `LinkPreview.abrir` filtra por `LinkBrowser.isWebLink`;
/// `localhost` porque a conexão é recusada na hora — o card do link muda de
/// altura no instante em que a URL entra, sem depender de rede.
let linkDeTeste = URL(string: "https://localhost/")!

/// PNG de verdade: o preview de conversão da prateleira só sai do estado
/// "convertendo" com um arquivo que o ImageIO abra.
func arquivoPNGFalso() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cortecheck.png")
    guard !FileManager.default.fileExists(atPath: url.path) else { return url }
    let tamanho = CGSize(width: 480, height: 300)
    guard let ctx = CGContext(data: nil, width: Int(tamanho.width),
                              height: Int(tamanho.height), bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let imagem = { () -> CGImage? in
              ctx.setFillColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1)
              ctx.fill(CGRect(origin: .zero, size: tamanho))
              return ctx.makeImage()
          }(),
          let destino = CGImageDestinationCreateWithURL(
              url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return url }
    CGImageDestinationAddImage(destino, imagem, nil)
    CGImageDestinationFinalize(destino)
    return url
}
// MARK: - Transições

typealias Acao = @MainActor (Cena) -> Void

struct Transicao {
    let nome: String
    let familia: String
    /// Conteúdo e abertura do card. Roda antes do assentamento.
    let montar: Acao
    /// Seção a focar DEPOIS do assentamento. Focar antes não adianta: abrir o
    /// card dispara o `recalcularSecoes` do `AberturaDoCard`, que remonta a
    /// ordem a partir do conteúdo real e derruba um foco pedido cedo demais.
    let foco: NotchSection?
    /// (atraso em segundos a partir do disparo, ação). Atraso 0 = mesma runloop.
    let passos: [(TimeInterval, Acao)]

    init(nome: String, familia: String, montar: @escaping Acao,
         foco: NotchSection? = nil, passos: [(TimeInterval, Acao)]) {
        self.nome = nome
        self.familia = familia
        self.montar = montar
        self.foco = foco
        self.passos = passos
    }
}

@MainActor
func atividadeFalsa(_ c: Cena) {
    c.vm.activity = NotchActivity(id: "deploy", title: "Deploy", detail: "3 de 8",
                                  progress: 0.375, updatedAt: Date())
}

@MainActor
func pomodoroFalso(_ c: Cena) {
    c.vm.pomodoro = PomodoroState(phase: .focus, runState: .running, remaining: 900,
                                  completedFocus: 1, cyclesUntilLong: 4)
}

// Seções não varridas de propósito: `.mensagens`, `.historico` e `.nota`. Dar
// conteúdo a elas passa por `MessageStore.append`, `NotificationHistory` e
// `QuickNote`, que gravam no Application Support REAL do usuário — um harness
// não pode sujar a caixa de mensagens de quem roda o gate. As alturas delas
// (272, 272 e 148) estão cobertas por proxy: `.link` aberto (438) é a maior
// seção do app e entra na varredura.

let transicoes: [Transicao] = [
    // ---- Lista 3 da medição 002: o `mode` fica PARADO em .music e a moldura
    // muda de altura sem `.animation(_:value:)` amarrada. Os dois sentidos.
    Transicao(nome: "foco-link-para-atividade", familia: "lista3-focus",
              montar: { c in
                  atividadeFalsa(c)
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { $0.vm.focar(.atividade) })]),
    Transicao(nome: "foco-atividade-para-link", familia: "lista3-focus",
              montar: { c in
                  atividadeFalsa(c)
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .atividade,
              passos: [(0, { $0.vm.focar(.link) })]),
    Transicao(nome: "foco-espelho-para-atividade", familia: "lista3-focus",
              montar: { c in
                  atividadeFalsa(c)
                  c.vm.mirrorOn = true
                  c.vm.expanded = true
              },
              foco: .espelho,
              passos: [(0, { $0.vm.focar(.atividade) })]),
    Transicao(nome: "foco-atividade-para-espelho", familia: "lista3-focus",
              montar: { c in
                  atividadeFalsa(c)
                  c.vm.mirrorOn = true
                  c.vm.expanded = true
              },
              foco: .atividade,
              passos: [(0, { $0.vm.focar(.espelho) })]),
    Transicao(nome: "link-fecha", familia: "lista3-link",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { _ in LinkPreview.shared.fechar() })]),
    Transicao(nome: "link-abre", familia: "lista3-link",
              montar: { c in
                  atividadeFalsa(c)
                  c.vm.expanded = true
              },
              foco: .atividade,
              // dois passos porque é assim no app: a seção `.link` só entra na
              // ordem depois que o `AberturaDoCard` recalcula com `hasLink`
              // verdadeiro — focar no mesmo instante cairia na guarda do `focar`.
              passos: [(0, { _ in LinkPreview.shared.abrir(linkDeTeste, on: 1) }),
                       (0.05, { $0.vm.focar(.link) })]),
    Transicao(nome: "espelho-desliga", familia: "lista3-espelho",
              montar: { c in
                  c.vm.mirrorOn = true
                  c.vm.expanded = true
              },
              foco: .espelho,
              passos: [(0, { $0.vm.mirrorOn = false })]),
    Transicao(nome: "espelho-liga", familia: "lista3-espelho",
              montar: { c in
                  c.vm.mirrorOn = true
                  c.vm.expanded = true
              },
              foco: .espelho,
              passos: [(0, { $0.vm.mirrorOn = false }), (0.20, { $0.vm.mirrorOn = true })]),
    Transicao(nome: "pomodoro-evento-sai", familia: "lista3-calendario",
              montar: { c in
                  pomodoroFalso(c)
                  c.vm.calendarAviso = CalendarAviso(titulo: "Retrospectiva", faltam: 720)
                  c.vm.expanded = true
              },
              foco: .pomodoro,
              passos: [(0, { $0.vm.calendarAviso = nil })]),
    Transicao(nome: "pomodoro-evento-entra", familia: "lista3-calendario",
              montar: { c in
                  pomodoroFalso(c)
                  c.vm.expanded = true
              },
              foco: .pomodoro,
              passos: [(0, { $0.vm.calendarAviso = CalendarAviso(titulo: "Retrospectiva",
                                                                 faltam: 720) })]),
    Transicao(nome: "shelf-preview-abre", familia: "lista3-shelf",
              montar: { c in
                  c.shelf.add(arquivoPNGFalso())
                  c.vm.expanded = true
              },
              foco: .shelf,
              passos: [(0, { c in c.shelf.startPreview(arquivoPNGFalso(), to: .image(.jpeg)) })]),
    Transicao(nome: "notificacao-perde-acoes", familia: "lista3-notificacao",
              montar: { c in
                  c.vm.enqueue(NotchNotification(appName: "Finder", title: "Backup",
                                                 body: "Terminou às 14:32",
                                                 actionTitles: ["Abrir", "Ignorar"]))
              },
              passos: [(0, { c in
                  c.vm.activeNotification = NotchNotification(
                      appName: "Finder", title: "Backup", body: "Terminou às 14:32")
              })]),
    Transicao(nome: "incoming-perde-resposta", familia: "lista3-incoming",
              montar: { c in
                  c.vm.showIncoming(.init(peerID: "p1", name: "Marina",
                                          text: "Bora almoçar?", allowReply: true))
              },
              passos: [(0, { c in
                  c.vm.incoming = .init(peerID: "p1", name: "Marina",
                                        text: "Bora almoçar?", allowReply: false)
              })]),

    // ---- Os MESMOS saltos de foco, agora pelo caminho de verdade: clicar na
    // faixa é `withAnimation(.easeOut(duration: 0.22)) { vm.focar(s) }`
    // (`NotchView.swift:986`) e o swipe horizontal é o mesmo embrulho em torno
    // de `focarVizinho` (`KnoblerApp.swift:1006`). Chamar `focar` pelado, como
    // as transições acima fazem, roda numa transação ambiente VAZIA — não é o
    // que o app faz. A duração aqui (0.22) é diferente da que o `expandedContent`
    // usa pro mesmo `vm.focus` (0.3, `NotchView.swift:970`).
    Transicao(nome: "faixa-link-para-atividade", familia: "faixa-withanimation",
              montar: { c in
                  atividadeFalsa(c)
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { c in
                  withAnimation(.easeOut(duration: 0.22)) { c.vm.focar(.atividade) }
              })]),
    Transicao(nome: "faixa-atividade-para-link", familia: "faixa-withanimation",
              montar: { c in
                  atividadeFalsa(c)
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .atividade,
              passos: [(0, { c in
                  withAnimation(.easeOut(duration: 0.22)) { c.vm.focar(.link) }
              })]),
    Transicao(nome: "faixa-espelho-para-atividade", familia: "faixa-withanimation",
              montar: { c in
                  atividadeFalsa(c)
                  c.vm.mirrorOn = true
                  c.vm.expanded = true
              },
              foco: .espelho,
              passos: [(0, { c in
                  withAnimation(.easeOut(duration: 0.22)) { c.vm.focar(.atividade) }
              })]),
    Transicao(nome: "swipe-vizinho-avancando", familia: "faixa-withanimation",
              montar: { c in
                  atividadeFalsa(c)
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .atividade,
              passos: [(0, { c in
                  withAnimation(.easeOut(duration: 0.22)) { c.vm.focarVizinho(avancando: true) }
              })]),
    Transicao(nome: "swipe-vizinho-voltando", familia: "faixa-withanimation",
              montar: { c in
                  atividadeFalsa(c)
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { c in
                  withAnimation(.easeOut(duration: 0.22)) { c.vm.focarVizinho(avancando: false) }
              })]),
    Transicao(nome: "faixa-troca-durante-abertura", familia: "faixa-withanimation",
              montar: { c in
                  atividadeFalsa(c)
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .atividade,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.60, { $0.vm.setExpandedDirect(true) }),
                       (0.68, { c in
                           withAnimation(.easeOut(duration: 0.22)) { c.vm.focar(.link) }
                       })]),

    // ---- Duas mudanças na mesma runloop: `mode` junto com algo que muda a altura.
    Transicao(nome: "abre-card-e-troca-foco", familia: "mesma-runloop",
              montar: { c in
                  atividadeFalsa(c)
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .atividade,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.60, { c in
                           c.vm.setExpandedDirect(true)
                           c.vm.focar(.link)
                       })]),
    Transicao(nome: "fecha-card-e-troca-foco", familia: "mesma-runloop",
              montar: { c in
                  atividadeFalsa(c)
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { c in
                  c.vm.setExpandedDirect(false)
                  c.vm.focar(.atividade)
              })]),
    Transicao(nome: "fecha-card-e-fecha-link", familia: "mesma-runloop",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { c in
                  LinkPreview.shared.fechar()
                  c.vm.setExpandedDirect(false)
              })]),
    Transicao(nome: "abre-card-e-abre-link", familia: "mesma-runloop",
              montar: { c in
                  atividadeFalsa(c)
                  c.vm.expanded = true
              },
              foco: .atividade,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.60, { c in
                           LinkPreview.shared.abrir(linkDeTeste, on: 1)
                           c.vm.setExpandedDirect(true)
                       })]),
    Transicao(nome: "hud-com-card-aberto", familia: "mesma-runloop",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { $0.vm.showHUD(.init(level: 0.6, muted: false)) })]),

    // ---- Chegada assíncrona NO MEIO da animação de expansão (0.12 s ≈ metade
    // da mola de abertura, response 0.42).
    Transicao(nome: "notificacao-durante-abertura", familia: "chegada-assincrona",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.60, { $0.vm.setExpandedDirect(true) }),
                       (0.72, { c in
                           c.vm.enqueue(NotchNotification(appName: "Finder", title: "Backup",
                                                          body: "Terminou às 14:32",
                                                          actionTitles: ["Abrir"]))
                       })]),
    Transicao(nome: "hud-durante-abertura", familia: "chegada-assincrona",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.60, { $0.vm.setExpandedDirect(true) }),
                       (0.72, { $0.vm.showHUD(.init(level: 0.6, muted: false)) })]),
    Transicao(nome: "pomodoro-durante-abertura", familia: "chegada-assincrona",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.60, { $0.vm.setExpandedDirect(true) }),
                       (0.72, { pomodoroFalso($0) })]),
    Transicao(nome: "mensagem-durante-abertura", familia: "chegada-assincrona",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.60, { $0.vm.setExpandedDirect(true) }),
                       (0.72, { c in
                           c.vm.showIncoming(.init(peerID: "p1", name: "Marina",
                                                   text: "Bora almoçar?", allowReply: true))
                       })]),
    Transicao(nome: "link-durante-abertura", familia: "chegada-assincrona",
              montar: { c in
                  atividadeFalsa(c)
                  c.vm.expanded = true
              },
              foco: .atividade,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.60, { $0.vm.setExpandedDirect(true) }),
                       (0.72, { _ in LinkPreview.shared.abrir(linkDeTeste, on: 1) })]),
    Transicao(nome: "espelho-durante-abertura", familia: "chegada-assincrona",
              montar: { c in
                  c.vm.mirrorOn = true
                  c.vm.expanded = true
              },
              foco: .espelho,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.60, { $0.vm.setExpandedDirect(true) }),
                       (0.72, { $0.vm.mirrorOn = false })]),

    // Chegada de screenshot: `ScreenshotWatcher.onScreenshot` faz
    // `shelf.add(url)` + `peekShelf()`, e o `peekShelf` é um
    // `setExpandedDirect(true)` (`KnoblerApp.swift:266` e `:1023`).
    Transicao(nome: "screenshot-durante-abertura", familia: "chegada-assincrona",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.60, { $0.vm.setExpandedDirect(true) }),
                       (0.72, { c in
                           c.shelf.add(arquivoPNGFalso())
                           c.vm.setExpandedDirect(true)
                       })]),

    // ---- setExpandedDirect cancelando o pendingWork do hover.
    Transicao(nome: "hover-abre-e-gesto-fecha", familia: "hover-vs-gesto",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.60, { $0.vm.setHover(true) }),
                       (0.90, { $0.vm.setExpandedDirect(false) })]),
    // 0.34 s > closeDelay (0.30): o fechamento por hover chega a acontecer e o
    // gesto reabre logo depois. Em 0.30 o gesto cancelaria o `pendingWork`
    // antes de ele rodar e nada se moveria.
    // Sem link aberto de propósito: `fecharPorHoverOut` tem
    // `guard !linkAberto` — com página aberta o card congela e o hover-out não
    // moveria nada.
    Transicao(nome: "hover-fecha-e-gesto-reabre", familia: "hover-vs-gesto",
              montar: { c in
                  c.vm.mirrorOn = true
                  c.vm.expanded = true
              },
              foco: .espelho,
              passos: [(0, { $0.vm.setHover(false) }),
                       (0.34, { $0.vm.setExpandedDirect(true) })]),
    Transicao(nome: "hover-abre-e-troca-foco", familia: "hover-vs-gesto",
              montar: { c in
                  atividadeFalsa(c)
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .atividade,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.60, { $0.vm.setHover(true) }),
                       (0.90, { $0.vm.focar(.link) })]),
]

// MARK: - Motor

let janelaLargura: CGFloat = 900
let janelaAltura: CGFloat = 640
/// Quanto tempo a observação dura DEPOIS do último passo.
let observacao: TimeInterval = 0.8
/// Giro de runloop entre uma foto e outra. A foto em si custa ~30 ms
/// (`cacheDisplay` de 1800×1520 px), então a cadência real fica em ~15 Hz.
let passoDeFoto: TimeInterval = 0.01

/// Reduced Motion não é varrido: `NotchView` lê
/// `@Environment(\.accessibilityReduceMotion)`, e esse key path é somente-leitura
/// no SDK do macOS 26 — forçá-lo exigiria mexer na preferência de acessibilidade
/// da máquina do usuário. O harness registra qual valor estava em vigor.
@MainActor
let reducedMotionDoSistema = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

let verboso = ProcessInfo.processInfo.environment["CORTECHECK_VERBOSE"] != nil

struct Resultado {
    let nome: String
    let familia: String
    let quadros: [Quadro]
    /// Segundos gastos na janela de observação — dá a cadência real das fotos.
    let duracao: TimeInterval

    var quadrosComCorte: Int { quadros.filter(\.temCorte).count }
    var excedenteMaxPt: Double { quadros.map(\.excedentePt).max() ?? 0 }
    var lacunaTopoMaxPt: Double { quadros.map(\.lacunaTopoPt).max() ?? 0 }
    var alturas: [Int] { quadros.map { Int($0.alturaMolduraPt.rounded()) } }
    var alturasDistintas: Int { Set(alturas).count }
    var hz: Double { duracao > 0 ? Double(quadros.count) / duracao : 0 }
}

@MainActor
func rodar(_ t: Transicao) -> Resultado {
    Cena.limpar()
    let cena = Cena(notchReal: true)
    let raiz = ZStack(alignment: .top) {
        // magenta puro: ver o cabeçalho deste arquivo
        Color(red: 1, green: 0, blue: 1)
        NotchView(vm: cena.vm, askStore: cena.askStore,
                  agentRequestStore: cena.agentRequestStore,
                  media: cena.media, levels: SystemAudioLevels(), shelf: cena.shelf,
                  dropTargetsEnabled: false)
            .environmentObject(cena.mensagens)
            .environmentObject(cena.lan)
    }
    .frame(width: janelaLargura, height: janelaAltura)

    let host = NSHostingView(rootView: AnyView(raiz))
    host.frame = NSRect(x: 0, y: 0, width: janelaLargura, height: janelaAltura)
    let janela = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
    janela.contentView = host
    // fora de qualquer tela: a animação continua correndo (é o que o controle
    // positivo prova) e nada aparece pro usuário.
    janela.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    janela.orderFrontRegardless()

    // Assenta ANTES de mexer: mudar o estado antes do primeiro giro do runloop
    // faz o SwiftUI adotar o valor novo como inicial, sem animação nenhuma —
    // foi assim que o protótipo deste harness deu falso negativo.
    RunLoop.main.run(until: Date().addingTimeInterval(0.35))
    t.montar(cena)
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    if let foco = t.foco { cena.vm.focar(foco) }
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))

    let escala = Int(janela.backingScaleFactor)
    // Quadro zero: o estado ANTES do disparo. Sem ele, uma moldura que muda de
    // tamanho na mesma runloop (sem animação) apareceria como "altura única" e
    // seria confundida com transição que não aconteceu.
    var quadros: [Quadro] = [medir(host, escala: escala, etiqueta: "\(t.nome)-000")]
    var pendentes = t.passos
    let fimDosPassos = (t.passos.map(\.0).max() ?? 0) + observacao
    let inicio = Date()
    while true {
        let agora = Date().timeIntervalSince(inicio)
        while let p = pendentes.first, p.0 <= agora {
            p.1(cena)
            pendentes.removeFirst()
        }
        if agora >= fimDosPassos { break }
        RunLoop.main.run(until: Date().addingTimeInterval(passoDeFoto))
        quadros.append(medir(host, escala: escala,
                             etiqueta: String(format: "%@-%03d", t.nome, quadros.count)))
    }
    janela.orderOut(nil as Any?)
    janela.contentView = nil
    return Resultado(nome: t.nome, familia: t.familia, quadros: quadros,
                     duracao: Date().timeIntervalSince(inicio))
}

/// Controle NEGATIVO do detector: uma moldura de 100 pt com conteúdo que desce
/// até 200 pt. Se `medir` não acusar corte aqui, o "0 de N" da varredura não
/// valeria nada — seria um detector cego, não uma ausência de defeito.
@MainActor
func controleDoDetector() -> Quadro {
    let raiz = ZStack(alignment: .top) {
        Color(red: 1, green: 0, blue: 1)
        ZStack(alignment: .top) {
            Rectangle().fill(Color.black).frame(width: 300, height: 100)
            Color.white.frame(width: 60, height: 60).padding(.top, 140)
        }
        .frame(width: 300, height: 200, alignment: .top)
    }
    .frame(width: janelaLargura, height: janelaAltura)
    let host = NSHostingView(rootView: AnyView(raiz))
    host.frame = NSRect(x: 0, y: 0, width: janelaLargura, height: janelaAltura)
    let janela = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
    janela.contentView = host
    janela.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    janela.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    let q = medir(host, escala: Int(janela.backingScaleFactor),
                  etiqueta: "controle-do-detector")
    janela.orderOut(nil as Any?)
    janela.contentView = nil
    return q
}

// MARK: - Execução

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

MainActor.assumeIsolated {

Cena.isolarDisco()

// Controle positivo. Se a animação não correr na janela fora da tela, TODA foto
// sai já no estado final e o harness devolveria "não reproduziu" sem ter medido
// nada. O controle troca o `mode` (.music → .closed → .music), o único gatilho
// com `.animation(morphAnimation, value: mode)` amarrada, e exige ver alturas
// intermediárias — sem isso não há o que medir e o harness aborta.
let controle = Transicao(
    nome: "controle-positivo-mode", familia: "controle",
    montar: { c in
        LinkPreview.shared.abrir(linkDeTeste, on: 1)
        c.vm.expanded = true
    },
    foco: .link,
    passos: [(0, { $0.vm.setExpandedDirect(false) }),
             (0.60, { $0.vm.setExpandedDirect(true) })])

let qd = controleDoDetector()
print(String(format: "controle do detector: corte=%@ excedente=%.1f pt (esperado ~100 pt)",
             qd.temCorte ? "sim" : "NÃO", qd.excedentePt))
guard qd.temCorte else {
    print("FALHOU: o detector não enxerga moldura menor que conteúdo — nada do resto vale.")
    exit(1)
}

// Controle do estado FECHADO, sem transição nenhuma: a pilulinha parada tem
// que aparecer em toda foto. É o que separa "o notch sumiu por um quadro" de
// "o `cacheDisplay` devolveu buffer em branco" quando o card fecha.
let rf = rodar(Transicao(nome: "controle-fechado-parado", familia: "controle",
                         montar: { c in c.vm.expanded = false },
                         passos: [(0, { _ in })]))
print("controle do fechado parado: alturas \(rf.alturas)")

let rc = rodar(controle)
print("controle positivo: \(rc.quadros.count) quadros, "
      + "\(rc.alturasDistintas) alturas de moldura distintas "
      + "(\(rc.alturas.min() ?? -1)–\(rc.alturas.max() ?? -1) pt)")
if verboso { print("   alturas: \(rc.alturas)") }
guard rc.alturasDistintas >= 5 else {
    print("FALHOU: a animação não corre nesta janela — o harness não mediria nada.")
    exit(1)
}

var resultados: [Resultado] = []
for t in transicoes {
    let r = rodar(t)
    resultados.append(r)
    let rotulo = r.nome.padding(toLength: 32, withPad: " ", startingAt: 0)
    print(String(format: "  %@ quadros=%2d alturas=%2d corte=%2d excedente_max=%6.1f pt "
                         + "lacuna_topo_max=%5.1f pt",
                 rotulo, r.quadros.count, r.alturasDistintas, r.quadrosComCorte,
                 r.excedenteMaxPt, r.lacunaTopoMaxPt))
    if verboso { print("     alturas: \(r.alturas)") }
}

let comCorte = resultados.filter { $0.quadrosComCorte > 0 }
print("")
print("Reduced Motion do sistema: \(reducedMotionDoSistema ? "ligado" : "desligado")"
      + " — a outra posição NÃO foi varrida (ver cabeçalho do Motor)")
print("combinações rodadas: \(resultados.count)")
print("famílias: \(Set(resultados.map(\.familia)).sorted().joined(separator: ", "))")
let hzMedio = resultados.map(\.hz).reduce(0, +) / Double(resultados.count)
print(String(format: "cadência média das fotos: %.1f Hz — um corte de UM quadro a 60 Hz "
                     + "pode passar entre duas fotos", hzMedio))
let vaziosComConteudo = resultados.flatMap(\.quadros).filter(\.molduraSumiuComConteudo).count
let vaziosLimpos = resultados.flatMap(\.quadros).filter { $0.vazio && $0.fimConteudo < 0 }.count
print("quadros sem moldura NENHUMA: \(vaziosLimpos + vaziosComConteudo)"
      + " (com conteúdo desenhado: \(vaziosComConteudo))")
print("provas dos quadros suspeitos em \(pastaDeProvas)")
print("com moldura menor que o conteúdo: \(comCorte.count)")
for r in comCorte {
    print(String(format: "  %@ — %d/%d quadros, excedente máximo %.1f pt, lacuna de topo %.1f pt",
                 r.nome, r.quadrosComCorte, r.quadros.count,
                 r.excedenteMaxPt, r.lacunaTopoMaxPt))
}

}
