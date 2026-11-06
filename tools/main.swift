//
//  tools/main.swift — harness de snapshot do Knobler
//
//  Renderiza a NotchView em cada estado, offscreen, e salva PNGs em
//  Snapshots/. Uso: tools/snapshot.sh (compila e roda).
//  Serve pra validar o design visualmente antes de entregar.
//

import AppKit
import ImageIO
import Network
import SwiftUI
import UniformTypeIdentifiers

// `PluginsSettingsPane` chama `KnoblerMain.delegate` no ABRIR das peças sem
// painel, e o harness não compila `KnoblerApp.swift` (o `@main` de lá brigaria
// com este arquivo). Dublê inerte só pra satisfazer o compilador: nenhum
// cenário renderiza a vitrine de Ajustes.
// ponytail: dublê sem lógica real — teto é uma chamada nova a
// `KnoblerMain.delegate` vinda de Knobler/PluginsSettingsPane.swift que peça
// mais do que `viewModelPrincipal`/`ligarDesligarNota`, o que quebra a
// compilação do harness de novo. Upgrade: injetar as ações da vitrine por
// protocolo em vez de alcançar o delegate global.
@MainActor
enum KnoblerMain {
    struct DubleDeAppDelegate {
        func viewModelPrincipal() -> NotchViewModel? { nil }
        func ligarDesligarNota(em screen: NSScreen?) {}
    }
    static let delegate = DubleDeAppDelegate()
}

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Snapshots"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// capa de disco fake (gradiente) pra simular artwork do Spotify
func fakeArtwork() -> NSImage {
    let size = NSSize(width: 300, height: 300)
    let image = NSImage(size: size)
    image.lockFocus()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.85, green: 0.35, blue: 0.30, alpha: 1),
        NSColor(calibratedRed: 0.25, green: 0.15, blue: 0.45, alpha: 1),
    ])!.draw(in: NSRect(origin: .zero, size: size), angle: -60)
    // "vinil" no centro só pra ter forma reconhecível
    NSColor.black.withAlphaComponent(0.35).setFill()
    NSBezierPath(ovalIn: NSRect(x: 90, y: 90, width: 120, height: 120)).fill()
    image.unlockFocus()
    return image
}

func fakeState(playing: Bool = true) -> MediaController.PlaybackState {
    .init(
        isPlaying: playing,
        title: "Paranoid Android",
        artist: "Radiohead",
        album: "OK Computer",
        duration: 386,
        position: 143,
        fetchedAt: Date(),
        artworkURL: nil
    )
}

struct Scenario {
    let name: String
    let realNotch: Bool
    let configure: @MainActor (NotchViewModel, MediaController, AskStore) -> Void
    let agentRequest: AgentRequest?
    let agentRequestExpanded: Bool
    let resolveAgentRequest: (AgentRequestAction, AgentRequestResponder)?
    let terminalFirstRace: Bool
    let frameHeight: CGFloat
    /// O card do WhatsApp mede 780: os 560 de sempre cortariam a moldura.
    let frameWidth: CGFloat

    init(
        name: String,
        realNotch: Bool,
        agentRequest: AgentRequest? = nil,
        agentRequestExpanded: Bool = false,
        resolveAgentRequest: (AgentRequestAction, AgentRequestResponder)? = nil,
        terminalFirstRace: Bool = false,
        frameHeight: CGFloat = 240,
        frameWidth: CGFloat = 560,
        configure: @escaping @MainActor (NotchViewModel, MediaController, AskStore) -> Void
    ) {
        self.name = name
        self.realNotch = realNotch
        self.agentRequest = agentRequest
        self.agentRequestExpanded = agentRequestExpanded
        self.resolveAgentRequest = resolveAgentRequest
        self.terminalFirstRace = terminalFirstRace
        self.frameHeight = frameHeight
        self.frameWidth = frameWidth
        self.configure = configure
    }
}

/// Autoridade mínima da corrida do snapshot: a primeira chamada aceita, as
/// seguintes apenas registram a tentativa sem poder sobrescrever o vencedor.
@MainActor
final class SnapshotAgentArbiter {
    private(set) var winner: AgentRequestResult?
    private(set) var attempts: [AgentRequestResponder] = []

    func resolve(action: AgentRequestAction, responder: AgentRequestResponder) -> Bool {
        attempts.append(responder)
        guard winner == nil else { return false }
        winner = AgentRequestResult(action: action, responder: responder)
        return true
    }
}

// prateleira do cenário corrente (recriada por cenário no loop)
var currentShelf = ShelfStore()

func fakeShelfFiles() -> [URL] {
    let dir = FileManager.default.temporaryDirectory
    return ["Relatório.pdf", "foto.png", "notas.txt"].map { name in
        let url = dir.appendingPathComponent(name)
        try? "x".data(using: .utf8)?.write(to: url)
        return url
    }
}

/// Arquivos de uma pilha, com prefixo comum e nome longo: é o caso que a grade
/// da pilha aberta trunca no meio.
func fakePilhaFiles(_ n: Int) -> [URL] {
    let dir = FileManager.default.temporaryDirectory
    return (1...n).map { i in
        let url = dir.appendingPathComponent(
            String(format: "Captura de tela 2026-08-28 as 14.%02d.png", i))
        try? "x".data(using: .utf8)?.write(to: url)
        return url
    }
}

/// PNG de verdade (o `fakeShelfFiles` escreve "x", que o ImageIO não abre) —
/// o preview de conversão precisa de um arquivo que converta pra valer.
func fakePNGFile(_ size: CGSize = CGSize(width: 480, height: 300)) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-preview.png")
    guard let ctx = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return url }
    ctx.setFillColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1)
    ctx.fill(CGRect(origin: .zero, size: size))
    ctx.setFillColor(red: 0.95, green: 0.75, blue: 0.25, alpha: 1)
    ctx.fillEllipse(in: CGRect(x: size.width * 0.30, y: size.height * 0.22,
                               width: size.width * 0.40, height: size.height * 0.56))
    if let image = ctx.makeImage(),
       let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
    return url
}

