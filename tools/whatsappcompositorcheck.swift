// Gate da etapa 25 do WhatsApp: o compositor da conversa e as ações da bolha.
// Modelo puro em Knobler/WhatsApp/WhatsAppCompositor.swift (`WACompositor`:
// modo do compositor, texto e rótulo da citação, as 6 reações, o emoji que
// sai ao tocar numa reação e o tempo da gravação); no WhatsAppStore, citação e
// anexo pendente por conversa; no NotchViewModel, a barra de reações por tela.
//
//   ver a linha `swift_teste tools/whatsappcompositorcheck.swift $VM_FONTES
//   $WA_NUCLEO Knobler/WhatsApp/WhatsAppCartao.swift
//   Knobler/WhatsApp/WhatsAppApresentacao.swift
//   Knobler/WhatsApp/WhatsAppCompositor.swift` em tools/check.sh.
//
// O que se prova (o que quem usa vê):
//   - o compositor troca microfone por avião quando há texto (espaços não
//     contam) ou anexo; gravando e ditando têm desenho próprio;
//   - a faixa "Respondendo a …" diz de quem é e o que é a mensagem citada;
//   - tocar na reação que já é minha a remove (emoji vazio vai à ponte);
//   - citação e anexo ficam presos à conversa: sobrevivem a fechar a conversa
//     e o notch, e não vazam para outra conversa;
//   - Enter envia: o `citar` vai com o id, e o campo (rascunho) e a faixa de
//     citação esvaziam na hora, sem esperar a ponte responder — quem limpa é o
//     store, dentro de `enviarTexto`/`enviarAnexo`;
//   - o anexo pendente sai com o texto do campo como legenda, e some do campo;
//   - a barra de reações é por tela: trocar de conversa, Esc e fechar o notch
//     a fecham; a outra tela não muda;
//   - `_zerar()` também esquece citações e anexos (o snapshot reaproveita o
//     `WhatsAppStore.shared` entre cenários);
//   - a ligação que o check.sh não compila: views, fontes do snapshot e os
//     quatro cenários whatsapp-citando-reacoes/gravando/ditando/rascunho.
//
// Nada sai pela rede: o cliente fala com um transporte falso que responde por
// caminho e grava cada pedido. A chave mora numa pasta de NSTemporaryDirectory();
// a chave de verdade da ponte nunca é lida, e o `WhatsAppStore.shared` não é
// tocado. Roda da raiz do repo (o check.sh faz `cd` para lá).

import AppKit

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappcompositorcheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - números do teste (fictícios, como no mockup)

private let A = "554791744143"                      // conta
private let EU = A + "@s.whatsapp.net"
private let X = "554799990010@s.whatsapp.net"       // Marina Duarte (individual)
private let Y = "554799990011@s.whatsapp.net"       // Carlos (individual)
private let G = "120363000000000001@g.us"           // Projeto Aurora (grupo)
private let ANA = "554799000001@s.whatsapp.net"

private let kX = WAChave(conta: A, jid: X)
private let kY = WAChave(conta: A, jid: Y)
private let kG = WAChave(conta: A, jid: G)

private func msg(_ id: String, conversa: String, remetente: String, nome: String? = nil,
                 deMim: Bool = false, tipo: WATipoMensagem = .texto, texto: String = "",
                 midia: WAMidia? = nil) -> WAMensagem {
    WAMensagem(id: id, conversa: conversa, remetente: remetente, remetenteNome: nome,
               deMim: deMim, ts: 1_762_270_000, tipo: tipo, texto: texto, midia: midia,
               citacao: nil, reacoes: [], editada: nil, apagada: nil, status: nil)
}

private func midia(_ mime: String, nome: String, segundos: Int? = nil) -> WAMidia {
    WAMidia(mimetype: mime, nome: nome, tamanho: 120_000, segundos: segundos,
            miniatura: false, baixada: true)
}

private func conversa(_ jid: String, _ nome: String, tipo: WATipoConversa) -> WAConversa {
    WAConversa(jid: jid, jids: [jid], tipo: tipo, nome: nome, naoLidas: 0,
               marcadaNaoLida: false, ts: 1_762_270_000, ultima: nil)
}

private let cvX = conversa(X, "Marina Duarte", tipo: .individual)
private let cvG = conversa(G, "Projeto Aurora", tipo: .grupo)

// remetenteNome "Marina" ≠ nome da conversa: o individual usa o da conversa
private let m7 = msg("m7", conversa: X, remetente: X, nome: "Marina",
                     texto: "Consegue me mandar o orçamento de dezembro?")
private let m8 = msg("m8", conversa: X, remetente: EU, deMim: true, texto: "Mando hoje")

// MARK: - modelo puro

