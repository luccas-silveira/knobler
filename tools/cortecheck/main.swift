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
import Combine
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
    let q = classificar(base: base, bpr: rep.bytesPerRow, bpp: rep.bitsPerPixel / 8,
                        largura: rep.pixelsWide, altura: rep.pixelsHigh, escala: escala)
    if q.temCorte || q.vazio { gravarProva(rep, etiqueta: etiqueta) }
    if q.vazio { examinarVazio(host, escala: escala, etiqueta: etiqueta) }
    return q
}

/// Segunda opinião sobre um quadro que saiu sem moldura NENHUMA, no MESMO giro
/// de runloop — nada no modelo muda entre as três fotos abaixo, então o que
/// diferir entre elas é do caminho de captura, não do desenho.
///
/// 1. `cacheDisplay` de novo, num bitmap novo: se o notch aparecer aqui, o vazio
///    era do buffer, não da árvore.
/// 2. `CALayer.render(in:)`, que é outro caminho e desenha a árvore de MODELO
///    (o estado final da animação, não o interpolado): se aqui aparecer e no
///    `cacheDisplay` não, a subárvore existe e a captura a perdeu.
@MainActor
func examinarVazio(_ host: NSView, escala: Int, etiqueta: String) {
    vaziosExaminados += 1
    if let rep2 = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: rep2)
        if let b2 = rep2.bitmapData {
            let q2 = classificar(base: b2, bpr: rep2.bytesPerRow, bpp: rep2.bitsPerPixel / 8,
                                 largura: rep2.pixelsWide, altura: rep2.pixelsHigh, escala: escala)
            if !q2.vazio { vaziosQueSumiramNaSegundaFoto += 1 }
        }
    }
    // A foto por camada custa ~200 ms (desenha os 1800×1280 px na CPU) e come a
    // cadência das fotos justamente nas transições onde mais interessa amostrar.
    // ponytail: teto de 8 por corrida — chega pra decidir a pergunta dos magenta;
    // se um dia for preciso contorno por transição, o teto vira por transição.
    guard fotosPorCamadaFeitas < tetoDeFotosPorCamada,
          ProcessInfo.processInfo.environment["CORTECHECK_SEM_CAMADA"] == nil else { return }
    fotosPorCamadaFeitas += 1
    let qc = fotoPorCamada(host, escala: escala)
    if !qc.vazio { vaziosComCamadaDesenhada += 1 }
}

/// Foto pelo caminho da camada, independente do `cacheDisplay`.
@MainActor
func fotoPorCamada(_ host: NSView, escala: Int) -> Quadro {
    let vazio = Quadro(topoMoldura: 0, fimMoldura: -1, fimConteudo: -1, escala: escala)
    let largura = Int(host.bounds.width) * escala
    let altura = Int(host.bounds.height) * escala
    guard largura > 0, altura > 0, let camada = host.layer,
          let ctx = CGContext(data: nil, width: largura, height: altura, bitsPerComponent: 8,
                              bytesPerRow: largura * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return vazio }
    ctx.scaleBy(x: CGFloat(escala), y: CGFloat(escala))
    // `render(in:)` desenha na orientação da camada; a classificação conta as
    // linhas de cima pra baixo, então o eixo Y é espelhado aqui.
    ctx.translateBy(x: 0, y: host.bounds.height)
    ctx.scaleBy(x: 1, y: -1)
    camada.render(in: ctx)
    guard let base = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return vazio }
    return classificar(base: base, bpr: largura * 4, bpp: 4,
                       largura: largura, altura: altura, escala: escala)
}