/// Gira o runloop até a conversão do preview terminar. O `ImageRenderer` desenha
/// um instante depois do setup, e sem esperar o card sairia sempre no estado
/// "convertendo" — o oposto do que este PNG existe pra mostrar.
@MainActor
func esperarPreview(_ shelf: ShelfStore, _ segundos: TimeInterval = 5) {
    let limite = Date().addingTimeInterval(segundos)
    while shelf.preview?.running != false, Date() < limite {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

@MainActor
func configurarEditorAgenda(_ vm: NotchViewModel) {
    vm.onConsultarAgenda = { CalendarAgenda(dia: $0, autorizado: true) }
    vm.onCalendariosAgenda = { [CalendarDestino(id: "sintetico", nome: "Trabalho", conta: "Local", padrao: true)] }
    vm.setExpandedDirect(true)
    vm.secoes = [.agenda, .musica]
    vm.focar(.agenda)
    vm.novoEventoAgenda()
    vm.agendaRascunho?.titulo = "Revisão do projeto"
    vm.agendaRascunho?.local = "Sala de reunião"
    vm.agendaRascunho?.link = "https://meet.google.com/exemplo"
    vm.agendaRascunho?.observacoes = "Alinhar os próximos passos com a equipe."
}

/// Com a tela bloqueada o window server não dá foco de teclado a janela
/// nenhuma (o `makeKey()` vira no-op): o teste de teclado da agenda falharia
/// e o trap derrubaria todos os cenários seguintes.
func telaBloqueada() -> Bool {
    let sessao = CGSessionCopyCurrentDictionary() as? [String: Any]
    return (sessao?["CGSSessionScreenIsLocked"] as? Bool) ?? false
}

@MainActor
func lembretesSinteticos() -> AppleRemindersStore {
    let store = AppleRemindersStore(snapshot: true)
    store.accounts = [AppleReminderAccount(id: "local", title: "Pessoal")]
    store.lists = [AppleReminderList(id: "tarefas", title: "Tarefas", accountID: "local", writable: true)]
    store.defaultListID = "tarefas"
    store.items = [
        AppleReminder(id: "atrasado", draft: AppleReminderDraft(title: "Revisar o planejamento da próxima entrega com a equipe de produto", notes: "Confirmar os detalhes antes da reunião.", listID: "tarefas", priority: 1, dueDate: Date().addingTimeInterval(-86400)), completed: false, writable: true),
        AppleReminder(id: "hoje", draft: AppleReminderDraft(title: "Comprar ingredientes para o jantar", listID: "tarefas", dueDate: Date(), hasTime: true), completed: false, writable: true)
    ]
    return store
}

@MainActor
func configurarLembretes(_ vm: NotchViewModel, estado: String) {
    let store = lembretesSinteticos()
    let ui = AppleRemindersUI(store: store)
    if estado == "vazio" { store.items = [] }
    if estado == "sem-permissao" { store.access = .denied }
    if estado == "carregando" { store.loading = true; store.items = [] }
    if estado == "criar" || estado == "erro" {
        ui.newReminder()
        ui.draft?.title = "Revisar o planejamento"
        ui.draft?.dueDate = Date()
    }
    if estado == "erro" { ui.error = .message("Não foi possível salvar. Seu rascunho foi preservado.") }
    vm.onLembretesView = { [weak vm] in
        AnyView(AppleRemindersNotchView(store: store, ui: ui,
            onEditingChanged: { [weak vm] in vm?.atualizarEdicaoLembretes($0) },
            onKeyboard: { [weak vm] in vm?.onAgendaKeyboard?() }))
    }
    vm.setExpandedDirect(true)
    vm.secoes = [.lembretesApple, .agenda, .musica]
    vm.focar(.lembretesApple)
}

@MainActor
func configurarMonitores(_ vm: NotchViewModel, estado: String) {
    let interna = MonitorState(id: 1, persistentID: "snapshot-interna", name: "Tela integrada",
        brightness: 0.65, hardwareBrightness: true)
    var externa = MonitorState(id: 2, persistentID: "snapshot-externa", name: "Monitor externo",
        brightness: 0.72, contrast: 0.5, volume: 0.35, muteSupported: true, hardwareBrightness: true)
    externa.preferences.enableMute = true
    if estado == "software" {
        externa.contrast = nil
        externa.volume = nil
        externa.hardwareBrightness = false
        externa.software = true
        externa.brightness = 0.3
    }
    if estado == "erro" { externa.error = "Não foi possível ajustar o brilho deste monitor." }
    Monitores.shared.displays = estado == "interna" ? [interna] : estado == "multiplas" ? [interna, externa] : [externa]
    vm.monitoresDisponiveis = true
    vm.displayID = 1
    vm.setExpandedDirect(true)
    vm.monitoresSelecionado = estado == "interna" ? 1 : 2
    vm.monitoresContraste = estado == "contraste"
    vm.secoes = [.monitores, .musica]
    vm.focar(.monitores)
}

// MARK: - WhatsApp: contas e conversas fictícias do mockup
// (docs/vesta/mockups/2026-11-04-whatsapp/index.html, `ACC` e `CHATS`)

let waBiz = "554791744143"
let waPes = "554792508292"
let waMarina = "554799990010@s.whatsapp.net"
let waCarlos = "554799990011@s.whatsapp.net"
let waFamilia = "120363000000000002@g.us"

/// Hoje (ou `dias` atrás) na hora dada, no fuso local: a hora da linha sai
/// igual à do mockup.
func waTs(_ h: Int, _ m: Int, dias: Int = 0) -> Int {
    let cal = Calendar.current
    let dia = cal.date(byAdding: .day, value: -dias, to: Date())!
    return Int(cal.date(bySettingHour: h, minute: m, second: 0, of: dia)!.timeIntervalSince1970)
}

func waConversa(_ jid: String, _ nome: String, grupo: Bool = false, naoLidas: Int = 0, ts: Int,
                tipo: WATipoMensagem = .texto, previa: String = "", de: String? = nil,
                segundos: Int? = nil, apagada: Bool = false) -> WAConversa {
    let ultima = WAUltima(id: "u-\(jid)", deMim: false,
                          remetente: de == nil ? jid : "554799990099@s.whatsapp.net",
                          remetenteNome: de, tipo: tipo, previa: previa, ts: ts,
                          apagada: apagada ? ts : nil, segundos: segundos)
    return WAConversa(jid: jid, jids: [jid], tipo: grupo ? .grupo : .individual, nome: nome,
                      naoLidas: naoLidas, marcadaNaoLida: false, ts: ts, ultima: ultima)
}

func waEstadoDoMockup() -> WAEstado {
    var e = WAEstado()
    e.substituirContas([
        WAConta(conta: waBiz, jid: waBiz + ":17@s.whatsapp.net", nome: "ZOI Business", padrao: true,
                estado: .conectada, motivo: nil, desde: 1762270000, naoLidas: 5, conversasNaoLidas: 2),
        WAConta(conta: waPes, jid: waPes + ":4@s.whatsapp.net", nome: "Pessoal", padrao: false,
                estado: .conectada, motivo: nil, desde: 1762270000, naoLidas: 2, conversasNaoLidas: 2),
    ])
    e.substituirConversas(conta: waBiz, [
        waConversa("120363000000000001@g.us", "Operacional ZOI", grupo: true, naoLidas: 3,
                   ts: waTs(14, 41), tipo: .voz, de: "Diego Martins", segundos: 37),
        waConversa(waMarina, "Marina Duarte", naoLidas: 2, ts: waTs(14, 32),
                   previa: "Fechado! Mando o briefing até sexta."),
        waConversa(waCarlos, "Carlos (Seller Veículos)", ts: waTs(11, 47),
                   previa: "Dá uma olhada quando puder."),
    ])
    e.definirRascunho("Carlos, ajustei o orçamento de dezembro e…", para: WAChave(conta: waBiz, jid: waCarlos))
    e.substituirConversas(conta: waPes, [
        waConversa(waFamilia, "Família", grupo: true, naoLidas: 1, ts: waTs(13, 5),
                   tipo: .figurinha, de: "Tia Lúcia"),
        waConversa("554799990013@s.whatsapp.net", "Rafa Lima", naoLidas: 1, ts: waTs(12, 20),
                   tipo: .video, segundos: 18),
        waConversa("554799990014@s.whatsapp.net", "Mãe", ts: waTs(21, 10, dias: 1),
                   previa: "Filho, chegou bem?", apagada: true),
    ])
    return e
}

/// Seção (ou faixa) do WhatsApp com o estado do mockup. A conversa já entra
/// aberta: assim o `adotarPadrao` da view não sai pedindo bolhas.
@MainActor
func waCenario(_ vm: NotchViewModel, conta: String, aberta: String, foco: NotchSection) {
    WhatsAppStore.shared._injetar(estado: waEstadoDoMockup(), conexao: .pronta, canalAberto: true)
    vm.setExpandedDirect(true)
    vm.secoes = [.musica, .shelf, .mensagens, .whatsapp, .historico, .nota]
    vm.focus = foco
    vm.whatsappContaSelecionada = conta
    vm.whatsappConversaAberta = WAChave(conta: conta, jid: aberta).texto
}

/// Estados de conexão da seção (aba "Estados de conexão" do mockup). Sem
/// conversa na conta mostrada nem pareamento a pedir: nada sai para a ponte.
let waQRSintetico = "2@knobler-snapshot"

func waPareamento(_ estado: WAEstadoPareamento) -> WAPareamento {
    let qr = estado == .qr ? waQRSintetico : nil
    return WAPareamento(id: "p-snapshot", estado: estado, qr: qr, qrExpiraEm: qr == nil ? nil : 1762270620,
                        fim: 1762270720, conta: nil, motivo: nil)
}

/// `estado`: o do mockup, só com contas (`comConversas: false`) ou vazio.
/// Com `pessoalDeslogada`, a Pessoal · 8292 está deslogada e sem conversas.
@MainActor
func waEstadosCenario(_ vm: NotchViewModel, conexao: WAConexao, conta: String = waBiz,
                      comContas: Bool = true, comConversas: Bool = true,
                      pessoalDeslogada: Bool = false, pareamento: WAPareamento? = nil) {
    var e = WAEstado()
    if comContas {
        let mockup = waEstadoDoMockup()
        e.substituirContas(mockup.contas.map { c in
            guard pessoalDeslogada, c.conta == waPes else { return c }
            return WAConta(conta: c.conta, jid: c.jid, nome: c.nome, padrao: c.padrao, estado: .deslogada,
                           motivo: nil, desde: c.desde, naoLidas: 0, conversasNaoLidas: 0)
        })
        if comConversas {
            e.substituirConversas(conta: waBiz, mockup.conversas(da: waBiz))
            if !pessoalDeslogada { e.substituirConversas(conta: waPes, mockup.conversas(da: waPes)) }
        }
    }
    e.pareamento = pareamento
    WhatsAppStore.shared._injetar(estado: e, conexao: conexao, canalAberto: conexao == .pronta)
    vm.setExpandedDirect(true)
    vm.secoes = [.musica, .shelf, .mensagens, .whatsapp, .historico, .nota]
    vm.focus = .whatsapp
    vm.whatsappContaSelecionada = conta
    // a conversa já aberta: o `adotarPadrao` não sai pedindo bolhas
    if conta == waBiz && comConversas { vm.whatsappConversaAberta = WAChave(conta: waBiz, jid: waMarina).texto }
}

/// Conversa do mockup aberta na coluna direita (aba "Variante A", colunas
/// direitas dos quadros de conversa). As mídias são cores sólidas gravadas
/// numa pasta temporária do harness: nada pessoal, nada da ponte.
let waOperacional = "120363000000000001@g.us"
let waEu = waBiz + "@s.whatsapp.net"
let waAna = "554799000001@s.whatsapp.net"
let waDiego = "554799000002@s.whatsapp.net"
let waJulia = "554799000003@s.whatsapp.net"
let waPastaDeMidia = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("knobler-snapshot-whatsapp-\(getpid())", isDirectory: true)

/// `de: nil` é mensagem minha.
func waMsg(_ id: String, _ conversa: String, de: String? = nil, nome: String? = nil, _ h: Int, _ mi: Int,
           tipo: WATipoMensagem = .texto, texto: String = "", midia: WAMidia? = nil,
           citacao: WACitacao? = nil, reacao: String? = nil, editada: Bool = false,
           apagada: Bool = false, status: WAStatus? = nil) -> WAMensagem {
    let ts = waTs(h, mi)
    let reacoes = reacao.map { [WAReacao(remetente: de ?? conversa, deMim: false, emoji: $0, ts: ts + 60)] } ?? []
    return WAMensagem(id: id, conversa: conversa, remetente: de ?? waEu, remetenteNome: nome,
                      deMim: de == nil, ts: ts, tipo: tipo, texto: texto, midia: midia, citacao: citacao,
                      reacoes: reacoes, editada: editada ? ts + 120 : nil, apagada: apagada ? ts + 30 : nil,
                      status: de == nil ? status : nil)
}

func waMidia(_ mimetype: String, nome: String = "", tamanho: Int = 120_000, segundos: Int? = nil) -> WAMidia {
    WAMidia(mimetype: mimetype, nome: nome, tamanho: tamanho, segundos: segundos, miniatura: true, baixada: true)
}

/// PNG de cor sólida (ou só um emoji, fundo transparente, para a figurinha).
func waPNG(_ cor: NSColor, largura: CGFloat = 400, altura: CGFloat = 250, emoji: String? = nil) -> Data {
    let img = NSImage(size: NSSize(width: largura, height: altura), flipped: false) { r in
        cor.setFill()
        r.fill()
        if let emoji {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: altura * 0.8)]
            let t = NSAttributedString(string: emoji, attributes: attrs)
            let tam = t.size()
            t.draw(at: NSPoint(x: (largura - tam.width) / 2, y: (altura - tam.height) / 2))
        }
        return true
    }
    return NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
}

/// Envio local do mockup: `enviando` (relógio) ou que falhou ("tentar de novo").
struct WAEnvioDoMockup {
    let texto: String
    let h: Int
    let m: Int
    let falhou: Bool
}