private func modo() {
    func m(_ g: Bool, _ d: Bool, _ t: String, _ a: Bool) -> WAModoDoCompositor {
        WACompositor.modo(gravando: g, ditando: d, texto: t, temAnexo: a)
    }
    let vazio = WAModoDoCompositor.normal(mostraEnviar: false, mostraMicrofone: true)
    let cheio = WAModoDoCompositor.normal(mostraEnviar: true, mostraMicrofone: false)

    exigir(m(true, false, "", false) == .gravando, "gravando: o compositor vira a caixa de gravação, veio \(m(true, false, "", false))")
    exigir(m(true, false, "oi", true) == .gravando, "gravando com texto e anexo ainda é .gravando, veio \(m(true, false, "oi", true))")
    exigir(m(true, true, "", false) == .gravando, "gravando vence o ditado, veio \(m(true, true, "", false))")

    exigir(m(false, true, "", false) == .ditando, "ditando com o campo vazio: .ditando, veio \(m(false, true, "", false))")
    exigir(m(false, true, "Pode subir o corte de 15 s ainda hoje", false) == .ditando,
           "ditando com texto no campo: .ditando (\"Ouvindo\" ao lado do texto), veio \(m(false, true, "Pode subir o corte de 15 s ainda hoje", false))")

    exigir(m(false, false, "", false) == vazio, "campo vazio sem anexo: microfone, sem avião; veio \(m(false, false, "", false))")
    exigir(m(false, false, "   ", false) == vazio, "texto só com espaços conta como vazio; veio \(m(false, false, "   ", false))")
    exigir(m(false, false, "oi", false) == cheio, "com texto: avião, sem microfone; veio \(m(false, false, "oi", false))")
    exigir(m(false, false, "  oi ", false) == cheio, "texto com espaços em volta ainda é texto; veio \(m(false, false, "  oi ", false))")
    exigir(m(false, false, "", true) == cheio, "com anexo e sem texto: avião, sem microfone; veio \(m(false, false, "", true))")
    exigir(m(false, false, "   ", true) == cheio, "com anexo e só espaços: avião; veio \(m(false, false, "   ", true))")
}

private func textoDaCitacao() {
    func t(_ m: WAMensagem) -> String { WACompositor.textoDaCitacao(m) }
    let casos: [(String, WAMensagem, String)] = [
        ("texto", m7, "Consegue me mandar o orçamento de dezembro?"),
        ("imagem", msg("i", conversa: X, remetente: X, tipo: .imagem, midia: midia("image/jpeg", nome: "IMG_0412.jpg")), "Foto"),
        ("vídeo", msg("v", conversa: X, remetente: X, tipo: .video, midia: midia("video/mp4", nome: "corte.mp4", segundos: 15)), "Vídeo"),
        ("documento", msg("d", conversa: X, remetente: X, tipo: .documento, midia: midia("application/pdf", nome: "orcamento-dezembro.pdf")), "orcamento-dezembro.pdf"),
        ("áudio", msg("a", conversa: X, remetente: X, tipo: .audio, midia: midia("audio/mpeg", nome: "musica.mp3", segundos: 30)), "Áudio"),
        ("voz", msg("z", conversa: X, remetente: X, tipo: .voz, midia: midia("audio/ogg; codecs=opus", nome: "", segundos: 12)), "Áudio"),
        ("figurinha", msg("f", conversa: X, remetente: X, tipo: .figurinha, midia: midia("image/webp", nome: "")), "Figurinha"),
        // tipo que o Knobler não desenha (mídia indisponível na citação)
        ("indisponível", msg("o", conversa: X, remetente: X, tipo: .outro("enquete")), "Mídia"),
    ]
    for (nome, m, esperado) in casos {
        exigir(t(m) == esperado, "textoDaCitacao(\(nome)): esperado \"\(esperado)\", veio \"\(t(m))\"")
    }
}

private func rotuloDaCitacao() {
    func r(_ m: WAMensagem, _ c: WAConversa) -> String { WACompositor.rotuloDaCitacao(m: m, conversa: c) }
    exigir(r(m8, cvX) == "Respondendo a você", "minha mensagem citada: \"Respondendo a você\", veio \"\(r(m8, cvX))\"")
    let minhaNoGrupo = msg("g0", conversa: G, remetente: EU, nome: "Luccas Silveira", deMim: true, texto: "fechado")
    exigir(r(minhaNoGrupo, cvG) == "Respondendo a você", "minha no grupo: \"Respondendo a você\", veio \"\(r(minhaNoGrupo, cvG))\"")
    let daAna = msg("g1", conversa: G, remetente: ANA, nome: "Ana Ribeiro", texto: "subi o arquivo")
    exigir(r(daAna, cvG) == "Respondendo a Ana Ribeiro",
           "de outro no grupo: \"Respondendo a <remetenteNome>\", veio \"\(r(daAna, cvG))\"")
    exigir(r(m7, cvX) == "Respondendo a Marina Duarte",
           "individual: \"Respondendo a <nome da conversa>\" (não o remetenteNome), veio \"\(r(m7, cvX))\"")
}