/// Classifica um bitmap RGBA já desenhado. Extraído de `medir` para que a
/// segunda foto e a foto por camada usem exatamente o mesmo critério de pixel.
func classificar(base: UnsafeMutablePointer<UInt8>, bpr: Int, bpp: Int,
                 largura: Int, altura: Int, escala: Int) -> Quadro {
    var topoMoldura = -1, fimMoldura = -1, fimConteudo = -1

    for y in 0..<altura {
        var temMoldura = false, temConteudo = false
        var x = 0
        while x < largura {
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
    return Quadro(topoMoldura: max(topoMoldura, 0), fimMoldura: fimMoldura,
                  fimConteudo: fimConteudo, escala: escala)
}

/// Contadores da investigação dos quadros magenta. Cobrem TODO quadro vazio da
/// corrida, controles inclusive — é nos controles que eles aparecem mais.
@MainActor
var vaziosExaminados = 0
@MainActor
var vaziosQueSumiramNaSegundaFoto = 0
@MainActor
var vaziosComCamadaDesenhada = 0
let tetoDeFotosPorCamada = 8
@MainActor
var fotosPorCamadaFeitas = 0

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
    /// A janela que hospeda a view. Preenchida pelo `rodar` — é por ela que as
    /// transições de AMBIENTE (orderOut, setFrame) mexem no que o app mexe.
    var janela: NSWindow?
    /// Assinatura de `AppSettings.objectWillChange` → `applyVisibility`, a
    /// mesma de `KnoblerApp.swift:377`-`378`. Uma por transição: o `rodar` a
    /// desfaz no fim, senão a transição seguinte herdaria o assinante.
    var visibilityCancellable: AnyCancellable?
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
// MARK: - Eventos de ambiente

/// Registro de todo evento de ambiente dirigido. Sem ele, um `orderOut` que não
/// esconde nada devolveria um zero falso: o harness teria medido a ausência do
/// evento, não a ausência do defeito.
struct EventoDirigido {
    let transicao: String
    let chamada: String
    let antes: String
    let depois: String
    var mudou: Bool { antes != depois }
}

@MainActor
var eventosDirigidos: [EventoDirigido] = []
@MainActor
var transicaoCorrente = "—"

@MainActor
func estadoDaJanela(_ j: NSWindow) -> String {
    String(format: "visivel=%@ frame=%.0fx%.0f@%.0f,%.0f", j.isVisible ? "sim" : "nao",
           j.frame.width, j.frame.height, j.frame.origin.x, j.frame.origin.y)
}

/// Dirige um evento de ambiente e grava o estado observável da janela antes e
/// depois — a prova de que o evento aconteceu de verdade.
@MainActor
func evento(_ c: Cena, _ chamada: String, _ acao: (NSWindow) -> Void) {
    guard let j = c.janela else { return }
    let antes = estadoDaJanela(j)
    acao(j)
    let depois = estadoDaJanela(j)
    eventosDirigidos.append(EventoDirigido(transicao: transicaoCorrente, chamada: chamada,
                                           antes: antes, depois: depois))
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

    Transicao(nome: "incoming-perde-a-foto", familia: "lista3-incoming",
              montar: { c in
                  c.vm.showIncoming(.init(peerID: "p1", name: "Marina",
                                          text: "Olha isso", allowReply: true,
                                          mediaFile: nil, mediaHeight: 200))
              },
              passos: [(0, { c in
                  c.vm.incoming = .init(peerID: "p1", name: "Marina",
                                        text: "Olha isso", allowReply: true,
                                        mediaFile: nil, mediaHeight: 0)
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

    // ---- Ambiente: o que acontece com a JANELA, não com a interface. Os
    // pontos de entrada são os mesmos do app — `placeWindows`
    // (`Knobler/KnoblerApp.swift:1195`) faz `setFrame(_:display: true)` seguido
    // de `orderFrontRegardless()`, e `orderOut(nil)` (`:1205`) some com a
    // janela. Ver os limites na medição 003.1: este worktree NÃO tem
    // observador de troca de Space nem de sono.
    Transicao(nome: "ambiente-orderout-volta-fechado", familia: "ambiente",
              montar: { c in c.vm.expanded = false },
              passos: [(0, { c in evento(c, "orderOut", { $0.orderOut(nil as Any?) }) }),
                       (0.30, { c in evento(c, "orderFrontRegardless", { $0.orderFrontRegardless() }) })]),

    Transicao(nome: "ambiente-orderout-volta-aberto", familia: "ambiente",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { c in evento(c, "orderOut", { $0.orderOut(nil as Any?) }) }),
                       (0.30, { c in evento(c, "orderFrontRegardless", { $0.orderFrontRegardless() }) })]),

    Transicao(nome: "ambiente-orderout-durante-morph", familia: "ambiente",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.05, { c in evento(c, "orderOut", { $0.orderOut(nil as Any?) }) }),
                       (0.20, { c in evento(c, "orderFrontRegardless", { $0.orderFrontRegardless() }) }),
                       (0.60, { $0.vm.setExpandedDirect(true) })]),

    // A forma que o brief descreve pra troca de Space: esconder, esperar 0,35 s,
    // devolver. Este worktree não tem esse observador (ver medição), então o que
    // roda aqui é a FORMA do evento, não uma chamada do app.
    Transicao(nome: "ambiente-espaco-simulado", familia: "ambiente",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { c in evento(c, "orderOut", { $0.orderOut(nil as Any?) }) }),
                       (0.35, { c in evento(c, "orderFrontRegardless", { $0.orderFrontRegardless() }) })]),

    // `placeWindows` literal: setFrame com o MESMO frame e display: true,
    // seguido de orderFrontRegardless no mesmo giro. É o que
    // `didChangeScreenParametersNotification` dispara com a tela igual.
    Transicao(nome: "ambiente-placewindows-parado", familia: "ambiente",
              montar: { c in c.vm.expanded = false },
              passos: [(0, { c in placeWindowsFalso(c) })]),

    Transicao(nome: "ambiente-placewindows-durante-morph", familia: "ambiente",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.05, { c in placeWindowsFalso(c) }),
                       (0.60, { $0.vm.setExpandedDirect(true) })]),

    // Mudança de resolução, o lado que dá pra simular: a janela muda de origem
    // (a tela ficou de outro tamanho) sem tocar no hardware.
    Transicao(nome: "ambiente-setframe-move-origem", familia: "ambiente",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { c in
                           guard let j = c.janela else { return }
                           let f = j.frame.offsetBy(dx: 137, dy: -211)
                           evento(c, "setFrame(origem)", { $0.setFrame(f, display: true) })
                       }),
                       (0.50, { c in
                           guard let j = c.janela else { return }
                           let f = j.frame.offsetBy(dx: -137, dy: 211)
                           evento(c, "setFrame(origem de volta)", { $0.setFrame(f, display: true) })
                       })]),

    // O outro lado da mudança de resolução: a janela muda de TAMANHO com a
    // view viva dentro. É o caso que o `placeWindows` evita de propósito
    // (ponytail em `KnoblerApp.swift`: "redimensionar durante animação é jank").
    Transicao(nome: "ambiente-setframe-muda-tamanho", familia: "ambiente",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { c in
                           guard let j = c.janela else { return }
                           let f = NSRect(x: j.frame.minX, y: j.frame.minY,
                                          width: 700, height: janelaAltura + 260)
                           evento(c, "setFrame(tamanho)", { $0.setFrame(f, display: true) })
                       }),
                       (0.50, { c in
                           guard let j = c.janela else { return }
                           let f = NSRect(x: j.frame.minX, y: j.frame.minY,
                                          width: janelaLargura, height: janelaAltura)
                           evento(c, "setFrame(tamanho de volta)", { $0.setFrame(f, display: true) })
                       })]),
    // ---- 004: o código que o usuário roda de verdade. `applyVisibility`
    // (`KnoblerApp.swift:1073`), o `fullscreenDisplays()` que ela varre a cada
    // chamada, e os TRÊS chamadores com as cadências deles: o fim do
    // `placeWindows` (`:1269`), 0,35 s depois de cada troca de Space
    // (`:371`-`374`) e CADA mudança em `AppSettings` (`:377`-`378`).

    // Chamador 3, parado: o notch na pilulinha e os Ajustes mudando. Cada
    // mudança ordena a janela pra frente OUTRA VEZ, já visível, e varre a lista
    // de janelas do sistema antes.
    Transicao(nome: "real-ajustes-parado", familia: "real",
              montar: { c in
                  c.vm.expanded = false
                  assinarAjustes(c)
              },
              passos: (0..<12).map { i -> (TimeInterval, Acao) in
                  (Double(i) * 0.05, { _ in mudarUmAjuste() })
              }),

    // O mesmo, com a mola do morph correndo por cima: é a combinação que o
    // usuário produz mexendo nos Ajustes com o card abrindo ou fechando.
    Transicao(nome: "real-ajustes-durante-morph", familia: "real",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
                  assinarAjustes(c)
              },
              foco: .link,
              passos: [(0, { $0.vm.setExpandedDirect(false) })]
                  + (0..<16).map { i -> (TimeInterval, Acao) in
                      (0.02 + Double(i) * 0.02, { _ in mudarUmAjuste() })
                  }
                  + [(0.90, { $0.vm.setExpandedDirect(true) })]),

    // A rajada: 30 mudanças no MESMO giro de runloop (o que um campo de texto
    // ou um slider dos Ajustes faz). Os 30 `async` caem juntos no giro
    // seguinte → 30 `applyVisibility`, 30 varreduras da lista de janelas e 30
    // `orderFrontRegardless` de uma vez, no meio do morph.
    Transicao(nome: "real-ajustes-rajada", familia: "real",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
                  assinarAjustes(c)
              },
              foco: .link,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.05, { _ in for _ in 0..<30 { mudarUmAjuste() } }),
                       (0.90, { $0.vm.setExpandedDirect(true) })]),

    // Chamador 2: a troca de Space. O app não esconde nada na troca em si —
    // ele espera 0,35 s e roda `applyVisibility`, que decide pelo que a lista
    // de janelas disser. Aqui a costura força o ramo do `orderOut` (entrou em
    // tela cheia) e depois o solta (saiu), com o mesmo atraso das duas vezes.
    Transicao(nome: "real-espaco-entra-telacheia", familia: "real",
              montar: { c in c.vm.expanded = false },
              passos: [(0, { _ in telaCheiaForcada = true }),
                       (0.35, { c in applyVisibilityReal(c) }),
                       (0.90, { _ in telaCheiaForcada = false }),
                       (1.25, { c in applyVisibilityReal(c) })]),

    // O `applyVisibility` atrasado caindo DENTRO da mola: a troca de Space
    // acontece a 0,05 s do card começar a fechar, e o efeito dela chega a
    // 0,40 s — no meio da animação.
    Transicao(nome: "real-espaco-durante-morph", familia: "real",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.40, { c in applyVisibilityReal(c) }),
                       (0.90, { $0.vm.setExpandedDirect(true) }),
                       (1.30, { c in applyVisibilityReal(c) })]),

    // Chamador 1: o fim do `placeWindows` — `setFrame(_:display: true)` por
    // tela (`KnoblerApp.swift:1256`) e, no fim, `applyVisibility()` (`:1269`).
    // UM `orderFrontRegardless`, e ele vem de dentro do `applyVisibility`
    // (`:1077`, o único do arquivo). O `placeWindowsFalso` que esta transição
    // reaproveita é a forma PRÉ-`f8684aa`, com um `orderFrontRegardless`
    // próprio: ela dirige um a mais que o app. Ver os limites da medição 004.
    Transicao(nome: "real-placewindows-applyvisibility", familia: "real",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { $0.vm.setExpandedDirect(false) }),
                       (0.05, { c in placeWindowsReal(c) }),
                       (0.60, { $0.vm.setExpandedDirect(true) }),
                       (0.65, { c in placeWindowsReal(c) })]),

    // O interruptor "ocultar em tela cheia" nos Ajustes: ele é ao mesmo tempo
    // uma mudança de `AppSettings` (dispara `applyVisibility`) e o que decide
    // se `fullscreenDisplays()` chega a ser chamado.
    Transicao(nome: "real-telacheia-liga-desliga", familia: "real",
              montar: { c in
                  c.vm.expanded = false
                  assinarAjustes(c)
              },
              passos: (0..<4).map { i -> (TimeInterval, Acao) in
                  (Double(i) * 0.40, { _ in
                      AppSettings.shared.ocultarEmTelaCheia.toggle()
                  })
              }),

    // Só o syscall, sem tocar na janela: `CGWindowListCopyWindowInfo` na main
    // thread a 33 Hz enquanto a mola corre. Separa "a varredura atrapalha o
    // desenho" de "ordenar a janela atrapalha o desenho".
    Transicao(nome: "real-fullscreendisplays-varredura", familia: "real",
              montar: { c in
                  LinkPreview.shared.abrir(linkDeTeste, on: 1)
                  c.vm.expanded = true
              },
              foco: .link,
              passos: [(0, { $0.vm.setExpandedDirect(false) })]
                  + (0..<40).map { i -> (TimeInterval, Acao) in
                      (0.02 + Double(i) * 0.03, { _ in
                          let t0 = Date()
                          telasCheiasVistasDeVerdade.formUnion(telasEmTelaCheia())
                          custoFullscreenDisplaysMs.append(
                              Date().timeIntervalSince(t0) * 1000)
                      })
                  }
                  + [(1.30, { $0.vm.setExpandedDirect(true) })]),
]