@MainActor
func waConversaCenario(_ vm: NotchViewModel, jid: String, _ mensagens: [WAMensagem],
                       local: WAEnvioDoMockup? = nil, indisponiveis: [String] = [],
                       miniaturas: [String: Data] = [:], arquivos: [String: Data] = [:]) {
    let store = WhatsAppStore.shared
    let k = WAChave(conta: waBiz, jid: jid)
    var e = waEstadoDoMockup()
    e.inserirMensagens(mensagens, em: k, antes: nil, maisVelhas: false)
    if let local {
        e.comecarEnvio(chave: k, texto: local.texto, citacao: nil, ref: "snap-1",
                       agora: waTs(local.h, local.m), remetente: waBiz)
        if local.falhou { e.falharEnvio(ref: "snap-1", chave: k) }
    }
    for id in indisponiveis { _ = e.aplicar(.midia(conversa: jid, alvo: id, ok: false), conta: waBiz) }
    store._usarMidia(raiz: waPastaDeMidia)
    for m in mensagens {
        if let d = arquivos[m.id] {
            let url = store.midia.caminho(chave: k, mensagem: m)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? d.write(to: url)
        }
        if let d = miniaturas[m.id] { store.midia._injetarMiniatura(d, chave: k, mensagem: m) }
    }
    store._injetar(estado: e, conexao: .pronta, canalAberto: true)
    if jid == waOperacional {
        let p = { (jid: String, nome: String, eu: Bool) in
            WAParticipante(jid: jid, telefone: nil, lid: nil, nome: nome, admin: false, superadmin: false, eu: eu)
        }
        store._injetar(grupo: WAGrupo(jid: jid, nome: "Operacional ZOI", descricao: "", criado: 1_575_256_960,
                                      dono: nil, soAdminsEnviam: false,
                                      participantes: [p(waEu, "Você", true), p(waAna, "Ana Ribeiro", false),
                                                      p(waDiego, "Diego Martins", false),
                                                      p(waJulia, "Júlia Souza", false)]),
                       em: k)
    }
    vm.setExpandedDirect(true)
    vm.secoes = [.musica, .shelf, .mensagens, .whatsapp, .historico, .nota]
    vm.focus = .whatsapp
    vm.whatsappContaSelecionada = waBiz
    vm.whatsappConversaAberta = k.texto
}

/// Card de chegada do WhatsApp (aba "Card de chegada" do mockup): o estado
/// do mockup com a mensagem dentro e o card montado pelo `WACartao`, como a
/// `WhatsAppIntegracao` monta. A miniatura entra em memória, sem a ponte.
@MainActor
func waCartaoCenario(_ vm: NotchViewModel, conta: String, jid: String, _ m: WAMensagem,
                     contagem: Int = 1, miniatura: Data? = nil) {
    let store = WhatsAppStore.shared
    let k = WAChave(conta: conta, jid: jid)
    var e = waEstadoDoMockup()
    e.inserirMensagens([m], em: k, antes: nil, maisVelhas: false)
    store._usarMidia(raiz: waPastaDeMidia)
    if let miniatura { store.midia._injetarMiniatura(miniatura, chave: k, mensagem: m) }
    store._injetar(estado: e, conexao: .pronta, canalAberto: true)
    let conversa = e.conversas(da: conta).first { $0.jid == jid }!
    vm.activeNotification = WACartao.montar(mensagem: m, conversa: conversa,
                                            conta: e.contas.first { $0.conta == conta }, numero: conta,
                                            contagem: contagem, agora: Date(timeIntervalSince1970: TimeInterval(m.ts)))
}