private func reacoes() {
    exigir(WACompositor.reacoes == ["👍", "❤️", "😂", "😮", "😢", "🙏"],
           "as 6 reações, nesta ordem: veio \(WACompositor.reacoes)")
    let e = WACompositor.emojiParaEnviar
    exigir(e("👍", nil) == "👍", "sem reação minha, tocar 👍 envia 👍; veio \"\(e("👍", nil))\"")
    exigir(e("👍", "👍") == "", "tocar na reação que já é minha remove (emoji vazio); veio \"\(e("👍", "👍"))\"")
    exigir(e("❤️", "👍") == "❤️", "tocar em outra troca a reação; veio \"\(e("❤️", "👍"))\"")
}

private func tempoDeGravacao() {
    let t0 = Date(timeIntervalSince1970: 1_762_270_000)
    func t(_ s: TimeInterval) -> String { WACompositor.tempoDeGravacao(inicio: t0, agora: t0.addingTimeInterval(s)) }
    for (s, esperado) in [(0.0, "0:00"), (9, "0:09"), (12, "0:12"), (12.4, "0:12"), (65, "1:05"), (600, "10:00")] {
        exigir(t(s) == esperado, "tempoDeGravacao(\(s) s): esperado \"\(esperado)\", veio \"\(t(s))\"")
    }
}

// MARK: - transporte falso

private func js(_ s: String?) -> String {
    guard let s else { return "null" }
    let d = try! JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
    let t = String(decoding: d, as: UTF8.self)
    return String(t.dropFirst().dropLast())
}

private struct Pedido {
    let metodo: String
    let caminho: String
    let query: [String: String]
    let corpo: [String: Any]
}

private final class TransporteFalso: WATransporte {
    private let trava = NSLock()
    private var _pedidos: [Pedido] = []
    private var _segurar = false
    private var _falhar = false
    private var enviados = 0