// MARK: - O código real: applyVisibility, fullscreenDisplays e os três chamadores

/// O display que a cena finge ter. `applyVisibility` decide POR display
/// (`notches` é um dicionário por `CGDirectDisplayID`); a cena tem uma janela
/// só, então ela é o display 1.
// ponytail: fixo em 1 — nesta máquina o `CGDirectDisplayID` da tela principal
// É 1, então o ramo real da costura bate por sorte, não por construção. Numa
// máquina onde não for, só a costura `telaCheiaForcada` alcança o `orderOut`.
// Upgrade: ler o ID de `NSScreen.main` como o `Self.displayID(of:)` do app faz.
let displayDaCena: CGDirectDisplayID = 1

/// A costura da medição, e a única parte da decisão que é encenada: liga o
/// ramo do `orderOut` sem sequestrar um Space de verdade. Entrar em tela cheia
/// pra valer mexeria na sessão gráfica do usuário.
@MainActor
var telaCheiaForcada = false

@MainActor
var custoFullscreenDisplaysMs: [Double] = []
@MainActor
var telasCheiasVistasDeVerdade: Set<CGDirectDisplayID> = []
@MainActor
var chamadasApplyVisibility = 0

/// Réplica LITERAL de `AppDelegate.fullscreenDisplays()`
/// (`Knobler/KnoblerApp.swift:1040`). O `CGWindowListCopyWindowInfo` é o mesmo
/// syscall que o app faz, na main thread, a cada chamada — é o que esta
/// medição quer cronometrar. A única diferença: no app o `meuPID` exclui as
/// janelas do próprio Knobler; aqui o harness é outro processo, então o
/// Knobler de verdade (se estiver rodando) passaria pelo filtro de PID — mas
/// não pelo de camada, porque `NotchWindow` é `.mainMenu + 3` e o filtro exige
/// camada 0.
@MainActor
func telasEmTelaCheia() -> Set<CGDirectDisplayID> {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let janelas = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]],
          let primeira = NSScreen.screens.first else { return [] }
    let meuPID = ProcessInfo.processInfo.processIdentifier

    let cheias: [CGRect] = janelas.compactMap { j in
        guard (j[kCGWindowLayer as String] as? Int) == 0,
              (j[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              (j[kCGWindowOwnerPID as String] as? Int32) != meuPID,
              let b = j[kCGWindowBounds as String] as? [String: CGFloat],
              let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
        else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
    guard !cheias.isEmpty else { return [] }

    var ids = Set<CGDirectDisplayID>()
    for screen in NSScreen.screens {
        let f = screen.frame
        let cg = CGRect(x: f.minX, y: primeira.frame.maxY - f.maxY,
                        width: f.width, height: f.height)
        if cheias.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(cg) }) {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            ids.insert(screen.deviceDescription[key] as? CGDirectDisplayID ?? 0)
        }
    }
    return ids
}