let scenarios: [Scenario] = [
    Scenario(name: "monitores-interna", realNotch: true, frameHeight: 360) { vm, _, _ in configurarMonitores(vm, estado: "interna") },
    Scenario(name: "monitores-ddc", realNotch: true, frameHeight: 360) { vm, _, _ in configurarMonitores(vm, estado: "ddc") },
    Scenario(name: "monitores-software", realNotch: false, frameHeight: 360) { vm, _, _ in configurarMonitores(vm, estado: "software") },
    Scenario(name: "monitores-multiplas", realNotch: true, frameHeight: 360) { vm, _, _ in configurarMonitores(vm, estado: "multiplas") },
    Scenario(name: "monitores-contraste", realNotch: true, frameHeight: 400) { vm, _, _ in configurarMonitores(vm, estado: "contraste") },
    Scenario(name: "monitores-erro", realNotch: true, frameHeight: 400) { vm, _, _ in configurarMonitores(vm, estado: "erro") },
    Scenario(name: "closed-idle", realNotch: true) { _, _, _ in },
    Scenario(name: "closed-music", realNotch: true) { _, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
    },
    Scenario(name: "closed-music-external", realNotch: false) { _, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
    },
    // pausado: capa escurecida e as barras nos pontinhos, como a ilha do iPhone
    Scenario(name: "closed-paused", realNotch: true) { _, media, _ in
        media.injectPreview(state: fakeState(playing: false), artwork: fakeArtwork())
    },
    // nota com texto e card fechado: a asa existe só por causa do pontinho —
    // sem música, sem atividade, sem mic. É o aviso de "tem rascunho aqui".
    Scenario(name: "nota-editando", realNotch: true) { vm, _, _ in
        vm.displayID = 1
        QuickNote.shared.adotar(1)
        QuickNote.shared.text = "Rascunho sintético preservado"
        vm.setExpandedDirect(true)
        vm.secoes = [.nota, .musica]
        vm.focus = .nota
    },
    Scenario(name: "teclado-bloqueado", realNotch: true) { _, _, _ in TecladoBloqueado.shared._simularAtivo(true) },
    Scenario(name: "closed-note", realNotch: true) { vm, _, _ in
        vm.displayID = 1
        QuickNote.shared.hostDisplayID = 1
        QuickNote.shared.active = true
        QuickNote.shared.text = "pedido 88213"
    },
    Scenario(name: "nota-fechada-por-gesto", realNotch: true) { vm, _, _ in
        vm.displayID = 1
        QuickNote.shared.adotar(1)
        QuickNote.shared.text = "Rascunho preservado"
        QuickNote.shared.editing = true
        vm.setExpandedDirect(true)
        vm.setExpandedDirect(false)
        assert(vm.mode == .closed && !QuickNote.shared.editing)
    },
    Scenario(name: "hud-volume", realNotch: true) { vm, _, _ in
        vm.hud = .init(level: 0.6, muted: false)
    },
    Scenario(name: "hud-muted", realNotch: true) { vm, _, _ in
        vm.hud = .init(level: 0, muted: true)
    },
    Scenario(name: "hud-volume-external", realNotch: false) { vm, _, _ in
        vm.hud = .init(level: 0.6, muted: false)
    },
    Scenario(name: "hud-brightness", realNotch: true) { vm, _, _ in
        vm.hud = .init(kind: .brightness, level: 0.75)
    },
    Scenario(name: "hud-battery-charging", realNotch: true) { vm, _, _ in
        vm.hud = .init(kind: .battery, level: 0.74, charging: true)
    },
    Scenario(name: "hud-battery-low", realNotch: true) { vm, _, _ in
        vm.hud = .init(kind: .battery, level: 0.18, charging: false)
    },
    Scenario(name: "music-expanded", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.setExpandedDirect(true)
    },
    Scenario(name: "music-expanded-paused", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(playing: false), artwork: fakeArtwork())
        vm.setExpandedDirect(true)
    },
    // Card aberto: o eixo de variação é QUAL SEÇÃO está em foco. A faixa do
    // rodapé mostra as outras, e `secoes`/`focus` são montados à mão porque o
    // harness não tem como provocar o carimbo de evento de cada seção.
    //
    // Sem cenário pra `historico` e `mensagens` (usam ScrollView, que sai preto
    // no ImageRenderer offscreen) nem pra `espelho` (precisa de câmera real).
    Scenario(name: "foco-musica", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.setExpandedDirect(true)
        vm.secoes = [.musica, .atividade, .shelf]
        vm.focus = .musica
    },
    Scenario(name: "foco-atividade", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.activity = NotchActivity(id: "deploy", title: "Deploy", detail: "3 de 8",
                                    progress: 0.375, updatedAt: Date())
        vm.setExpandedDirect(true)
        vm.secoes = [.atividade, .musica]
        vm.focus = .atividade
    },
    Scenario(name: "foco-pomodoro", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.pomodoro = PomodoroState(phase: .focus, runState: .running, remaining: 900,
                                    completedFocus: 1, cyclesUntilLong: 4)
        vm.setExpandedDirect(true)
        vm.secoes = [.pomodoro, .musica]
        vm.focus = .pomodoro
    },
    // Card do Pomodoro com a linha do próximo evento do calendário: título longo
    // de propósito, pra provar que trunca em vez de empurrar os controles.
    Scenario(name: "foco-pomodoro-evento", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.pomodoro = PomodoroState(phase: .focus, runState: .running, remaining: 900,
                                    completedFocus: 1, cyclesUntilLong: 4)
        vm.calendarAviso = CalendarAviso(titulo: "Retrospectiva do time de produto",
                                         faltam: 12 * 60)
        vm.setExpandedDirect(true)
        vm.secoes = [.pomodoro, .musica]
        vm.focus = .pomodoro
    },
    // O Pomodoro na FAIXA, não em foco: é o único cenário que desenha o anel do
    // tempo restante no ícone (`fatiaDoCiclo`). Sem ele nenhum PNG cobre esse
    // anel — os outros cenários de Pomodoro o deixam sempre em foco.
    Scenario(name: "faixa-pomodoro", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.pomodoro = PomodoroState(phase: .focus, runState: .running, remaining: 900,
                                    completedFocus: 1, cyclesUntilLong: 4)
        vm.setExpandedDirect(true)
        vm.secoes = [.musica, .pomodoro]
        vm.focus = .musica
    },
    Scenario(name: "expanded-acoes-rapidas", realNotch: true) { vm, _, _ in
        AppSettings.shared.acoesRapidas = [.cor, .monitores, .nota]
        vm.setExpandedDirect(true)
        vm.secoes = [.acoesRapidas]
        vm.focus = .acoesRapidas
    },
    Scenario(name: "expanded-acoes-rapidas-vazio", realNotch: true) { vm, _, _ in
        AppSettings.shared.acoesRapidas = []
        vm.setExpandedDirect(true)
        vm.secoes = [.acoesRapidas]
        vm.focus = .acoesRapidas
    },
    Scenario(name: "expanded-cor-vazio", realNotch: true) { vm, _, _ in
        vm.setExpandedDirect(true)
        vm.secoes = [.cor]
        vm.focus = .cor
    },
    // moldura do quadro A do mockup: 780 × (32 + 360 + 60), ainda com o vazio
    Scenario(name: "whatsapp-moldura", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        vm.setExpandedDirect(true)
        vm.secoes = [.whatsapp]
        vm.focus = .whatsapp
    },
    // coluna esquerda do quadro "Lista e conversa individual" (variante A):
    // grupo com prévia de áudio, Marina com 2 não lidas, Carlos com rascunho
    Scenario(name: "whatsapp-lista-4143", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waCenario(vm, conta: waBiz, aberta: waMarina, foco: .whatsapp)
    },
    // lista do quadro "Lista — Pessoal · 8292" (variante B): vídeo, figurinha
    // em grupo e mensagem apagada
    Scenario(name: "whatsapp-lista-8292", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waCenario(vm, conta: waPes, aberta: waFamilia, foco: .whatsapp)
    },
    // quadro "Faixa de atalhos, 3×": o ícone com a contagem das não lidas
    Scenario(name: "whatsapp-faixa", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        waCenario(vm, conta: waBiz, aberta: waMarina, foco: .musica)
    },
    // aba "Estados de conexão": um cenário por quadro (o de chave ausente e o
    // de incompatível seguem o desenho do de chave)
    Scenario(name: "whatsapp-ponte-fora", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waEstadosCenario(vm, conexao: .foraDoAr)
    },
    Scenario(name: "whatsapp-chave", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waEstadosCenario(vm, conexao: .chaveNaoConfere)
    },
    Scenario(name: "whatsapp-chave-ausente", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waEstadosCenario(vm, conexao: .semChave, comContas: false)
    },
    Scenario(name: "whatsapp-incompativel", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waEstadosCenario(vm, conexao: .incompativel(2), comContas: false)
    },
    Scenario(name: "whatsapp-qr", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waEstadosCenario(vm, conexao: .pronta, conta: waPes, comConversas: false,
                         pessoalDeslogada: true, pareamento: waPareamento(.qr))
    },
    Scenario(name: "whatsapp-qr-expirado", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waEstadosCenario(vm, conexao: .pronta, conta: waPes, comConversas: false,
                         pessoalDeslogada: true, pareamento: waPareamento(.expirado))
    },
    Scenario(name: "whatsapp-carregando", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waEstadosCenario(vm, conexao: .carregando, comContas: false)
    },
    Scenario(name: "whatsapp-vazio", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waEstadosCenario(vm, conexao: .pronta, conta: waPes, comConversas: false)
    },
    // quadro "Conta desconectada" da variante A: a ZOI Business segue com a
    // lista e as não lidas; a Pessoal, deslogada, mostra o QR à direita
    Scenario(name: "whatsapp-desconectada", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waEstadosCenario(vm, conexao: .pronta, conta: waPes, pessoalDeslogada: true,
                         pareamento: waPareamento(.qr))
    },
    // quadro "Lista e conversa individual": lida em cápsula, citação dentro
    // da bolha, reação embaixo, foto com legenda (MSG m1–m4)
    Scenario(name: "whatsapp-conversa-marina", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        let foto = waMsg("m4", waMarina, de: waMarina, 14, 20, tipo: .imagem, texto: "Versão nova do post 3",
                         midia: waMidia("image/jpeg"))
        waConversaCenario(vm, jid: waMarina, [
            waMsg("m1", waMarina, de: waMarina, 14, 2, texto: "Oi! Conseguiu ver as artes da campanha de Natal?"),
            waMsg("m2", waMarina, 14, 5, texto: "Vi sim, ficaram ótimas. Só ajustaria o CTA do carrossel.", status: .lida),
            waMsg("m3", waMarina, de: waMarina, 14, 8, texto: "Pode deixar, troco para “Agende sua visita”.",
                  citacao: WACitacao(id: "m2", remetente: waEu, texto: "Só ajustaria o CTA do carrossel."),
                  reacao: "👍"),
            foto,
        ], arquivos: ["m4": waPNG(NSColor(red: 0.62, green: 0.72, blue: 0.78, alpha: 1))])
    },
    // quadro "Envio, edição e barra de reações" (só as bolhas): editada e
    // entregue, enviada, recebida, enviando (MSG m5–m8)
    Scenario(name: "whatsapp-conversa-entrega", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waConversaCenario(vm, jid: waMarina, [
            waMsg("m5", waMarina, 14, 22, texto: "Perfeito. Sobe hoje às 18h?", editada: true, status: .entregue),
            waMsg("m6", waMarina, 14, 25, texto: "Já te mando o relatório de outubro.", status: .enviada),
            waMsg("m7", waMarina, de: waMarina, 14, 32, texto: "Fechado! Mando o briefing até sexta."),
        ], local: WAEnvioDoMockup(texto: "Combinado!", h: 14, m: 33, falhou: false))
    },
    // quadro "Grupo: remetentes, documento, vídeo, gravando" (só as bolhas)
    Scenario(name: "whatsapp-grupo-midia", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waConversaCenario(vm, jid: waOperacional, [
            waMsg("g1", waOperacional, de: waAna, nome: "Ana Ribeiro", 9, 12,
                  texto: "Bom dia, pessoal! A pauta da semana está no drive."),
            waMsg("g2", waOperacional, de: waAna, nome: "Ana Ribeiro", 9, 13, tipo: .documento,
                  midia: waMidia("application/pdf", nome: "Pauta-semana-45.pdf", tamanho: 840_000)),
            waMsg("g3", waOperacional, de: waDiego, nome: "Diego Martins", 9, 40, tipo: .video,
                  texto: "Bastidores da gravação na Seller", midia: waMidia("video/mp4", segundos: 42)),
        ], miniaturas: ["g3": waPNG(NSColor(red: 0.17, green: 0.18, blue: 0.20, alpha: 1))])
    },
    // quadro "Grupo: reação, figurinha e mensagem apagada"
    Scenario(name: "whatsapp-grupo-reacao", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waConversaCenario(vm, jid: waOperacional, [
            waMsg("g4", waOperacional, 9, 44, texto: "Ficou muito bom. Dá para cortar uma versão de 15 s?",
                  reacao: "❤️", status: .lida),
            waMsg("g5", waOperacional, de: waDiego, nome: "Diego Martins", 9, 46, tipo: .figurinha,
                  midia: waMidia("image/webp")),
            waMsg("g6", waOperacional, de: waJulia, nome: "Júlia Souza", 10, 2, apagada: true),
        ], arquivos: ["g5": waPNG(.clear, largura: 180, altura: 180, emoji: "🎬")])
    },
    // quadro "Grupo: mídia indisponível, áudio, falha, ditando" (só as bolhas)
    Scenario(name: "whatsapp-grupo-falha", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waConversaCenario(vm, jid: waOperacional, [
            waMsg("g7", waOperacional, de: waJulia, nome: "Júlia Souza", 10, 5, tipo: .imagem,
                  midia: waMidia("image/jpeg")),
            waMsg("g8", waOperacional, de: waDiego, nome: "Diego Martins", 14, 41, tipo: .voz,
                  midia: waMidia("audio/ogg; codecs=opus", segundos: 37)),
        ], local: WAEnvioDoMockup(texto: "Ouço daqui a pouco e respondo.", h: 14, m: 43, falhou: true),
           indisponiveis: ["g7"])
    },
    // quadro "Envio, edição e barra de reações": a barra de 6 reações aberta
    // sobre m7 e o compositor citando m7 (MSG m5–m8)
    Scenario(name: "whatsapp-citando-reacoes", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        let m7 = waMsg("m7", waMarina, de: waMarina, 14, 32, texto: "Fechado! Mando o briefing até sexta.")
        waConversaCenario(vm, jid: waMarina, [
            waMsg("m5", waMarina, 14, 22, texto: "Perfeito. Sobe hoje às 18h?", editada: true, status: .entregue),
            waMsg("m6", waMarina, 14, 25, texto: "Já te mando o relatório de outubro.", status: .enviada),
            m7,
        ], local: WAEnvioDoMockup(texto: "Combinado!", h: 14, m: 33, falhou: false))
        WhatsAppStore.shared.citar(m7, em: WAChave(conta: waBiz, jid: waMarina))
        vm.whatsappReacoesEm = "m7"
    },
    // quadro "Grupo: remetentes, documento, vídeo, gravando": o compositor
    // gravando há 12 s, nível em 60%
    Scenario(name: "whatsapp-gravando", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waConversaCenario(vm, jid: waOperacional, [
            waMsg("g1", waOperacional, de: waAna, nome: "Ana Ribeiro", 9, 12,
                  texto: "Bom dia, pessoal! A pauta da semana está no drive."),
            waMsg("g2", waOperacional, de: waAna, nome: "Ana Ribeiro", 9, 13, tipo: .documento,
                  midia: waMidia("application/pdf", nome: "Pauta-semana-45.pdf", tamanho: 840_000)),
            waMsg("g3", waOperacional, de: waDiego, nome: "Diego Martins", 9, 40, tipo: .video,
                  texto: "Bastidores da gravação na Seller", midia: waMidia("video/mp4", segundos: 42)),
        ], miniaturas: ["g3": waPNG(NSColor(red: 0.17, green: 0.18, blue: 0.20, alpha: 1))])
        WhatsAppStore.shared._injetarGravacao(WAGravacaoEmCurso(
            chave: WAChave(conta: waBiz, jid: waOperacional), inicio: Date().addingTimeInterval(-12.5), nivel: 0.6))
    },
    // quadro "Grupo: mídia indisponível, áudio, falha, ditando": o ditado
    // escreve no campo em uso, com "Ouvindo" à direita (MSG g7–g9)
    Scenario(name: "whatsapp-ditando", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        waConversaCenario(vm, jid: waOperacional, [
            waMsg("g7", waOperacional, de: waJulia, nome: "Júlia Souza", 10, 5, tipo: .imagem,
                  midia: waMidia("image/jpeg")),
            waMsg("g8", waOperacional, de: waDiego, nome: "Diego Martins", 14, 41, tipo: .voz,
                  midia: waMidia("audio/ogg; codecs=opus", segundos: 37)),
        ], local: WAEnvioDoMockup(texto: "Ouço daqui a pouco e respondo.", h: 14, m: 43, falhou: true),
           indisponiveis: ["g7"])
        let k = WAChave(conta: waBiz, jid: waOperacional)
        WhatsAppStore.shared.definirRascunho("Pode subir o corte de 15 s ainda hoje", para: k)
        WhatsAppStore.shared.campoEmUso = k
        vm.whatsappEditando = true
        vm.dictation = .recording(level: 0.6)
    },
    // r3-interacao-abrir-rascunho.png: o rascunho do Carlos volta no campo
    // aba "Card de chegada": quadro "Individual, texto"
    Scenario(name: "whatsapp-cartao-texto", realNotch: true, frameHeight: 300, frameWidth: 440) { vm, _, _ in
        waCartaoCenario(vm, conta: waBiz, jid: waMarina,
                        waMsg("k1", waMarina, de: waMarina, 14, 32, texto: "Fechado! Mando o briefing até sexta."))
    },
    // quadro "Grupo": o grupo é o título, quem mandou vem na prévia
    Scenario(name: "whatsapp-cartao-grupo", realNotch: true, frameHeight: 300, frameWidth: 440) { vm, _, _ in
        waCartaoCenario(vm, conta: waBiz, jid: waOperacional,
                        waMsg("k2", waOperacional, de: waDiego, nome: "Diego Martins", 14, 41,
                              texto: "Subi o corte de 15 s no drive."))
    },
    // quadro "Prévia com foto": miniatura acima do campo
    Scenario(name: "whatsapp-cartao-foto", realNotch: true, frameHeight: 300, frameWidth: 440) { vm, _, _ in
        let mae = "554799990014@s.whatsapp.net"
        waCartaoCenario(vm, conta: waPes, jid: mae,
                        waMsg("k3", mae, de: mae, 9, 12, tipo: .imagem, texto: "As orquídeas floresceram!",
                              midia: waMidia("image/jpeg")),
                        miniatura: waPNG(NSColor(red: 0.36, green: 0.55, blue: 0.33, alpha: 1)))
    },
    // quadro "Agrupado": três mensagens seguidas viram um card só
    Scenario(name: "whatsapp-cartao-agrupado", realNotch: true, frameHeight: 300, frameWidth: 440) { vm, _, _ in
        let rafa = "554799990013@s.whatsapp.net"
        waCartaoCenario(vm, conta: waPes, jid: rafa,
                        waMsg("k4", rafa, de: rafa, 12, 20, texto: "Bora pedalar sábado cedo?"), contagem: 3)
    },
    // quadro "Campo em uso: a fila espera": rascunho no campo, com foco
    Scenario(name: "whatsapp-cartao-respondendo", realNotch: true, frameHeight: 300, frameWidth: 440) { vm, _, _ in
        waCartaoCenario(vm, conta: waBiz, jid: waMarina,
                        waMsg("k5", waMarina, de: waMarina, 14, 32, texto: "Fechado! Mando o briefing até sexta."))
        let k = WAChave(conta: waBiz, jid: waMarina)
        WhatsAppStore.shared.definirRascunho("Perfeito, obrigado!", para: k)
        WhatsAppStore.shared.campoEmUso = k
        vm.whatsappEditando = true
    },
    Scenario(name: "whatsapp-rascunho", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in
        // o estado do mockup já traz "Carlos, ajustei o orçamento de dezembro e…"
        waConversaCenario(vm, jid: waCarlos, [
            waMsg("c1", waCarlos, de: waCarlos, 11, 40, tipo: .documento,
                  midia: waMidia("application/pdf", nome: "Proposta-Seller-nov26.pdf", tamanho: 1_200_000)),
            waMsg("c2", waCarlos, de: waCarlos, 11, 47, texto: "Dá uma olhada quando puder."),
        ])
    },
    Scenario(name: "expanded-cor", realNotch: true) { vm, _, _ in
        CoresRecentes.shared.carregar(["#FF3B30", "#34C759", "#0A84FF", "#FFD60A", "#BF5AF2"])
        vm.setExpandedDirect(true)
        vm.secoes = [.cor]
        vm.focus = .cor
    },
    // o "streamdeck" da anotação: ferramentas, cores e ações no card
    Scenario(name: "foco-anotacao", realNotch: true) { vm, _, _ in
        vm.setExpandedDirect(true)
        vm.secoes = [.anotacao, .musica]
        vm.focus = .anotacao
    },
    Scenario(name: "foco-shelf", realNotch: true) { vm, _, _ in
        fakeShelfFiles().forEach { currentShelf.add($0) }
        vm.setExpandedDirect(true)
        vm.secoes = [.shelf, .musica]
        vm.focus = .shelf
    },
    // a pilha aberta: cabe numa página, sem o botão "Mais"
    Scenario(name: "foco-shelf-pilha", realNotch: true, frameHeight: 340) { vm, _, _ in
        currentShelf.add(fakePilhaFiles(7))
        currentShelf.abrirPilha(currentShelf.entradas[0])
        vm.setExpandedDirect(true)
        vm.secoes = [.shelf, .musica]
        vm.focus = .shelf
    },
    // pilha que não cabe: a décima célula vira "Mais" e a grade pagina
    Scenario(name: "foco-shelf-pilha-cheia", realNotch: true, frameHeight: 340) { vm, _, _ in
        currentShelf.add(fakePilhaFiles(20))
        currentShelf.abrirPilha(currentShelf.entradas[0])
        vm.setExpandedDirect(true)
        vm.secoes = [.shelf, .musica]
        vm.focus = .shelf
    },
    // conversão esperando confirmação: é o único estado da prateleira que
    // desenha miniatura do RESULTADO (não do original) e as duas linhas de preset
    Scenario(name: "shelf-preview-imagem", realNotch: true) { vm, _, _ in
        let origem = fakePNGFile()
        currentShelf.add(origem)
        currentShelf.startPreview(origem, to: .image(.jpeg))
        esperarPreview(currentShelf)
        vm.setExpandedDirect(true)
        vm.secoes = [.shelf, .musica]
        vm.focus = .shelf
    },
    Scenario(name: "shelf-preview-falha-salvar", realNotch: true) { vm, _, _ in
        let fm = FileManager.default
        let pasta = fm.temporaryDirectory.appendingPathComponent("snapshot-falha-\(UUID().uuidString)")
        try! fm.createDirectory(at: pasta, withIntermediateDirectories: true)
        let origem = pasta.appendingPathComponent("foto.png")
        try! fm.copyItem(at: fakePNGFile(), to: origem)
        currentShelf.startPreview(origem, to: .image(.jpeg))
        esperarPreview(currentShelf)
        try! fm.removeItem(at: pasta)
        currentShelf.confirmPreview()
        assert(currentShelf.preview?.failed == true)
        vm.setExpandedDirect(true)
        vm.secoes = [.shelf, .musica]
        vm.focus = .shelf
    },
    // atividade da API: anel na asinha (fechado) e linha no card (aberto)
    Scenario(name: "closed-activity", realNotch: false) { vm, _, _ in
        vm.activity = NotchActivity(
            id: "deploy", title: "Deploy zoi-studio", detail: "rsync…",
            progress: 0.42, updatedAt: Date())
    },
    Scenario(name: "closed-activity-music", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.activity = NotchActivity(
            id: "deploy", title: "Deploy zoi-studio", detail: "rsync…",
            progress: 0.42, updatedAt: Date())
    },
    // AirDrop recebendo com música tocando: símbolo azul no lugar da capa
    Scenario(name: "closed-airdrop-music", realNotch: true) { vm, media, _ in
        media.injectPreview(state: fakeState(), artwork: fakeArtwork())
        vm.activity = NotchActivity(
            id: "airdrop", title: "Recebendo por AirDrop", detail: "IMG_5640.MOV",
            progress: 0.42, updatedAt: Date())
    },
    // atividade sem progresso e sem música: a seção sobe sozinha na ordenação
    // (é a única com conteúdo) e a faixa fica com um ícone só
    Scenario(name: "foco-atividade-indeterminada", realNotch: true) { vm, _, _ in
        vm.activity = NotchActivity(
            id: "build", title: "Compilando Knobler", detail: "xcodebuild",
            progress: nil, updatedAt: Date())
        vm.setExpandedDirect(true)
    },
    Scenario(name: "notification", realNotch: true) { vm, _, _ in
        vm.activeNotification = NotchNotification(
            appName: "Finder",
            title: "Backup concluído",
            body: "O Time Machine terminou o backup de hoje às 14:32."
        )
    },
    Scenario(name: "notification-subtitulo", realNotch: true) { vm, _, _ in
        vm.activeNotification = NotchNotification(
            appName: "Finder", title: "Cópia concluída",
            body: "12 itens copiados para o disco externo",
            subtitle: "Backup de fotos")
    },
    // hover: o texto abre inteiro e o card cresce junto
    Scenario(name: "notification-aberta", realNotch: true, frameHeight: 360) { vm, _, _ in
        vm.activeNotification = NotchNotification(
            appName: "Finder", title: "Não foi possível concluir a cópia",
            body: "O item \"Relatório final.pdf\" não pôde ser copiado porque o disco de destino ficou sem espaço durante a operação. Libere espaço no disco externo e tente de novo; os 11 itens anteriores já foram copiados e continuam no destino.")
        vm.holdNotification(true)
    },
    // AirDrop recebido: miniatura no lugar do ícone e as três ações
    Scenario(name: "notification-airdrop-recebido", realNotch: true) { vm, _, _ in
        var n = NotchNotification(appName: "AirDrop", title: "Recebido", body: "IMG_5708.MOV",
                                  iconEmoji: "📥")
        n.thumbnail = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in
            NSColor.systemTeal.setFill(); r.fill(); return true
        }
        n.actionTitles = ["Abrir", "Mostrar no Finder", "Prateleira"]
        n.actionToken = UUID()
        vm.activeNotification = n
    },
    // app que não se identifica: sino, nunca WhatsApp
    Scenario(name: "notification-sem-app", realNotch: true) { vm, _, _ in
        vm.activeNotification = NotchNotification(
            appName: nil, title: "Acesso aos dados bloqueado",
            body: "Um app tentou acessar seus dados a partir de outros apps e foi bloqueado.")
    },
    // ponytail: do histórico, só o cenário vazio fica no harness — o populado
    // (ScrollView com itens) renderiza preto sólido no ImageRenderer offscreen,
    // ver CLAUDE.md. Um PNG preto é um falso gate, pior que não ter o cenário.
    //
    // frameHeight maior que o padrão 240: a seção de histórico tem altura
    // própria (chrome + a lista), e com 240 o PNG cortava a faixa do rodapé —
    // um gate que não mostra o rodapé não prova que o card coube.
    Scenario(name: "expanded-agentes", realNotch: true, frameHeight: 400) { vm, _, _ in
        let agora = Date()
        func sessao(_ id: String, _ nome: String, _ detalhe: String, _ e: AgentSession.State) -> AgentSession {
            AgentSession(id: id, name: nome, detail: detalhe, state: e, waitingFor: nil,
                         since: agora, processID: 1)
        }
        // dois anéis por provider: um confortável, outro com a semana esgotada
        func uso(_ id: String, _ curta: Double, _ semana: Double, reset: Double) -> ProviderSnapshot {
            ProviderSnapshot(id: id, displayName: id, glyph: id == "claude" ? .claude : .openai,
                fidelity: .official, status: .ok,
                windows: [LimitWindow(id: "primary", label: "5h", usedFraction: curta,
                                      resetsAt: agora.addingTimeInterval(reset)),
                          LimitWindow(id: "week", label: "7d", usedFraction: semana,
                                      resetsAt: agora.addingTimeInterval(3 * 86400))],
                headlineID: "primary", weeklyID: "week")
        }
        AgentesUso.shared.injetar(
            sessoes: [sessao("a", "knobler", "Terminal", .busy),
                      sessao("b", "site", "VS Code", .waiting),
                      sessao("c", "api", "Codex", .success)],
            uso: ["claude": uso("claude", 0.42, 0.18, reset: 2 * 3600),
                  "codex": uso("codex", 0.86, 1.0, reset: 40 * 60)],
            lidoEm: ["claude": agora, "codex": agora])
        vm.setExpandedDirect(true)
        vm.secoes = [.agentes, .musica]
        vm.focar(.agentes)
    },
    Scenario(name: "foco-historico-vazio", realNotch: true, frameHeight: 400) { vm, _, _ in
        vm.setExpandedDirect(true)
        vm.secoes = [.historico]
        vm.focar(.historico)
    },
    // Dados inteiramente sintéticos: nenhuma consulta ao calendário pessoal.
    Scenario(name: "lembretes-hoje", realNotch: true, frameHeight: 460) { vm, _, _ in configurarLembretes(vm, estado: "hoje") },
    Scenario(name: "lembretes-vazio", realNotch: true, frameHeight: 460) { vm, _, _ in configurarLembretes(vm, estado: "vazio") },
    Scenario(name: "lembretes-sem-permissao", realNotch: false, frameHeight: 460) { vm, _, _ in configurarLembretes(vm, estado: "sem-permissao") },
    Scenario(name: "lembretes-carregando", realNotch: true, frameHeight: 460) { vm, _, _ in configurarLembretes(vm, estado: "carregando") },
    Scenario(name: "lembretes-criar", realNotch: true, frameHeight: 460) { vm, _, _ in configurarLembretes(vm, estado: "criar") },
    Scenario(name: "lembretes-erro", realNotch: true, frameHeight: 460) { vm, _, _ in configurarLembretes(vm, estado: "erro") },
    Scenario(name: "agenda-hoje", realNotch: true, frameHeight: 400) { vm, _, _ in
        vm.setExpandedDirect(true)
        vm.secoes = [.musica, .agenda, .anotacao]
        vm.focar(.agenda)
        let dia = Calendar.current.startOfDay(for: Date())
        let agora = dia.addingTimeInterval(10 * 3600)
        vm.agenda = CalendarAgenda(dia: dia, atualizadoEm: agora, autorizado: true, eventos: [
            CalendarEvento(id: "dia", titulo: "Entrega do projeto", calendario: "Trabalho",
                inicio: dia, fim: Calendar.current.date(byAdding: .day, value: 1, to: dia)!, diaInteiro: true),
            CalendarEvento(id: "reuniao", titulo: "Revisão de design", calendario: "Equipe",
                inicio: agora.addingTimeInterval(-1800), fim: agora.addingTimeInterval(1800), diaInteiro: false),
            CalendarEvento(id: "planejamento", titulo: "Planejamento da próxima versão", calendario: "Trabalho",
                inicio: agora.addingTimeInterval(7200), fim: agora.addingTimeInterval(10800), diaInteiro: false),
            CalendarEvento(id: "fim", titulo: "Encerramento da semana", calendario: "Equipe",
                inicio: agora.addingTimeInterval(21600), fim: agora.addingTimeInterval(25200), diaInteiro: false),
        ])
    },
    Scenario(name: "agenda-vazia", realNotch: true, frameHeight: 400) { vm, _, _ in
        vm.setExpandedDirect(true)
        vm.secoes = [.agenda, .anotacao]
        vm.focar(.agenda)
        vm.agenda = CalendarAgenda(dia: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
                                   autorizado: true)
    },
    Scenario(name: "agenda-sem-permissao", realNotch: false, frameHeight: 400) { vm, _, _ in
        vm.setExpandedDirect(true)
        vm.secoes = [.agenda, .anotacao]
        vm.focar(.agenda)
        vm.agenda = CalendarAgenda()
    },
    Scenario(name: "agenda-criar", realNotch: true, frameHeight: 560) { vm, _, _ in
        configurarEditorAgenda(vm)
    },
    Scenario(name: "agenda-criar-dia-inteiro", realNotch: false, frameHeight: 540) { vm, _, _ in
        configurarEditorAgenda(vm)
        vm.agendaRascunho?.diaInteiro = true
    },
    Scenario(name: "agenda-criar-erro", realNotch: true, frameHeight: 560) { vm, _, _ in
        configurarEditorAgenda(vm)
        vm.agendaErro = CalendarErro.gravacao.localizedDescription
    },
    Scenario(name: "agenda-criar-sem-calendario", realNotch: true, frameHeight: 560) { vm, _, _ in
        configurarEditorAgenda(vm)
        vm.onCalendariosAgenda = { [] }
        vm.atualizarAgenda()
    },
    Scenario(name: "agenda-criar-tela-baixa", realNotch: false, frameHeight: 420) { vm, _, _ in
        configurarEditorAgenda(vm)
        vm.availableSize.height = 400
    },
    Scenario(name: "dictation-recording", realNotch: true) { vm, _, _ in
        vm.dictation = .recording(level: 0.6)
    },
    Scenario(name: "dictation-transcribing", realNotch: true) { vm, _, _ in
        vm.dictation = .transcribing
    },
    Scenario(name: "dictation-error", realNotch: false) { vm, _, _ in
        vm.dictation = .error("Sem acesso ao microfone")
    },
    // frameHeight maior que o default 240: a pergunta agora ocupa as linhas que
    // precisar e o card mede a própria altura — com 240 o PNG cortava a lista.
    Scenario(name: "ask-simple", realNotch: true, frameHeight: 420) { _, _, askStore in
        askStore.send(.enqueue(AskRequest(id: "s1", questions: [
            AskQuestion(
                question: "Qual abordagem seguir?", header: "Abordagem",
                multiSelect: false,
                options: [
                    AskOption(label: "Hook PreToolUse",
                              description: "Intercepta toda pergunta e envia pro notch",
                              preview: nil),
                    AskOption(label: "Servidor MCP",
                              description: "Tool dedicada configurada por projeto",
                              preview: nil),
                ])
        ], receivedAt: Date(timeIntervalSince1970: 1_000))))
    },
    Scenario(name: "ask-multiselect", realNotch: true, frameHeight: 420) { _, _, askStore in
        askStore.send(.enqueue(AskRequest(id: "s2", questions: [
            AskQuestion(
                question: "Quais checagens rodar?", header: "Validação",
                multiSelect: true,
                options: [
                    AskOption(label: "Build Release", description: "xcodebuild", preview: nil),
                    AskOption(label: "Snapshots", description: "harness visual", preview: nil),
                    AskOption(label: "E2E manual", description: "roteiro no app real", preview: nil),
                ])
        ], receivedAt: Date(timeIntervalSince1970: 1_000))))
    },
    Scenario(name: "ask-preview", realNotch: true) { _, _, askStore in
        askStore.send(.enqueue(AskRequest(id: "s3", questions: [
            AskQuestion(
                question: "Qual layout do card?", header: "Layout",
                multiSelect: false,
                options: [
                    AskOption(label: "Split",
                              description: "opções + preview",
                              preview: "+----------+-----------+\n| opções   | preview   |\n|          |  ascii    |\n+----------+-----------+"),
                    AskOption(label: "Empilhado",
                              description: "preview embaixo",
                              preview: "+----------------------+\n|        opções        |\n+----------------------+\n|       preview        |\n+----------------------+"),
                ])
        ], receivedAt: Date(timeIntervalSince1970: 1_000))))
    },
    Scenario(name: "ask-paged", realNotch: true) { _, _, askStore in
        let request = AskRequest(id: "s4", questions: [
            AskQuestion(question: "Pergunta um?", header: "Um", multiSelect: false,
                        options: [AskOption(label: "A", description: "", preview: nil)]),
            AskQuestion(question: "Pergunta dois de três?", header: "Dois", multiSelect: false,
                        options: [
                            AskOption(label: "Sim", description: "segue", preview: nil),
                            AskOption(label: "Não", description: "para", preview: nil),
                        ]),
            AskQuestion(question: "Pergunta três?", header: "Três", multiSelect: false,
                        options: [AskOption(label: "B", description: "", preview: nil)]),
        ], receivedAt: Date(timeIntervalSince1970: 1_000))
        askStore.send(.enqueue(request))
        // O cenário permanece na página 1 por uma transição de domínio real.
        askStore.send(.submit(labels: ["A"], text: nil))
    },
    Scenario(
        name: "agent-permission-compact", realNotch: true,
        agentRequest: AgentRequest(
            id: "permission-compact", agent: .claude, kind: .permission,
            title: "Permissão de comando",
            summary: "Executar git status para conferir as alterações locais antes de preparar a revisão.",
            details: "command: git status --short\ncwd: /Users/luccassilveira/Desktop/Projetos/knobler",
            source: .terminal, actions: [.allow, .deny]
        )
    ) { _, _, _ in },
    Scenario(
        name: "agent-permission-expanded", realNotch: true,
        agentRequest: AgentRequest(
            id: "permission-expanded", agent: .codex, kind: .permission,
            title: "Aplicar alteração de arquivo",
            summary: "O agente quer atualizar o painel do notch com o card de aprovação.",
            details: "path: Knobler/NotchView.swift\n--- a/Knobler/NotchView.swift\n+++ b/Knobler/NotchView.swift\n+ AgentRequestCard(request: request)",
            source: .cli, actions: [.allow, .allowForSession, .deny]
        ),
        agentRequestExpanded: true,
        frameHeight: 360
    ) { _, _, _ in },
    Scenario(
        name: "agent-question", realNotch: true,
        agentRequest: AgentRequest(
            id: "question", agent: .claude, kind: .question,
            title: "Escolha uma abordagem",
            summary: "Como o agente deve continuar com a integração?",
            source: .ide, actions: [.option("Manter o fluxo atual"), .option("Usar a ponte local")]
        )
    ) { _, _, _ in },
    Scenario(
        name: "agent-request-race", realNotch: true,
        agentRequest: AgentRequest(
            id: "race", agent: .codex, kind: .permission,
            title: "Corrida de resolução", summary: "A resposta externa chegou primeiro.",
            source: .cli, actions: [.allow, .deny]
        ),
        terminalFirstRace: true
    ) { _, _, _ in },
    Scenario(name: "pomodoro-focus", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .focus, runState: .running, remaining: 23 * 60 + 14, completedFocus: 1, cyclesUntilLong: 4)
    },
    // Últimos 5 min pro evento: a pílula cede o timer pro aviso do calendário.
    Scenario(name: "pomodoro-evento", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .focus, runState: .running, remaining: 23 * 60 + 14, completedFocus: 1, cyclesUntilLong: 4)
        vm.calendarAviso = CalendarAviso(titulo: "Retrospectiva", faltam: 4 * 60)
    },
    Scenario(name: "pomodoro-break", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .shortBreak, runState: .running, remaining: 4 * 60 + 32, completedFocus: 1, cyclesUntilLong: 4)
    },
    Scenario(name: "pomodoro-paused", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .focus, runState: .paused, remaining: 12 * 60 + 3, completedFocus: 1, cyclesUntilLong: 4)
    },
    Scenario(name: "pomodoro-waiting", realNotch: false) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .shortBreak, runState: .waiting, remaining: 5 * 60, completedFocus: 1, cyclesUntilLong: 4)
    },
    // pausa longa em espera NO NOTCH REAL: o rótulo mais comprido não pode
    // escorregar sob a câmera (asa esquerda ~85pt)
    Scenario(name: "pomodoro-waiting-long", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .longBreak, runState: .waiting, remaining: 15 * 60, completedFocus: 4, cyclesUntilLong: 4)
    },
    // card expandido (hover): foco/pausado/espera + confirmar que a música some
    Scenario(name: "pomodoro-card-focus", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .focus, runState: .running, remaining: 23 * 60 + 14, completedFocus: 1, cyclesUntilLong: 4)
        vm.setExpandedDirect(true)
    },
    Scenario(name: "pomodoro-card-paused", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .focus, runState: .paused, remaining: 12 * 60 + 3, completedFocus: 1, cyclesUntilLong: 4)
        vm.setExpandedDirect(true)
    },
    Scenario(name: "pomodoro-card-waiting", realNotch: true) { vm, _, _ in
        vm.pomodoro = PomodoroState(phase: .shortBreak, runState: .waiting, remaining: 5 * 60, completedFocus: 1, cyclesUntilLong: 4)
        vm.setExpandedDirect(true)
    },
    // AirPods: ilha de conexão, card (hover), bateria baixa, modelo
    // desconhecido e fone sem leitura de um lado.
    Scenario(name: "airpods-island", realNotch: true) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 82, case_: 31, model: .pro)
        vm.airpodsIsland = true
    },
    Scenario(name: "airpods-island-external", realNotch: false) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 82, case_: 31, model: .pro)
        vm.airpodsIsland = true
    },
    Scenario(name: "airpods-connect", realNotch: true) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31, model: .pro)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-connect-external", realNotch: false) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 90, right: 89, case_: 31, model: .pro)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-low", realNotch: false) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods Pro", left: 8, right: 74, case_: nil, model: .pro)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-gen3", realNotch: true) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "AirPods", left: 64, right: nil, case_: 100, model: .gen3)
        vm.airpodsCard = true
    },
    Scenario(name: "airpods-unknown", realNotch: true) { vm, _, _ in
        vm.airpods = AirPodsBattery(name: "Fone Bluetooth", left: 50, right: 50, case_: nil)
        vm.airpodsCard = true
    },
    // Update: card de versão nova e o estado de instalação.
    Scenario(name: "update-card", realNotch: true) { vm, _, _ in
        vm.update = .available(Release(
            version: "0.9.0",
            notes: "Fixed\nDitado não cai mais a cada release",
            url: URL(string: "https://github.com/luccas-silveira/knobler/releases/tag/v0.9.0")!,
            asset: nil))
        vm.updateCard = true
    },
    Scenario(name: "update-installing", realNotch: true) { vm, _, _ in
        vm.update = .installing
        vm.updateCard = true
    },
]