    var pedidos: [Pedido] { trava.lock(); defer { trava.unlock() }; return _pedidos }
    func de(_ caminho: String) -> [Pedido] { pedidos.filter { $0.caminho == caminho } }
    /// Enquanto `true`, `POST /v1/enviar/*` não responde: é o "enviando".
    var segurar: Bool {
        get { trava.lock(); defer { trava.unlock() }; return _segurar }
        set { trava.lock(); _segurar = newValue; trava.unlock() }
    }
    /// O próximo `POST /v1/enviar/texto` responde 502.
    var falhar: Bool {
        get { trava.lock(); defer { trava.unlock() }; return _falhar }
        set { trava.lock(); _falhar = newValue; trava.unlock() }
    }

    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let comps = URLComponents(url: pedido.url!, resolvingAgainstBaseURL: false)!
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] { q[item.name] = item.value ?? "" }
        let corpo = pedido.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let p = Pedido(metodo: pedido.httpMethod ?? "GET", caminho: comps.path, query: q, corpo: corpo)
        registrar(p)

        if p.caminho.hasPrefix("/v1/enviar/") {
            var n = 0
            while segurar && n < 10_000 { try? await Task.sleep(nanoseconds: 1_000_000); n += 1 }
        }
        let (status, texto) = responder(p)
        let r = HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "application/json"])!
        return (Data(texto.utf8), r)
    }

    private func registrar(_ p: Pedido) { trava.lock(); _pedidos.append(p); trava.unlock() }

    private func proximo() -> Int? {
        trava.lock(); defer { trava.unlock() }
        if _falhar { _falhar = false; return nil }
        enviados += 1
        return enviados
    }

    private func mensagem(_ id: String, _ p: Pedido, tipo: String, texto: String, midia: String) -> String {
        #"{"id": \#(js(id)), "conversa": \#(js(p.corpo["para"] as? String)), "remetente": \#(js(EU)), "remetente_nome": null, "de_mim": true, "ts": \#(Int(Date().timeIntervalSince1970)), "tipo": \#(js(tipo)), "texto": \#(js(texto)), "midia": \#(midia), "citacao": null, "reacoes": [], "editada": null, "apagada": null, "status": "enviada"}"#
    }

    private func responder(_ p: Pedido) -> (Int, String) {
        let ref = js(p.corpo["ref"] as? String)
        switch (p.metodo, p.caminho) {
        case ("POST", "/v1/enviar/texto"):
            guard let n = proximo() else {
                return (502, #"{"ok": false, "erro": "whatsapp_recusou", "detalhe": "recusado"}"#)
            }
            let m = mensagem("3EB-TXT-\(n)", p, tipo: "texto", texto: p.corpo["texto"] as? String ?? "", midia: "null")
            return (200, #"{"ok": true, "ref": \#(ref), "mensagem": \#(m)}"#)
        case ("POST", "/v1/enviar/midia"):
            guard let n = proximo() else {
                return (502, #"{"ok": false, "erro": "whatsapp_recusou", "detalhe": "recusado"}"#)
            }
            let tipo = p.corpo["tipo"] as? String ?? "documento"
            let md = #"{"mimetype": "application/pdf", "nome": \#(js(p.corpo["nome"] as? String)), "tamanho": 1000, "segundos": null, "miniatura": false, "baixada": true}"#
            let m = mensagem("3EB-ANX-\(n)", p, tipo: tipo, texto: p.corpo["legenda"] as? String ?? "", midia: md)
            return (200, #"{"ok": true, "ref": \#(ref), "mensagem": \#(m)}"#)
        case ("POST", "/v1/reagir"):
            return (200, #"{"ok": true}"#)
        case ("POST", "/v1/lida"):
            return (200, #"{"ok": true, "marcadas": 1}"#)
        case ("GET", "/v1/mensagens"):
            return (200, #"{"ok": true, "conversa": \#(js(p.query["conversa"])), "mensagens": [], "antes": null}"#)
        default:
            return (404, #"{"ok": false, "erro": "rota_inexistente", "detalhe": "x"}"#)
        }
    }
}

// MARK: - montagem

private let pastaBase = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("whatsappcompositorcheck-\(getpid())", isDirectory: true)
private let arquivoDaChave: URL = {
    let u = pastaBase.appendingPathComponent("api-key")
    try! FileManager.default.createDirectory(at: pastaBase, withIntermediateDirectories: true)
    try! Data("chave-de-teste\n".utf8).write(to: u)
    return u
}()

@MainActor
private final class Montagem {
    let t = TransporteFalso()
    let store: WhatsAppStore

    init() {
        store = WhatsAppStore(cliente: WACliente(porta: 18099, caminhoDaChave: arquivoDaChave, transporte: t))
        store.pastaDeEnvio = pastaBase.appendingPathComponent("envio", isDirectory: true)
    }
}

@MainActor
private func esperar(_ desc: String, linha: UInt = #line, _ cond: () -> Bool) async {
    for _ in 0..<3000 {
        if cond() { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    exigir(cond(), "esperou 3 s e não aconteceu: \(desc)", linha: linha)
}

private func arquivoDeTeste(_ nome: String) -> URL {
    let pasta = pastaBase.appendingPathComponent("origem", isDirectory: true)
    try! FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
    let u = pasta.appendingPathComponent(nome)
    try! Data("%PDF-1.4 orçamento\n".utf8).write(to: u)
    return u
}

// MARK: - store: citação

/// A faixa de citação é da conversa: guarda o id e o remetente, não aparece em
/// outra conversa, sobrevive a fechar e reabrir a conversa e o notch, troca
/// quando cito outra, some no x/Esc.
@MainActor
private func citacaoPorConversa() async {
    let m = Montagem()
    let s = m.store
    exigir(s.citacao(kX) == nil, "conversa nova não nasce citando nada")

    s.citar(m7, em: kX)
    let c = s.citacao(kX)
    exigir(c?.id == "m7", "citar(m7): citacao(k).id deveria ser m7, veio \(String(describing: c?.id))")
    exigir(c?.remetente == X, "citar(m7): remetente deveria ser \(X), veio \(String(describing: c?.remetente))")
    exigir(c?.texto == m7.texto, "citar(m7): texto deveria ser o da mensagem, veio \(String(describing: c?.texto))")
    exigir(s.citacao(kY) == nil, "a citação de uma conversa apareceu em outra: \(String(describing: s.citacao(kY)))")

    // fechar e reabrir a conversa (e o notch, que vive no VM) não perde a citação
    await s.abrir(kX)
    s.fechar(kX)
    let vm = NotchViewModel()
    vm.setExpandedDirect(true)
    vm.whatsappConversaAberta = kX.texto
    vm.setExpandedDirect(false)
    await s.abrir(kX)
    exigir(s.citacao(kX)?.id == "m7", "a citação sumiu ao fechar e reabrir: \(String(describing: s.citacao(kX)))")
    s.fechar(kX)

    s.citar(m8, em: kX)
    exigir(s.citacao(kX)?.id == "m8", "citar outra mensagem troca a citação; veio \(String(describing: s.citacao(kX)?.id))")

    s.citar(m7, em: kY)  // fixture: citação na outra conversa, que não pode ser tocada
    s.cancelarCitacao(kX)
    exigir(s.citacao(kX) == nil, "cancelarCitacao (x/Esc) não apagou: \(String(describing: s.citacao(kX)))")
    exigir(s.citacao(kY)?.id == "m7", "cancelarCitacao(kX) apagou a citação de outra conversa")
}

/// Enter com citação: o `citar` vai com o id, a bolha local mostra a citação,
/// e o campo e a faixa esvaziam já com o envio em voo. A outra conversa fica
/// com o rascunho e a citação dela.
@MainActor
private func enviarComCitacao() async {
    let m = Montagem()
    let s = m.store
    s.citar(m7, em: kX)
    s.definirRascunho("Mando hoje à tarde", para: kX)
    s.citar(m7, em: kY)
    s.definirRascunho("rascunho do Carlos", para: kY)

    m.t.segurar = true
    let envio = Task { @MainActor in
        await s.enviarTexto(s.rascunho(kX), para: kX, citando: s.citacao(kX))
    }
    await esperar("POST /v1/enviar/texto sair") { !m.t.de("/v1/enviar/texto").isEmpty }
    let p = m.t.de("/v1/enviar/texto")[0]
    exigir(p.corpo["citar"] as? String == "m7", "enviar com citação manda citar = id da citada; veio \(String(describing: p.corpo["citar"]))")
    exigir(p.corpo["texto"] as? String == "Mando hoje à tarde", "o texto enviado é o do campo; veio \(String(describing: p.corpo["texto"]))")
    exigir(p.corpo["para"] as? String == X, "enviado para a conversa errada: \(String(describing: p.corpo["para"]))")

    // ainda "enviando": o campo e a faixa já esvaziaram
    exigir(s.rascunho(kX) == "", "o campo não esvaziou ao enviar (ainda em voo): \"\(s.rascunho(kX))\"")
    exigir(s.citacao(kX) == nil, "a faixa de citação não sumiu ao enviar (ainda em voo): \(String(describing: s.citacao(kX)))")
    let local = s.estado.bolhas(de: kX).last?.mensagem
    exigir(local?.citacao?.id == "m7", "a bolha local (enviando) deveria levar a citação de m7; veio \(String(describing: local?.citacao))")
    exigir(local?.citacao?.remetente == X, "a citação da bolha local perdeu o remetente: \(String(describing: local?.citacao))")

    m.t.segurar = false
    await envio.value
    exigir(s.rascunho(kX) == "", "depois da resposta o rascunho voltou: \"\(s.rascunho(kX))\"")
    exigir(s.citacao(kX) == nil, "depois da resposta a citação voltou: \(String(describing: s.citacao(kX)))")
    exigir(s.rascunho(kY) == "rascunho do Carlos", "enviar em uma conversa apagou o rascunho de outra: \"\(s.rascunho(kY))\"")
    exigir(s.citacao(kY)?.id == "m7", "enviar em uma conversa apagou a citação de outra")

    // envio que falha: a bolha "não enviada" mostra a citação
    s.citar(m7, em: kX)
    m.t.falhar = true
    await s.enviarTexto("de novo", para: kX, citando: s.citacao(kX))
    let falhou = s.estado.bolhas(de: kX).last
    var falhouMesmo = false
    if case .falhou? = falhou?.envio { falhouMesmo = true }
    exigir(falhouMesmo, "montagem: o envio deveria ter falhado")
    exigir(falhou?.mensagem.citacao?.id == "m7", "a bolha que falhou perdeu a citação: \(String(describing: falhou?.mensagem.citacao))")
}

// MARK: - store: anexo

/// Anexo pendente é da conversa, sobrevive a fechar o notch e sai com o texto
/// do campo como legenda; depois do envio, o campo fica limpo.
@MainActor
private func anexoPendente() async {
    let m = Montagem()
    let s = m.store
    let pdf = arquivoDeTeste("orcamento-dezembro.pdf")
    exigir(s.anexoPendente(kX) == nil, "conversa nova não nasce com anexo")

    s.definirAnexo(pdf, para: kX)
    exigir(s.anexoPendente(kX)?.standardizedFileURL.path == pdf.standardizedFileURL.path,
           "definirAnexo: anexoPendente(k) deveria ser o arquivo escolhido, veio \(String(describing: s.anexoPendente(kX)))")
    exigir(s.anexoPendente(kY) == nil, "o anexo de uma conversa apareceu em outra")

    // fechar o notch e a conversa não perde o anexo
    let vm = NotchViewModel()
    vm.setExpandedDirect(true)
    vm.whatsappConversaAberta = kX.texto
    vm.setExpandedDirect(false)
    await s.abrir(kX)
    s.fechar(kX)
    exigir(s.anexoPendente(kX)?.standardizedFileURL.path == pdf.standardizedFileURL.path,
           "o anexo pendente sumiu ao fechar o notch/a conversa")

    // tirar o anexo (x no chip) antes de enviar
    s.definirAnexo(pdf, para: kY)
    s.definirAnexo(nil, para: kY)
    exigir(s.anexoPendente(kY) == nil, "definirAnexo(nil) não tirou o anexo")
    exigir(s.anexoPendente(kX) != nil, "tirar o anexo de uma conversa tirou o de outra")

    s.definirRascunho("segue o orçamento", para: kX)
    guard let url = s.anexoPendente(kX) else { exigir(false, "sem anexo pendente para enviar"); return }
    await s.enviarAnexo(url, para: kX, legenda: s.rascunho(kX))
    let pedidos = m.t.de("/v1/enviar/midia")
    exigir(pedidos.count == 1, "enviar o anexo: 1 POST /v1/enviar/midia, foram \(pedidos.count) (erro: \(String(describing: s.erroDeAnexo)))")
    if let p = pedidos.first {
        exigir(p.corpo["legenda"] as? String == "segue o orçamento",
               "o texto do campo vai como legenda; veio \(String(describing: p.corpo["legenda"]))")
        exigir(p.corpo["nome"] as? String == "orcamento-dezembro.pdf", "nome do documento: \(String(describing: p.corpo["nome"]))")
        exigir(p.corpo["tipo"] as? String == "documento", "PDF vai como documento: \(String(describing: p.corpo["tipo"]))")
        exigir(p.corpo["para"] as? String == X, "anexo enviado para a conversa errada: \(String(describing: p.corpo["para"]))")
    }
    exigir(s.anexoPendente(kX) == nil, "depois de enviado, o anexo continuou pendente no campo")
    exigir(s.rascunho(kX) == "", "depois de enviar o anexo com legenda, o campo não esvaziou: \"\(s.rascunho(kX))\"")
}

// MARK: - store: reação, rascunho, harness

/// Tocar na reação que já é minha manda emoji vazio à ponte (remove).
@MainActor
private func reagirRemove() async {
    let m = Montagem()
    await m.store.reagir(WACompositor.emojiParaEnviar(escolhido: "👍", atual: "👍"), a: "m7", em: kX)
    let ps = m.t.de("/v1/reagir")
    exigir(ps.count == 1, "1 POST /v1/reagir, foram \(ps.count)")
    if let p = ps.first {
        exigir(p.corpo["emoji"] as? String == "", "remover a reação manda emoji vazio; veio \(String(describing: p.corpo["emoji"]))")
        exigir(p.corpo["alvo"] as? String == "m7", "alvo da reação: \(String(describing: p.corpo["alvo"]))")
    }
}

/// O rascunho do Carlos volta ao abrir a conversa de novo, mesmo trocando de
/// conversa na tela e fechando o notch.
@MainActor
private func rascunhoDevolvido() async {
    let m = Montagem()
    let s = m.store
    let texto = "Carlos, ajustei o orçamento de dezembro e…"
    let vm = NotchViewModel()
    vm.setExpandedDirect(true)
    vm.whatsappConversaAberta = kY.texto
    await s.abrir(kY)
    s.definirRascunho(texto, para: kY)
    s.fechar(kY)
    vm.whatsappConversaAberta = kX.texto
    vm.setExpandedDirect(false)
    vm.setExpandedDirect(true)
    vm.whatsappConversaAberta = kY.texto
    await s.abrir(kY)
    exigir(s.rascunho(kY) == texto, "o rascunho do Carlos não voltou ao reabrir: \"\(s.rascunho(kY))\"")
    exigir(s.rascunho(kX) == "", "o rascunho do Carlos vazou para outra conversa")
}

/// O snapshot reaproveita o store entre cenários: `_zerar()` esquece citação
/// e anexo; `_injetarGravacao` põe a gravação em curso sem microfone.
@MainActor
private func harness() {
    let m = Montagem()
    let s = m.store
    s.citar(m7, em: kX)
    s.definirAnexo(arquivoDeTeste("foto.pdf"), para: kX)
    s._zerar()
    exigir(s.citacao(kX) == nil, "_zerar() deixou a citação: vazaria para o próximo cenário do snapshot")
    exigir(s.anexoPendente(kX) == nil, "_zerar() deixou o anexo: vazaria para o próximo cenário do snapshot")

    let g = WAGravacaoEmCurso(chave: kG, inicio: Date(timeIntervalSince1970: 1_762_270_000), nivel: 0.5)
    s._injetarGravacao(g)
    exigir(s.gravacao == g, "_injetarGravacao: store.gravacao deveria ser a injetada, veio \(String(describing: s.gravacao))")
}

// MARK: - barra de reações por tela

@MainActor
private func barraDeReacoes() {
    let a = NotchViewModel(), b = NotchViewModel()
    for vm in [a, b] {
        vm.setExpandedDirect(true)
        vm.whatsappConversaAberta = kX.texto
        vm.whatsappReacoesEm = "m7"
    }
    exigir(a.whatsappReacoesEm == "m7", "montagem: a barra de reações não abriu em m7")

    // mesma conversa reatribuída (a seção adota a padrão) não fecha a barra
    a.whatsappConversaAberta = kX.texto
    exigir(a.whatsappReacoesEm == "m7", "reatribuir a MESMA conversa fechou a barra de reações")

    a.whatsappConversaAberta = kY.texto
    exigir(a.whatsappReacoesEm == nil, "trocar de conversa não fechou a barra de reações: \(String(describing: a.whatsappReacoesEm))")
    exigir(b.whatsappReacoesEm == "m7", "trocar de conversa numa tela fechou a barra da outra tela")

    a.whatsappReacoesEm = "m9"
    a.abrirWhatsApp(chave: kX.texto, conta: A)
    exigir(a.whatsappReacoesEm == nil, "abrir outra conversa pelo card não fechou a barra de reações")

    a.whatsappReacoesEm = "m9"
    a.fecharReacoesWhatsApp()
    exigir(a.whatsappReacoesEm == nil, "Esc (fecharReacoesWhatsApp) não fechou a barra")
    exigir(b.whatsappReacoesEm == "m7", "Esc numa tela fechou a barra da outra")

    a.whatsappReacoesEm = "m9"
    a.setExpandedDirect(false)
    exigir(a.whatsappReacoesEm == nil, "fechar o notch não fechou a barra de reações")
    exigir(b.whatsappReacoesEm == "m7", "fechar o notch numa tela fechou a barra da outra")
    exigir(b.whatsappConversaAberta == kX.texto, "a outra tela mudou de conversa")
}

// MARK: - ligação (views e harness de snapshot, que o check.sh não compila)

/// Linhas de código do arquivo, sem as de comentário (`//`); `nil` se falta.
private func codigo(_ caminho: String) -> [String]? {
    guard let t = try? String(contentsOfFile: caminho, encoding: .utf8) else { return nil }
    return t.components(separatedBy: "\n").filter {
        !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
    }
}

private func ligacao() {
    let compositor = "Knobler/WhatsApp/WhatsAppCompositor.swift"
    let compositorView = "Knobler/WhatsApp/WhatsAppCompositorView.swift"
    let conversaView = "Knobler/WhatsApp/WhatsAppConversaView.swift"
    let bolhaView = "Knobler/WhatsApp/WhatsAppBolhaView.swift"
    let fontes = "tools/notchview-fontes.txt"
    let harness = "tools/main.swift"

    exigir(FileManager.default.fileExists(atPath: "tools/check.sh"),
           "rode da raiz do repo (o check.sh faz isso); cwd = \(FileManager.default.currentDirectoryPath)")
    for f in [compositor, compositorView, conversaView, bolhaView, harness, fontes] {
        exigir(codigo(f) != nil, "\(f) não existe")
    }
    let cmp = codigo(compositorView)!, conv = codigo(conversaView)!, bol = codigo(bolhaView)!
    let views = cmp + conv + bol
    func tem(_ ls: [String], _ s: String) -> Bool { ls.contains { $0.contains(s) } }

    // a conversa tem o compositor fixo embaixo
    exigir(tem(conv, "WhatsAppCompositorView("), "\(conversaView) não mostra o WhatsAppCompositorView(")

    // compositor: modo, campo ligado ao rascunho do estado, envio, anexo, gravação
    exigir(tem(cmp, "WACompositor.modo("), "\(compositorView) não decide o desenho por WACompositor.modo(")
    exigir(tem(cmp, ".rascunho(") && tem(cmp, "definirRascunho("),
           "\(compositorView): o campo tem que ler/escrever store.rascunho/definirRascunho (nunca @State)")
    exigir(tem(cmp, "enviarTexto("), "\(compositorView): Enter/avião não chama store.enviarTexto(")
    exigir(tem(cmp, ".citacao("), "\(compositorView): o envio não leva store.citacao(k)")
    exigir(tem(cmp, "\"paperclip\""), "\(compositorView) sem o clipe (paperclip)")
    exigir(tem(cmp, "NSOpenPanel"), "\(compositorView): o clipe não abre o NSOpenPanel")
    exigir(tem(cmp, "definirAnexo(") && tem(cmp, "anexoPendente("), "\(compositorView) não guarda o anexo pendente no store")
    exigir(tem(cmp, "enviarAnexo("), "\(compositorView): o anexo pendente não é enviado (store.enviarAnexo)")
    exigir(tem(cmp, "\"paperplane.fill\""), "\(compositorView) sem o avião (paperplane.fill)")
    exigir(tem(cmp, "\"mic"), "\(compositorView) sem o microfone (mic)")
    exigir(tem(cmp, ".gravar(em:"), "\(compositorView): o microfone não começa a gravação (store.gravar(em:))")
    exigir(tem(cmp, "pararEEnviarGravacao("), "\(compositorView): o avião da gravação não chama pararEEnviarGravacao")
    exigir(tem(cmp, "cancelarGravacao("), "\(compositorView): a lixeira da gravação não chama cancelarGravacao")
    exigir(tem(cmp, "WACompositor.tempoDeGravacao("), "\(compositorView): o tempo da gravação não vem de WACompositor.tempoDeGravacao(")
    exigir(tem(cmp, "WATextos.gravando") || tem(cmp, "\"Gravando\""), "\(compositorView) sem \"Gravando\"")
    exigir(tem(cmp, "WATextos.ouvindo") || tem(cmp, "\"Ouvindo\""), "\(compositorView) sem \"Ouvindo\" do ditado")
    exigir(tem(cmp, "WATextos.placeholderConversa") || tem(cmp, "\"Mensagem\""), "\(compositorView) sem o placeholder \"Mensagem\"")

    // faixa de citação
    exigir(tem(cmp, "WACompositor.rotuloDaCitacao("), "\(compositorView): faixa sem WACompositor.rotuloDaCitacao(")
    exigir(tem(cmp, "WACompositor.textoDaCitacao("), "\(compositorView): faixa sem WACompositor.textoDaCitacao(")
    exigir(tem(cmp, "cancelarCitacao("), "\(compositorView): o x/Esc da faixa não chama cancelarCitacao")

    // foco e teclado: o campo em uso recebe o ditado; Esc fecha barra e citação
    exigir(tem(cmp, "@FocusState"), "\(compositorView) sem @FocusState no campo")
    exigir(tem(cmp, "atualizarEdicaoWhatsApp("), "\(compositorView): o foco não chega ao VM (atualizarEdicaoWhatsApp)")
    exigir(tem(cmp, "campoEmUso"), "\(compositorView): o foco não marca store.campoEmUso (o ditado escreve no campo em uso)")
    exigir(tem(cmp, ".onDisappear"), "\(compositorView) sem .onDisappear zerando foco e campo em uso")
    exigir(tem(cmp, ".onKeyPress(.escape"), "\(compositorView): Esc no campo não é tratado (.onKeyPress(.escape)")
    exigir(tem(views, "fecharReacoesWhatsApp("), "Esc não chama vm.fecharReacoesWhatsApp()")

    // ações da bolha: reagir e citar
    exigir(tem(bol, "\"face.smiling\""), "\(bolhaView) sem o botão de reagir (face.smiling)")
    exigir(tem(bol, "\"arrowshape.turn.up.left\""), "\(bolhaView) sem o botão de citar (arrowshape.turn.up.left)")
    exigir(tem(bol, "whatsappReacoesEm"), "\(bolhaView): a barra de reações não é o estado por tela vm.whatsappReacoesEm")
    exigir(tem(bol, "WACompositor.reacoes"), "\(bolhaView): a barra não lista WACompositor.reacoes")
    exigir(tem(bol, "WACompositor.emojiParaEnviar("), "\(bolhaView): tocar na reação não passa por WACompositor.emojiParaEnviar(")
    exigir(tem(bol, ".reagir("), "\(bolhaView): a reação não chama store.reagir(")
    exigir(tem(bol, ".citar("), "\(bolhaView): citar não chama store.citar(")
    exigir(tem(bol, ".onKeyPress(.escape"), "\(bolhaView): Esc na barra de reações não é tratado")

    // snapshot: fontes e cenários
    let ft = codigo(fontes)!.map { $0.trimmingCharacters(in: .whitespaces) }
    for f in [compositor, compositorView] {
        exigir(ft.contains(f), "\(fontes) sem \(f)")
    }
    let mn = codigo(harness)!
    for c in ["whatsapp-citando-reacoes", "whatsapp-gravando", "whatsapp-ditando", "whatsapp-rascunho"] {
        exigir(tem(mn, "\"\(c)\""), "\(harness) sem o cenário \"\(c)\"")
    }
    exigir(tem(mn, "whatsappReacoesEm = \"m7\""), "\(harness): whatsapp-citando-reacoes sem vm.whatsappReacoesEm = \"m7\"")
    exigir(tem(mn, "_injetarGravacao("), "\(harness): whatsapp-gravando sem _injetarGravacao(")
    exigir(tem(mn, ".recording(level: 0.6)"), "\(harness): whatsapp-ditando sem vm.dictation = .recording(level: 0.6)")
    exigir(tem(mn, "Pode subir o corte de 15 s ainda hoje"), "\(harness): whatsapp-ditando sem o rascunho do mockup")
    exigir(tem(mn, "Carlos, ajustei o orçamento de dezembro e…"), "\(harness): whatsapp-rascunho sem o rascunho do Carlos")
}

// MARK: - main

@main
enum Gate {
    @MainActor
    static func main() async {
        defer { try? FileManager.default.removeItem(at: pastaBase) }
        // hermético: nada do histórico real entra nem sai
        NotificationHistory.shared.arquivo = nil
        modo()
        textoDaCitacao()
        rotuloDaCitacao()
        reacoes()
        tempoDeGravacao()
        barraDeReacoes()
        await citacaoPorConversa()
        await enviarComCitacao()
        await anexoPendente()
        await reagirRemove()
        await rascunhoDevolvido()
        harness()
        ligacao()
        print("whatsappcompositorcheck ok")
    }
}