/// Réplica de `AppDelegate.applyVisibility()` (`Knobler/KnoblerApp.swift:1073`):
/// lê a chave dos Ajustes, varre as janelas do sistema e ordena TODAS as
/// janelas de notch — `orderOut` na tela em tela cheia, `orderFrontRegardless`
/// nas outras. Repare que o ramo de baixo ordena pra frente uma janela que já
/// está visível, toda vez, e é esse o caminho que roda a cada mudança de Ajuste.
@MainActor
func applyVisibilityReal(_ c: Cena) {
    let t0 = Date()
    let cheias = AppSettings.shared.ocultarEmTelaCheia ? telasEmTelaCheia() : []
    if AppSettings.shared.ocultarEmTelaCheia {
        custoFullscreenDisplaysMs.append(Date().timeIntervalSince(t0) * 1000)
        telasCheiasVistasDeVerdade.formUnion(cheias)
    }
    chamadasApplyVisibility += 1
    let escondeEstaTela = cheias.contains(displayDaCena) || telaCheiaForcada
    if escondeEstaTela {
        evento(c, "applyVisibility→orderOut", { $0.orderOut(nil as Any?) })
    } else {
        evento(c, "applyVisibility→orderFrontRegardless", { $0.orderFrontRegardless() })
    }
}