MainActor.assumeIsolated {
// desligar a nota copia o texto pro clipboard: sem este desvio o harness
// torraria o que quem roda `snapshot.sh` tinha copiado
QuickNote.shared.pasteboard = NSPasteboard(name: .init("knobler.snapshot"))
// mesmo espírito pro histórico, que agora persiste: sem soltar o arquivo, as
// notificações falsas dos cenários seriam gravadas no histórico REAL de quem
// roda o harness. Tem que vir antes do primeiro cenário.
NotificationHistory.shared.arquivo = nil
// a ponte de verdade fica fora: foto e bolhas que a seção do WhatsApp pedir vão
// para uma porta sem ninguém (registro em memória, nada gravado). Tem que vir
// antes do primeiro `WhatsAppStore.shared`/`WAFotoCache.shared`.
UserDefaults.standard.register(defaults: [WAConfig.chavePorta: 1])
for scenario in scenarios {
    // ShelfStore() relê o UserDefaults — sem o clear, os arquivos fake de um
    // cenário vazavam pros seguintes
    currentShelf.cancelPreview()
    currentShelf = ShelfStore()
    currentShelf.clear()
    let vm = NotchViewModel()
    let media = MediaController()
    let askStore = AskStore(dependencies: .init(
        resolve: { _, _ in },
        cancel: { _ in }
    ))
    let arbiter = scenario.terminalFirstRace ? SnapshotAgentArbiter() : nil
    let agentRequestStore = AgentRequestStore(
        resolveRemote: { _, action in
            guard let arbiter else { return false }
            return await MainActor.run { arbiter.resolve(action: action, responder: .nob) }
        },
        dismissRemote: { _ in }
    )
    media.injectPreview(state: nil, artwork: nil)
    vm.hasRealNotch = scenario.realNotch
    vm.notchSize = scenario.realNotch
        ? CGSize(width: 200, height: 32)
        : CGSize(width: 190, height: 30)
    // o histórico é singleton: sem zerar entre cenários, o que um cenário
    // grava vaza pro próximo (o histórico entraria na faixa de todo card)
    NotificationHistory.shared.prune(now: .distantFuture)
    AppSettings.shared.acoesRapidas = []
    CoresRecentes.shared.limpar()
    AgentesUso.shared.injetar(sessoes: [], uso: [:])
    // mesma razão: a nota também é singleton, e o pontinho dela apareceria em
    // todo notch fechado depois do cenário que a liga
    QuickNote.shared.active = false
    TecladoBloqueado.shared._simularAtivo(false)
    Monitores.shared.displays = []
    // o WhatsApp também é singleton: sem isso o estado de um cenário vaza pro
    // seguinte. O harness nunca chama start(), então não toca a ponte real.
    WhatsAppStore.shared._zerar()
    // anéis desenhados já no nível final: o ImageRenderer não roda a entrada
    BatteryRingView.animaEntrada = false
    scenario.configure(vm, media, askStore)
    if let request = scenario.agentRequest {
        agentRequestStore.send(.enqueue(request))
        if scenario.terminalFirstRace, let arbiter {
            precondition(arbiter.resolve(action: .deny, responder: .terminal))
            agentRequestStore.send(.resolve(id: request.id, action: .deny, responder: .terminal))
            var nobAccepted: Bool?
            Task { @MainActor in
                nobAccepted = await agentRequestStore.resolve(id: request.id, action: .allow)
            }
            let deadline = Date().addingTimeInterval(1)
            while nobAccepted == nil && RunLoop.current.run(mode: .default, before: deadline) && Date() < deadline {}
            precondition(nobAccepted == false)
            precondition(arbiter.attempts == [.terminal, .nob])
            precondition(arbiter.winner == AgentRequestResult(action: .deny, responder: .terminal))
            precondition(agentRequestStore.state.active == nil)
            precondition(agentRequestStore.state.results[request.id] == arbiter.winner)
            print("agent race: terminal deny won; NOB allow rejected")
        } else if let result = scenario.resolveAgentRequest {
            agentRequestStore.send(.resolve(id: request.id, action: result.0, responder: result.1))
        }
    }

    var agendaWindow: NotchWindow?
    // wallpaper claro atrás: revela a silhueta e as bordas da forma
    let view = ZStack(alignment: .top) {
        LinearGradient(
            colors: [Color(red: 0.72, green: 0.78, blue: 0.88),
                     Color(red: 0.90, green: 0.86, blue: 0.80)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        NotchView(
            vm: vm, askStore: askStore, agentRequestStore: agentRequestStore,
            media: media, levels: SystemAudioLevels(), shelf: currentShelf,
            dropTargetsEnabled: false,
            agentRequestInitiallyExpanded: scenario.agentRequestExpanded,
            onKeyboardEligibilityChanged: { agendaWindow?.allowsKeyboard = $0 })
            // a NotchView lê o MessageStore do ambiente só pra saber se há
            // conversa; sem injetar, o SwiftUI derruba o harness
            .environmentObject(MessageStore(carregando: false))
    }
    .frame(width: scenario.frameWidth, height: scenario.frameHeight)

    let png: Data
    if scenario.name.hasPrefix("agenda-") || scenario.name.hasPrefix("lembretes-") || scenario.name.hasPrefix("monitores-")
        || scenario.name.hasPrefix("whatsapp-") {
        // ScrollView usa backing AppKit e sai preta no ImageRenderer. Uma
        // janela sintética permite capturar a lista real, sem eventos pessoais.
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view.transaction { $0.disablesAnimations = true; $0.animation = nil })
        let window = NotchWindow(contentRect: NSRect(x: 100, y: 100, width: scenario.frameWidth, height: scenario.frameHeight),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        agendaWindow = window
        vm.onAgendaKeyboard = { [weak window] in window?.makeKey() }
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            fatalError("Não foi possível capturar a agenda")
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            fatalError("Não foi possível codificar a agenda")
        }
        png = data
        if scenario.name == "agenda-criar" && telaBloqueada() {
            // O PNG acima já saiu; só o teste de teclado fica de fora.
            print("agenda: teclado NÃO testado — tela bloqueada, nenhuma janela vira key")
        } else if scenario.name == "agenda-criar" {
            precondition(window.allowsKeyboard && window.isKeyWindow, "Editor precisa aceitar teclado")
            guard let editor = window.firstResponder as? NSTextView else {
                fatalError("Título não recebeu o foco de edição")
            }
            editor.selectAll(nil)
            editor.insertText("Título digitado no teste", replacementRange: NSRange(location: NSNotFound, length: 0))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            precondition(vm.agendaRascunho?.titulo == "Título digitado no teste", "Digitação perdeu o binding")
            let tab = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
            window.sendEvent(tab)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            precondition(window.firstResponder != nil && vm.expanded, "Tab não pode fechar o editor")
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
            window.sendEvent(escape)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            precondition(!vm.expanded && vm.agendaRascunho?.titulo == "Título digitado no teste",
                         "Escape deve recolher e preservar o rascunho")
            print("agenda: teclado, Tab e Escape ok na janela nativa")
        }
        window.close()
    } else {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            print("FALHOU: \(scenario.name)")
            exit(1)
        }
        png = data
    }
    let path = "\(outputDir)/\(scenario.name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("ok \(path)")
}

// Cenários de Mensagens LAN — precisam de LANMessaging/MessageStore no
// ambiente, que os demais cenários não usam.
@MainActor func renderMessageScenario(
    _ name: String, realNotch: Bool, frameHeight: CGFloat = 240,
    configure: (NotchViewModel, LANMessaging, MessageStore) -> Void
) {
    let vm = NotchViewModel()
    let media = MediaController()
    let askStore = AskStore(dependencies: .init(
        resolve: { _, _ in },
        cancel: { _ in }
    ))
    let agentRequestStore = AgentRequestStore(
        resolveRemote: { _, _ in false }, dismissRemote: { _ in }
    )
    media.injectPreview(state: nil, artwork: nil)
    let lan = LANMessaging()
    let store = MessageStore(carregando: false)
    vm.hasRealNotch = realNotch
    vm.notchSize = realNotch
        ? CGSize(width: 200, height: 32)
        : CGSize(width: 190, height: 30)
    configure(vm, lan, store)

    let view = ZStack(alignment: .top) {
        LinearGradient(
            colors: [Color(red: 0.72, green: 0.78, blue: 0.88),
                     Color(red: 0.90, green: 0.86, blue: 0.80)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    NotchView(
        vm: vm, askStore: askStore, agentRequestStore: agentRequestStore,
        media: media, levels: SystemAudioLevels(), shelf: currentShelf,
        dropTargetsEnabled: false)
            .environmentObject(lan)
            .environmentObject(store)
    }
    .frame(width: 560, height: frameHeight)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { print("FALHOU: \(name)"); exit(1) }
    let path = "\(outputDir)/\(name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("ok \(path)")
}

// Linhas do histórico fora da lista: a lista é um ScrollView e sai preta
// offscreen, mas a linha sozinha renderiza — é o gate do ícone.
@MainActor func renderHistoryRows(_ name: String, _ itens: [NotchNotification]) {
    let view = VStack(alignment: .leading, spacing: 6) {
        ForEach(itens) { HistoryRow(item: $0, mostraX: false, onRemove: {}) }
    }
    .padding(16)
    .frame(width: 430, alignment: .leading)
    .background(Color.black)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { print("FALHOU: \(name)"); exit(1) }
    let path = "\(outputDir)/\(name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("ok \(path)")
}

// Dois cards da vitrine de Ajustes › Plugins (Mensagens e WhatsApp), lado a
// lado como na grade do painel. O painel inteiro é um ScrollView (sai preto
// offscreen); o card sozinho renderiza.
@MainActor func renderCardsDaVitrine(_ name: String) {
    let card = { (id: PluginID, pilula: Pilula) -> AnyView in
        let ficha = PluginRegistry.ficha(id)!
        return AnyView(CardPeca(nome: ficha.nome, descricao: ficha.descricao,
                                simbolo: ficha.simbolo, cor: corDaPeca(id)) { pilula }
            .frame(width: 160))
    }
    let view = HStack(alignment: .top, spacing: 12) {
        card(.mensagens, Pilula(texto: "ABRIR"))
        card(.whatsapp, Pilula(texto: "INSTALAR", cheia: true))
    }
    .padding(16)
    .background(Color(white: 0.93))
    .environment(\.colorScheme, .light)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { print("FALHOU: \(name)"); exit(1) }
    let path = "\(outputDir)/\(name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("ok \(path)")
}

// Overlay do Descanso (bloqueio forçado) — render à parte, não usa NotchView.
@MainActor func renderOverlay(_ name: String, label: String, hold: Double) {
    let model = BreakOverlayModel()
    model.endDate = Date().addingTimeInterval(872)   // ~14:32 no contador
    model.label = label
    model.holdProgress = hold
    let view = ZStack {
        LinearGradient(
            colors: [Color(red: 0.72, green: 0.78, blue: 0.88),
                     Color(red: 0.90, green: 0.86, blue: 0.80)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        BreakOverlayView(model: model)
    }
    .frame(width: 560, height: 360)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { print("FALHOU: \(name)"); exit(1) }
    let path = "\(outputDir)/\(name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("ok \(path)")
}
// frameHeight maior que o padrão 240: a seção de Mensagens rende mais alta que
// as demais (ver NotchMetrics.alturaDaSecao) e cortava embaixo com o frame default.
renderMessageScenario("messages-online", realNotch: true, frameHeight: 390) { vm, lan, _ in
    vm.setExpandedDirect(true)
    vm.secoes = [.mensagens]
    vm.focar(.mensagens)
    lan.injectPreview(peers: [
        Peer(id: "p1", name: "Marina", endpoint: .hostPort(host: "127.0.0.1", port: 1)),
        Peer(id: "p2", name: "Diego", endpoint: .hostPort(host: "127.0.0.1", port: 2)),
    ])
}
renderMessageScenario("messages-incoming", realNotch: true) { vm, _, _ in
    vm.incoming = NotchViewModel.IncomingMessage(
        peerID: "p1", name: "Marina", text: "Bora almoçar daqui a pouco?", allowReply: true)
}

// settings-*.png e mapping-editor.png NÃO são gerados por este harness: o
// SettingsView usa NavigationSplitView e o MappingEditorView usa HSplitView,
// e nenhum dos dois renderiza via ImageRenderer offscreen neste toolchain —
// vira um ícone de "proibido" no lugar do conteúdo (confirmado com um repro
// mínimo: até um NavigationSplitView vazio quebra do mesmo jeito). Esses 9
// PNGs são capturados manualmente: rodar
//   Knobler.app/Contents/MacOS/Knobler --ajustes=<painel>
// (painéis: geral, notch, desenho, ditado, pomodoro, lembretes, descanso, webhooks,
// mensagens) e tirar o screenshot da janela real. mapping-editor.png sai de
// dentro do painel "webhooks" clicando "…" → "Mapear campos…" num perfil.

// lembretes-janela.png e lembretes-janela-editor.png também exigem captura
// nativa da janela: cacheDisplay perde a composição dos controles AppKit,
// produzindo botões brancos e símbolos incorretos. Usar AppleRemindersUI.show()
// com AppleRemindersStore(snapshot: true), dados sintéticos e captura do ID da
// janela pelo macOS; não consultar nem modificar lembretes pessoais.

renderCardsDaVitrine("whatsapp-vitrine")
renderOverlay("descanso", label: "Almoço", hold: 0)
renderOverlay("descanso-hold", label: "Almoço", hold: 0.6)
renderHistoryRows("historico-linhas", [
    NotchNotification(appName: "Finder", title: "Backup concluído", body: "Time Machine terminou."),
    NotchNotification(appName: "Finder", title: "Cópia concluída", body: "12 itens", subtitle: "Backup de fotos"),
    NotchNotification(appName: nil, title: "Webhook", body: "deploy ok", iconEmoji: "🚀"),
    NotchNotification(appName: nil, title: "Sem origem", body: "cai no sino"),
])
// mídias de cor sólida dos cenários de conversa do WhatsApp
try? FileManager.default.removeItem(at: waPastaDeMidia)
}