/// Chamador 1: o fim do `placeWindows` — `setFrame(_:display: true)` por tela
/// (`KnoblerApp.swift:1256`) e, no fim, `applyVisibility()` (`:1269`). O
/// `placeWindowsFalso` herdado da 003.1 traz um `orderFrontRegardless` próprio
/// que o `placeWindows` de hoje NÃO tem — dirige um evento a mais que o app.
@MainActor
func placeWindowsReal(_ c: Cena) {
    placeWindowsFalso(c)
    applyVisibilityReal(c)
}

/// Chamador 3: `AppSettings.objectWillChange` → `DispatchQueue.main.async` →
/// `applyVisibility` (`KnoblerApp.swift:377`-`378`). A assinatura é a de
/// verdade, com o mesmo hop de runloop.
@MainActor
func assinarAjustes(_ c: Cena) {
    c.visibilityCancellable = AppSettings.shared.objectWillChange
        .sink { [weak c] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let c else { return }
                    applyVisibilityReal(c)
                }
            }
        }
}

/// Uma mudança em `AppSettings` que não muda nada na tela: o que interessa é o
/// `objectWillChange`, que é o gatilho real. `formatModel` é texto de um campo
/// dos Ajustes que a `NotchView` não desenha — mas a `NotchView` observa o
/// `AppSettings.shared` inteiro (`NotchView.swift:17`), então o corpo dela é
/// reavaliado do mesmo jeito que no app.
@MainActor
var mudancasDeAjuste = 0
@MainActor
func mudarUmAjuste() {
    mudancasDeAjuste += 1
    AppSettings.shared.formatModel = "cortecheck-\(mudancasDeAjuste)"
}

/// Valores originais dos Ajustes mexidos, pra devolver no fim da corrida. O
/// harness não tem bundle id, então `UserDefaults.standard` dele mora em
/// `~/Library/Preferences/cortecheck.plist` — não encosta no
/// `com.zoi.knobler.plist` do usuário. A devolução é cinto e suspensório.
@MainActor
let formatModelOriginal = AppSettings.shared.formatModel
@MainActor
let ocultarEmTelaCheiaOriginal = AppSettings.shared.ocultarEmTelaCheia

/// O `placeWindows` do app como ele era ANTES do `f8684aa`: `setFrame(_:display:
/// true)` e `orderFrontRegardless()` no mesmo giro (eram as linhas 1195-1196).
/// No código medido o `orderFrontRegardless` saiu daqui e mora só no
/// `applyVisibility` (`KnoblerApp.swift:1077`). Mantido como está de propósito:
/// mudá-lo mudaria os 87 eventos e o hash do determinismo da medição 004.
@MainActor
func placeWindowsFalso(_ c: Cena) {
    guard let j = c.janela else { return }
    let f = j.frame
    evento(c, "setFrame(igual)+orderFrontRegardless", {
        $0.setFrame(f, display: true)
        $0.orderFrontRegardless()
    })
}

// MARK: - Motor

let janelaLargura: CGFloat = 900
let janelaAltura: CGFloat = 640
/// Quanto tempo a observação dura DEPOIS do último passo. Subiu de 0,8 s para
/// 1,6 s na medição 003.1: as transições que fecham e reabrem o card fotografam
/// a 4 Hz (o `cacheDisplay` do card de 530 pt custa ~200 ms), e com 0,8 s os
/// quadros vazios caíam no FIM da série — sem um quadro depois deles, não dava
/// para dizer se a árvore voltava a desenhar.
let observacao: TimeInterval = 1.6
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
    /// A série terminou sem a árvore voltar a desenhar. É o caso que mais
    /// parece o sintoma relatado: não é um quadro que pisca, é um estado.
    var terminouVazio: Bool { quadros.last?.vazio ?? false }

    /// Onde cada quadro vazio cai na curva de altura: entre um vizinho menor e
    /// um maior (subida), o contrário (descida), ou entre alturas iguais
    /// (patamar). Uma mola que passasse por zero só produziria vazio em
    /// DESCIDA; vazio em subida ou em patamar não sai de encolhimento.
    var contornoDosVazios: (subida: Int, descida: Int, patamar: Int, borda: Int) {
        var r = (subida: 0, descida: 0, patamar: 0, borda: 0)
        for (i, q) in quadros.enumerated() where q.vazio {
            let antes = quadros[..<i].last(where: { !$0.vazio })?.alturaMolduraPt
            let depois = quadros[(i + 1)...].first(where: { !$0.vazio })?.alturaMolduraPt
            // "borda" = a série acabou (ou começou) vazia, e aí não há vizinho
            // dos dois lados pra dizer se o vazio estava subindo ou descendo.
            guard let a = antes, let d = depois else { r.borda += 1; continue }
            if d > a { r.subida += 1 } else if d < a { r.descida += 1 } else { r.patamar += 1 }
        }
        return r
    }
}

/// Altura da moldura no mesmo instante, medida pelos dois caminhos de captura.
/// Preenchida pelo controle da camada.
@MainActor
var camadaControle: (porCacheDisplay: Double, porCamada: Double)?

@MainActor
func rodar(_ t: Transicao, deslocamento: CGFloat = 0, conferirCamada: Bool = false) -> Resultado {
    transicaoCorrente = t.nome
    telaCheiaForcada = false
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
            // `deslocamento` só é usado pelo controle do desvio: empurra a
            // NotchView DE VERDADE 60 pt pra baixo, sem tocar em Knobler/.
            .padding(.top, deslocamento)
    }
    // Ancorada no TOPO em vez de tamanho fixo: quando um evento de ambiente
    // muda o tamanho da janela, um conteúdo centralizado desceria junto e a
    // lacuna de topo acusaria corte que é só layout do envelope. Com a janela
    // no tamanho de sempre isto é idêntico ao `.frame(width:height:)` anterior.
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

    let host = NSHostingView(rootView: AnyView(raiz))
    host.frame = NSRect(x: 0, y: 0, width: janelaLargura, height: janelaAltura)
    // O painel de VERDADE, não uma NSWindow comum: `applyVisibility` ordena
    // `NotchWindow`s (nível `.mainMenu + 3`, `isOpaque = false`,
    // `.canJoinAllSpaces`), e a medição 003.1 deixou isso escrito como o limite
    // a atacar se um evento de janela virasse suspeito. Virou.
    let janela = NotchWindow(contentRect: host.frame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
    janela.contentView = host
    cena.janela = janela
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
    if conferirCamada {
        camadaControle = (quadros[0].alturaMolduraPt, fotoPorCamada(host, escala: escala).alturaMolduraPt)
    }
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
    cena.visibilityCancellable = nil
    telaCheiaForcada = false
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
    // Quatro trocas de `mode`, não uma: com um par só o número de alturas
    // distintas ficava em 5–8 contra uma trava de 5, e um dia de máquina
    // ocupada derrubaria o harness com um "a animação não corre" falso.
    passos: [(0, { $0.vm.setExpandedDirect(false) }),
             (0.60, { $0.vm.setExpandedDirect(true) }),
             (1.40, { $0.vm.setExpandedDirect(false) }),
             (2.00, { $0.vm.setExpandedDirect(true) })])

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
                         passos: [(0, { _ in })]),
               conferirCamada: true)
print("controle do fechado parado: alturas \(rf.alturas)")

// Controle da SEGUNDA CÂMERA. A pergunta dos quadros magenta é "a captura
// perdeu o desenho ou não havia desenho", e ela só se responde com um caminho
// de captura independente. Este exige que `CALayer.render(in:)` meça a MESMA
// pilulinha que o `cacheDisplay` mede num quadro que ninguém discute. Se ele
// falhar, a foto por camada é cega e o veredicto sobre os magenta cai com ela.
let camadaOK: Bool = {
    guard let c = camadaControle else { return false }
    return c.porCamada > 0 && abs(c.porCamada - c.porCacheDisplay) <= 2
}()
print(String(format: "controle da camada (2ª câmera): cacheDisplay=%.1f pt, camada=%.1f pt — %@",
             camadaControle?.porCacheDisplay ?? -1, camadaControle?.porCamada ?? -1,
             camadaOK ? "concordam" : "NÃO CONCORDAM (a foto por camada é cega)"))

// Controle do DESVIO na view real. O controle do detector acima é uma view
// sintética: prova que `medir` sabe somar, não que enxerga defeito na
// `NotchView`. Este roda a `NotchView` de verdade empurrada 60 pt pra baixo e
// exige que a lacuna de topo saia 60,0 pt — a mesma assinatura que a injeção de
// moldura deslocada produz. Sem tocar em Knobler/*.swift: o empurrão é um
// `.padding(.top,)` no envelope do harness.
let desvio: CGFloat = 60
let rdv = rodar(Transicao(nome: "controle-do-desvio-view-real", familia: "controle",
                          montar: { c in c.vm.expanded = false },
                          passos: [(0, { _ in })]),
                deslocamento: desvio)
print(String(format: "controle do desvio na view real: lacuna_topo_max=%.1f pt "
                     + "(esperado %.1f), corte=%@",
             rdv.lacunaTopoMaxPt, Double(desvio), rdv.quadrosComCorte > 0 ? "sim" : "NÃO"))
guard abs(rdv.lacunaTopoMaxPt - Double(desvio)) < 1, rdv.quadrosComCorte == rdv.quadros.count else {
    print("FALHOU: o detector não acusa moldura deslocada na NotchView real.")
    exit(1)
}

let rc = rodar(controle)
print("controle positivo: \(rc.quadros.count) quadros, "
      + "\(rc.alturasDistintas) alturas de moldura distintas "
      + "(\(rc.alturas.min() ?? -1)–\(rc.alturas.max() ?? -1) pt)")
if verboso { print("   alturas: \(rc.alturas)") }
// Limiar 3, e ele É derivado: a pergunta do controle é binária — a animação
// avança ou não. Duas alturas (antes e depois) já provariam que o estado mudou;
// a TERCEIRA é a que prova que houve um valor NO MEIO, ou seja, interpolação.
// Pedir mais que isso é pedir uma cadência de amostragem que a máquina não
// garante: o 5 anterior não vinha de lugar nenhum e chegou a medir 6 num dia
// com mais fotos e menos alturas (a amostragem cai em platôs da mola).
guard rc.alturasDistintas >= 3 else {
    print("FALHOU: a animação não corre nesta janela (menos de 3 alturas distintas) — "
          + "o harness não mediria nada.")
    exit(1)
}

// Filtro de família: roda uma família só, SEM pular nenhum controle — o
// `## Verificação` da medição precisa de um comando que caiba num minuto.
let familiaFiltro = ProcessInfo.processInfo.environment["CORTECHECK_FAMILIA"]
// Controle do AMBIENTE: a pilulinha parada com a janela FORA de ordem. Se o
// `cacheDisplay` parar de devolver o desenho só por a janela estar escondida,
// todo quadro medido durante um `orderOut` sairia vazio por artefato do
// instrumento — e a família `ambiente` inteira mediria o instrumento.
let passosDoOrderOut: [(TimeInterval, Acao)] = [
    (0, { c in evento(c, "orderOut", { $0.orderOut(nil as Any?) }) }),
    (0.30, { c in evento(c, "orderFrontRegardless", { $0.orderFrontRegardless() }) }),
]
let rao = rodar(Transicao(nome: "controle-ambiente-orderout-parado", familia: "controle",
                          montar: { c in c.vm.expanded = false },
                          passos: [(0, { c in evento(c, "orderOut", { $0.orderOut(nil as Any?) }) })]))
print("controle do ambiente (orderOut parado): alturas \(rao.alturas)")
guard rao.alturas.allSatisfy({ $0 == 32 }), rao.quadrosComCorte == 0 else {
    print("FALHOU: com a janela fora de ordem o `cacheDisplay` deixa de devolver o "
          + "desenho — a família `ambiente` mediria o instrumento, não o app.")
    exit(1)
}

// Controle do DESVIO dentro do ambiente. O controle do desvio lá em cima prova
// que o detector enxerga na NotchView parada; este prova que ele continua
// enxergando ATRAVESSANDO o evento — se o orderOut cegasse a medida, o zero da
// família seria zero de instrumento.
let rad = rodar(Transicao(nome: "controle-ambiente-desvio", familia: "controle",
                          montar: { c in c.vm.expanded = false },
                          passos: passosDoOrderOut),
                deslocamento: desvio)
print(String(format: "controle do desvio atravessando o orderOut: lacuna_topo_max=%.1f pt "
                     + "(esperado %.1f), quadros com corte=%d/%d",
             rad.lacunaTopoMaxPt, Double(desvio), rad.quadrosComCorte, rad.quadros.count))
guard abs(rad.lacunaTopoMaxPt - Double(desvio)) < 1,
      rad.quadrosComCorte == rad.quadros.count else {
    print("FALHOU: o detector perde a moldura deslocada durante o evento de ambiente.")
    exit(1)
}

var resultados: [Resultado] = []
for t in transicoes where familiaFiltro == nil || t.familia == familiaFiltro {
    let r = rodar(t)
    resultados.append(r)
    let rotulo = r.nome.padding(toLength: 32, withPad: " ", startingAt: 0)
    print(String(format: "  %@ quadros=%2d %4.1f Hz alturas=%2d corte=%2d excedente_max=%6.1f pt "
                         + "lacuna_topo_max=%5.1f pt",
                 rotulo, r.quadros.count, r.hz, r.alturasDistintas, r.quadrosComCorte,
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
var vaziosSubida = 0, vaziosDescida = 0, vaziosPatamar = 0, vaziosBorda = 0
for r in resultados {
    let c = r.contornoDosVazios
    vaziosSubida += c.subida
    vaziosDescida += c.descida
    vaziosPatamar += c.patamar
    vaziosBorda += c.borda
}
print("  contorno dos vazios: subida=\(vaziosSubida) descida=\(vaziosDescida) "
      + "patamar=\(vaziosPatamar) borda=\(vaziosBorda)")
let terminaramVazias = resultados.filter(\.terminouVazio)
print("  transições que TERMINARAM vazias: \(terminaramVazias.count)"
      + (terminaramVazias.isEmpty ? "" : " — \(terminaramVazias.map(\.nome).joined(separator: ", "))"))
print("quadros vazios examinados (a corrida INTEIRA, controles inclusive): \(vaziosExaminados)"
      + " — sumiram na 2ª foto do mesmo giro: \(vaziosQueSumiramNaSegundaFoto)"
      + ", com desenho na foto por camada: \(vaziosComCamadaDesenhada)/\(fotosPorCamadaFeitas)"
      + " (2ª câmera \(camadaOK ? "aferida" : "CEGA"))")

// Eventos de ambiente: quantos foram dirigidos e quantos mexeram de verdade no
// estado observável da janela. `setFrame` com o mesmo frame não tem estado que
// flipe — ele conta como dirigido e NÃO como mudança observada.
print("eventos de ambiente dirigidos: \(eventosDirigidos.count)"
      + " — com mudança observável na janela: \(eventosDirigidos.filter(\.mudou).count)")
for e in eventosDirigidos where verboso {
    print("   \(e.transicao) · \(e.chamada): \(e.antes) → \(e.depois)"
          + (e.mudou ? "" : "  (sem estado que flipe)"))
}
let porChamada = Dictionary(grouping: eventosDirigidos, by: \.chamada)
    .mapValues { ($0.count, $0.filter(\.mudou).count) }
for (chamada, c) in porChamada.sorted(by: { $0.key < $1.key }) {
    print("   \(chamada): \(c.0) dirigidos, \(c.1) com mudança observável")
}
// O código real: quantas vezes `applyVisibility` foi dirigida, e o que a
// varredura da lista de janelas custou na main thread.
print("")
print("chamadas de applyVisibility dirigidas: \(chamadasApplyVisibility)"
      + " — mudanças em AppSettings: \(mudancasDeAjuste)")
if custoFullscreenDisplaysMs.isEmpty {
    print("fullscreenDisplays(): 0 varreduras (ocultarEmTelaCheia estava desligado)")
} else {
    let ordenado = custoFullscreenDisplaysMs.sorted()
    print(String(format: "fullscreenDisplays(): %d varreduras na main thread — "
                         + "min %.1f ms, mediana %.1f ms, máx %.1f ms, total %.0f ms",
                 ordenado.count, ordenado.first ?? 0, ordenado[ordenado.count / 2],
                 ordenado.last ?? 0, ordenado.reduce(0, +)))
}
print("displays que o CGWindowList apontou como em tela cheia AGORA: "
      + (telasCheiasVistasDeVerdade.isEmpty ? "nenhum"
         : telasCheiasVistasDeVerdade.sorted().map(String.init).joined(separator: ", "))
      + " — o ramo do orderOut nas transições `real-` vem da costura, não daqui")
print("ocultarEmTelaCheia no início da corrida: "
      + (ocultarEmTelaCheiaOriginal ? "ligado" : "desligado"))

// devolve os Ajustes mexidos
AppSettings.shared.formatModel = formatModelOriginal
AppSettings.shared.ocultarEmTelaCheia = ocultarEmTelaCheiaOriginal

print("com moldura menor que o conteúdo: \(comCorte.count)")
for r in comCorte {
    print(String(format: "  %@ — %d/%d quadros, excedente máximo %.1f pt, lacuna de topo %.1f pt",
                 r.nome, r.quadrosComCorte, r.quadros.count,
                 r.excedenteMaxPt, r.lacunaTopoMaxPt))
}

}
