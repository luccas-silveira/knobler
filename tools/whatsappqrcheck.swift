// Gate da etapa 23 do WhatsApp: o QR do pareamento (Knobler/WhatsApp/WhatsAppQR.swift)
// e o que os estados de conexão pedem ao estado (Knobler/WhatsApp/WhatsAppStore.swift):
// `iniciarPareamento()`, `gerarOutroQR()` e `tentarDeNovo()`.
// Contrato: docs/whatsapp-ponte.md (objeto Pareamento em :395-422, rotas
// `POST`/`GET /v1/pareamento` em :695-717, evento `pareamento` em :947-950).
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift \
//     Knobler/WhatsApp/WhatsAppCliente.swift Knobler/WhatsApp/WhatsAppCanal.swift \
//     Knobler/WhatsApp/WhatsAppEstado.swift Knobler/WhatsApp/WhatsAppStore.swift \
//     Knobler/WhatsApp/WhatsAppGravacao.swift Knobler/WhatsApp/CodificadorOpus.swift \
//     Knobler/WhatsApp/OggOpus.swift Knobler/WhatsApp/WhatsAppMidia.swift \
//     Knobler/WhatsApp/WhatsAppQR.swift tools/whatsappqrcheck.swift \
//     -o /tmp/whatsappqrcheck && /tmp/whatsappqrcheck
//
// Nada sai pela rede: o cliente fala com um transporte falso que responde por
// caminho e grava cada pedido (com o cabeçalho Authorization), e o canal é um
// falso que conta `acordou()`. Cada montagem tem a própria chave numa pasta de
// NSTemporaryDirectory(); a chave de verdade da ponte nunca é lida.

import CoreImage
import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappqrcheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - números do teste

private let A = "554791744143"    // conta conectada (padrão)
private let B = "554792508292"    // conta deslogada: a que pareia
private let NOVA = "554700000003"

// MARK: - JSON do contrato

private func js(_ s: String?) -> String {
    guard let s else { return "null" }
    let d = try! JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
    let t = String(decoding: d, as: UTF8.self)
    return String(t.dropFirst().dropLast())
}

private func contaJSON(_ numero: String, padrao: Bool, estado: String) -> String {
    #"{"conta": \#(js(numero)), "jid": \#(js(numero + ":17@s.whatsapp.net")), "nome": null, "padrao": \#(padrao), "estado": \#(js(estado)), "motivo": null, "desde": 1762270000, "nao_lidas": 0, "conversas_nao_lidas": 0}"#
}

private func pareamentoJSON(_ id: String, estado: String, qr: String?) -> String {
    let expira = qr == nil ? "null" : "1762270620"
    return #"{"id": \#(js(id)), "estado": \#(js(estado)), "qr": \#(js(qr)), "qr_expira_em": \#(expira), "fim": 1762270720, "conta": null, "motivo": null}"#
}

private func pareamento(_ id: String, _ estado: WAEstadoPareamento, qr: String?, conta: String? = nil) -> WAPareamento {
    WAPareamento(id: id, estado: estado, qr: qr, qrExpiraEm: qr == nil ? nil : 1_762_270_620,
                 fim: 1_762_270_720, conta: conta, motivo: nil)
}

// MARK: - transporte falso

private struct Pedido {
    let metodo: String
    let caminho: String
    let autorizacao: String?
}

/// Como o `POST /v1/pareamento` responde.
private enum ModoDoPareamento {
    /// `200` com um pareamento novo `p-N` em `qr`, QR `2@qr-N`.
    case novo
    /// `409 pareamento_em_andamento`, com o atual (`p-andamento`) no corpo.
    case emAndamento
}

private final class TransporteFalso: WATransporte {
    private let trava = NSLock()
    private var _pedidos: [Pedido] = []
    private var _contas: [String] = [contaJSON(A, padrao: true, estado: "conectada"),
                                     contaJSON(B, padrao: false, estado: "deslogada")]
    private var _modo: ModoDoPareamento = .novo
    private var criados = 0

    var pedidos: [Pedido] { trava.lock(); defer { trava.unlock() }; return _pedidos }
    func limpar() { trava.lock(); _pedidos = []; trava.unlock() }
    func definirContas(_ c: [String]) { trava.lock(); _contas = c; trava.unlock() }
    func definirModo(_ m: ModoDoPareamento) { trava.lock(); _modo = m; trava.unlock() }

    func de(_ metodo: String, _ caminho: String) -> [Pedido] {
        pedidos.filter { $0.metodo == metodo && $0.caminho == caminho }
    }

    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let comps = URLComponents(url: pedido.url!, resolvingAgainstBaseURL: false)!
        let p = Pedido(metodo: pedido.httpMethod ?? "GET", caminho: comps.path,
                       autorizacao: pedido.value(forHTTPHeaderField: "Authorization"))
        let (status, texto) = responder(p)
        let r = HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "application/json"])!
        return (Data(texto.utf8), r)
    }

    private func responder(_ p: Pedido) -> (Int, String) {
        trava.lock(); defer { trava.unlock() }
        _pedidos.append(p)
        switch (p.metodo, p.caminho) {
        case ("GET", "/v1/contas"):
            return (200, #"{"ok": true, "contas": [\#(_contas.joined(separator: ", "))]}"#)
        case ("GET", "/v1/conversas"):
            return (200, #"{"ok": true, "conversas": [], "antes": null}"#)
        case ("GET", "/v1/pareamento"):
            return (404, #"{"ok": false, "erro": "sem_pareamento", "detalhe": "nada em andamento"}"#)
        case ("POST", "/v1/pareamento"):
            switch _modo {
            case .novo:
                criados += 1
                let id = "p-\(criados)"
                return (200, #"{"ok": true, "pareamento": \#(pareamentoJSON(id, estado: "qr", qr: "2@qr-\(criados)"))}"#)
            case .emAndamento:
                return (409, #"{"ok": false, "erro": "pareamento_em_andamento", "detalhe": "outro pareamento aberto", "pareamento": \#(pareamentoJSON("p-andamento", estado: "qr", qr: "2@em-andamento"))}"#)
            }
        default:
            return (404, #"{"ok": false, "erro": "rota_inexistente", "detalhe": "x"}"#)
        }
    }
}

// MARK: - canal falso

private final class CanalFalso: WACanalProtocolo {
    var aoEvento: ((WAEvento) -> Void)?
    var aoRessincronizar: ((String, Int) -> Void)?
    var aoMudarEstado: ((WAEstadoDoCanal) -> Void)?
    private(set) var iniciados = 0
    private(set) var parados = 0
    private(set) var acordados = 0

    func iniciar() { iniciados += 1 }
    func parar() { parados += 1; aoMudarEstado?(.parado) }
    func acordou() { acordados += 1 }

    func mudar(_ e: WAEstadoDoCanal) { aoMudarEstado?(e) }
    func entregar(_ e: WAEvento) { aoEvento?(e) }
}

// MARK: - montagem

private let pastaBase = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("whatsappqrcheck-\(getpid())", isDirectory: true)
private var montagens = 0

@MainActor
private final class Montagem {
    let t = TransporteFalso()
    let arquivoDaChave: URL
    let cliente: WACliente
    var canais: [CanalFalso] = []
    var store: WhatsAppStore!

    /// `chave == nil`: o arquivo da chave não existe ao montar.
    init(chave: String? = "chave-velha") {
        montagens += 1
        let pasta = pastaBase.appendingPathComponent("m\(montagens)", isDirectory: true)
        try! FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        arquivoDaChave = pasta.appendingPathComponent("api-key")
        if let chave { try! Data((chave + "\n").utf8).write(to: arquivoDaChave) }
        cliente = WACliente(porta: 18099, caminhoDaChave: arquivoDaChave, transporte: t)
        store = WhatsAppStore(cliente: cliente, fabricaDeCanal: { [unowned self] _ in
            let c = CanalFalso()
            self.canais.append(c)
            return c
        })
    }

    func escreverChave(_ chave: String) {
        try! Data((chave + "\n").utf8).write(to: arquivoDaChave)
    }

    func canal(linha: UInt = #line) -> CanalFalso {
        exigir(!canais.isEmpty, "nenhum canal foi criado", linha: linha)
        return canais.last!
    }
}

/// Espera a condição virar verdadeira (até 3 s), cedendo o main actor.
@MainActor
private func esperar(_ desc: String, linha: UInt = #line, _ cond: () -> Bool) async {
    for _ in 0..<3000 {
        if cond() { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    exigir(cond(), "esperou 3 s e não aconteceu: \(desc)", linha: linha)
}

/// Deixa as tarefas pendentes rodarem: base das provas de "não aconteceu".
@MainActor
private func assentar() async {
    for _ in 0..<60 { try? await Task.sleep(nanoseconds: 1_000_000) }
}

/// Store com canal aberto, a primeira carga terminada (A conectada, B
/// deslogada, nenhum pareamento) e os pedidos zerados.
@MainActor
private func montarPronta(linha: UInt = #line) async -> Montagem {
    let m = Montagem()
    await m.store.iniciar()
    m.canal(linha: linha).mudar(.aberto)
    await esperar("primeira carga terminar em .pronta", linha: linha) { m.store.conexao == .pronta }
    await assentar()
    exigir(m.store.estado.pareamento == nil, "a carga não deveria trazer pareamento (GET responde 404)", linha: linha)
    m.t.limpar()
    return m
}

// MARK: - QR

/// Pixels RGBA (sRGB, 8 bits) da imagem desenhada 1:1 sobre vermelho: pixel
/// transparente ou semitransparente aparece como não-preto-e-branco.
private func pixels(_ imagem: CGImage) -> [UInt8] {
    let w = imagem.width, h = imagem.height
    var b = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.interpolationQuality = .none
    ctx.draw(imagem, in: CGRect(x: 0, y: 0, width: w, height: h))
    return b
}

/// O texto que um leitor de QR tira da imagem (o celular faz o mesmo).
private func lerQR(_ imagem: CGImage) -> [String] {
    guard let d = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                             options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return [] }
    return d.features(in: CIImage(cgImage: imagem)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
}

/// Imagem quadrada `lado × lado`, só preto e branco opacos, com os dois
/// presentes, e que um leitor de QR lê de volta como `texto`.
private func conferirQR(_ texto: String, lado: Int, linha: UInt = #line) {
    guard let img = WAQR.imagem(texto, lado: lado) else {
        exigir(false, "WAQR.imagem(\"\(texto.prefix(24))…\", lado: \(lado)) devolveu nil", linha: linha)
        return
    }
    exigir(img.width == lado && img.height == lado,
           "QR de lado \(lado) saiu \(img.width) × \(img.height)", linha: linha)
    let b = pixels(img)
    var pretos = 0, brancos = 0, outros = 0
    var exemplo = ""
    for i in stride(from: 0, to: b.count, by: 4) {
        let (r, g, bl, a) = (b[i], b[i + 1], b[i + 2], b[i + 3])
        if a == 255 && r == 0 && g == 0 && bl == 0 { pretos += 1 }
        else if a == 255 && r == 255 && g == 255 && bl == 255 { brancos += 1 }
        else {
            outros += 1
            if exemplo.isEmpty { exemplo = "rgba(\(r), \(g), \(bl), \(a))" }
        }
    }
    exigir(outros == 0, "QR de lado \(lado) tem \(outros) pixel(s) que não são preto nem branco opacos (ex.: \(exemplo)) — suavização na escala ou fundo transparente", linha: linha)
    exigir(pretos > 0 && brancos > 0, "QR de lado \(lado) sem os dois tons (pretos \(pretos), brancos \(brancos))", linha: linha)
    let lido = lerQR(img)
    exigir(lido == [texto], "o leitor de QR tirou \(lido) da imagem, esperado [\(texto.prefix(40))…]", linha: linha)
}

/// Escala inteira: todo módulo tem o mesmo número de pixels. Nas linhas, cada
/// trecho de uma cor só que não toca a borda tem comprimento múltiplo do
/// módulo; com escala fracionária saem trechos de 5 e de 6 e o mdc cai a 1.
private func moduloDaEscala(_ imagem: CGImage) -> Int {
    func mdc(_ a: Int, _ b: Int) -> Int { b == 0 ? a : mdc(b, a % b) }
    let b = pixels(imagem)
    let w = imagem.width
    var g = 0
    for y in 0..<imagem.height {
        var trechos: [Int] = []
        var atual = b[(y * w) * 4], n = 0
        for x in 0..<w {
            let v = b[(y * w + x) * 4]
            if v == atual { n += 1 } else { trechos.append(n); atual = v; n = 1 }
        }
        // o primeiro e o último tocam a borda (margem branca de largura livre)
        for t in trechos.dropFirst() { g = mdc(g, t) }
    }
    return g
}

private func escalaInteira() {
    guard let img = WAQR.imagem("2@AbCd,xyz", lado: 128) else {
        exigir(false, "WAQR.imagem(\"2@AbCd,xyz\", lado: 128) devolveu nil")
        return
    }
    let k = moduloDaEscala(img)
    exigir(k >= 2, "QR de 128 com módulos de tamanhos diferentes (mdc dos trechos = \(k)): a escala tem que ser inteira")
}

private func qr() {
    // o exemplo do plano
    conferirQR("2@AbCd,xyz", lado: 128)
    // texto com o tamanho de um QR de verdade do WhatsApp (ref, chave pública, chave de identidade, adv)
    let real = "2@" + String(repeating: "Xy9+/AbC", count: 22) + ",dGVzdGUtY2hhdmUtcHVibGljYS1kby1rbm9ibGVy=,"
        + "aWRlbnRpZGFkZS1kby1rbm9ibGVyLXNuYXBzaG90=,YWR2LXNlY3JldG8tZG8ta25vYmxlcg=="
    conferirQR(real, lado: 128)
    // o lado vale: não é 128 fixo
    conferirQR("2@AbCd,xyz", lado: 200)

    exigir(WAQR.imagem("", lado: 128) == nil, "texto vazio deveria dar nil (não há o que desenhar)")

    guard let um = WAQR.imagem("2@AbCd,xyz", lado: 128),
          let dois = WAQR.imagem("2@AbCd,xyz", lado: 128) else {
        exigir(false, "WAQR.imagem devolveu nil para o mesmo texto na segunda vez")
        return
    }
    exigir(pixels(um) == pixels(dois), "o mesmo texto deu duas imagens diferentes")
    if let outra = WAQR.imagem("2@outro-texto,abc", lado: 128) {
        exigir(pixels(outra) != pixels(um), "textos diferentes deram a mesma imagem")
    } else {
        exigir(false, "WAQR.imagem(\"2@outro-texto,abc\") devolveu nil")
    }
}

// MARK: - pareamento

/// `iniciarPareamento()` faz um `POST /v1/pareamento` e guarda o que veio; o
/// segundo, com o pareamento em `qr`, não pede de novo.
@MainActor
private func iniciarGuardaENaoRepete() async {
    let m = await montarPronta()
    await m.store.iniciarPareamento()
    await esperar("iniciarPareamento() guardar o pareamento") { m.store.estado.pareamento != nil }
    exigir(m.t.de("POST", "/v1/pareamento").count == 1,
           "iniciarPareamento() deveria fazer 1 POST /v1/pareamento, fez \(m.t.de("POST", "/v1/pareamento").count)")
    let esperado = pareamento("p-1", .qr, qr: "2@qr-1")
    exigir(m.store.estado.pareamento == esperado,
           "pareamento guardado \(String(describing: m.store.estado.pareamento)), esperado \(esperado)")

    await m.store.iniciarPareamento()
    await assentar()
    exigir(m.t.de("POST", "/v1/pareamento").count == 1,
           "com o pareamento em qr, o segundo iniciarPareamento() pediu de novo (\(m.t.de("POST", "/v1/pareamento").count) POSTs)")
    exigir(m.store.estado.pareamento == esperado, "o segundo iniciarPareamento() trocou o pareamento guardado")
}

/// `409 pareamento_em_andamento`: adota o pareamento que veio no corpo.
@MainActor
private func adota409() async {
    let m = await montarPronta()
    m.t.definirModo(.emAndamento)
    await m.store.iniciarPareamento()
    await esperar("iniciarPareamento() adotar o pareamento do 409") { m.store.estado.pareamento != nil }
    exigir(m.t.de("POST", "/v1/pareamento").count == 1,
           "iniciarPareamento() deveria fazer 1 POST, fez \(m.t.de("POST", "/v1/pareamento").count)")
    let esperado = pareamento("p-andamento", .qr, qr: "2@em-andamento")
    exigir(m.store.estado.pareamento == esperado,
           "com 409 o pareamento guardado é \(String(describing: m.store.estado.pareamento)), esperado o do corpo \(esperado)")
    exigir(m.store.conexao == .pronta, "o 409 do pareamento mexeu na conexão: \(m.store.conexao)")
}

/// Evento `pareamento` com QR novo troca o QR mostrado; e não faz pedido.
@MainActor
private func eventoTrocaQR() async {
    let m = await montarPronta()
    await m.store.iniciarPareamento()
    await esperar("iniciarPareamento() guardar o pareamento") { m.store.estado.pareamento?.qr == "2@qr-1" }
    m.t.limpar()

    let novo = WAPareamento(id: "p-1", estado: .qr, qr: "2@qr-trocado", qrExpiraEm: 1_762_270_640,
                            fim: 1_762_270_720, conta: nil, motivo: nil)
    m.canal().entregar(.pareamento(novo))
    await esperar("o evento pareamento trocar o QR") { m.store.estado.pareamento?.qr == "2@qr-trocado" }
    exigir(m.store.estado.pareamento == novo, "o evento pareamento não foi guardado inteiro")

    await m.store.iniciarPareamento()
    await assentar()
    exigir(m.t.de("POST", "/v1/pareamento").isEmpty,
           "com QR novo pelo evento, iniciarPareamento() pediu outro pareamento")
}

/// `expirado` → `gerarOutroQR()` faz `POST` de novo e guarda o pareamento novo.
@MainActor
private func expiradoGeraOutro() async {
    let m = await montarPronta()
    await m.store.iniciarPareamento()
    await esperar("iniciarPareamento() guardar o pareamento") { m.store.estado.pareamento?.id == "p-1" }

    m.canal().entregar(.pareamento(pareamento("p-1", .expirado, qr: nil)))
    await esperar("o evento expirado chegar ao estado") { m.store.estado.pareamento?.estado == .expirado }
    await assentar()
    exigir(m.t.de("POST", "/v1/pareamento").count == 1,
           "o evento expirado pediu outro pareamento sozinho; quem pede é o Gerar outro")
    m.t.limpar()

    await m.store.gerarOutroQR()
    await esperar("gerarOutroQR() guardar o pareamento novo") { m.store.estado.pareamento?.id == "p-2" }
    exigir(m.t.de("POST", "/v1/pareamento").count == 1,
           "gerarOutroQR() deveria fazer 1 POST /v1/pareamento, fez \(m.t.de("POST", "/v1/pareamento").count)")
    exigir(m.store.estado.pareamento == pareamento("p-2", .qr, qr: "2@qr-2"),
           "depois do Gerar outro o pareamento é \(String(describing: m.store.estado.pareamento))")
}

/// `sucesso` relê `/v1/contas`: a conta pareada volta conectada.
@MainActor
private func sucessoRele() async {
    let m = await montarPronta()
    await m.store.iniciarPareamento()
    await esperar("iniciarPareamento() guardar o pareamento") { m.store.estado.pareamento != nil }
    m.t.definirContas([contaJSON(A, padrao: true, estado: "conectada"),
                       contaJSON(B, padrao: false, estado: "conectada"),
                       contaJSON(NOVA, padrao: false, estado: "conectada")])
    m.t.limpar()

    m.canal().entregar(.pareamento(pareamento("p-1", .sucesso, qr: nil, conta: B)))
    await esperar("pareamento sucesso reler /v1/contas") { !m.t.de("GET", "/v1/contas").isEmpty }
    await esperar("a conta pareada voltar conectada") {
        m.store.estado.contas.first { $0.conta == B }?.estado == .conectada
    }
    exigir(m.store.estado.contas.contains { $0.conta == NOVA }, "a conta que entrou no sucesso não apareceu")
    exigir(m.t.de("POST", "/v1/pareamento").isEmpty, "o sucesso pediu outro pareamento")
}

// MARK: - tentar de novo

/// Chave que não confere: o usuário conserta o arquivo e aperta "Tentar de
/// novo" — o estado relê a chave e acorda o mesmo canal, que reconecta na hora.
@MainActor
private func tentarDeNovoChaveNaoConfere() async {
    let m = await montarPronta()
    let c = m.canal()
    c.mudar(.chaveNaoConfere)
    await esperar("o canal levar a conexão a .chaveNaoConfere") { m.store.conexao == .chaveNaoConfere }
    exigir(m.cliente.chave() == "chave-velha", "o cliente deveria ter a chave velha em memória")

    m.escreverChave("chave-nova")
    exigir(m.cliente.chave() == "chave-velha", "pré-condição: sem reler, o cliente segue com a velha")

    await m.store.tentarDeNovo()
    await assentar()
    exigir(c.acordados == 1, "tentarDeNovo() deveria chamar acordou() no canal 1 vez, chamou \(c.acordados)")
    exigir(m.canais.count == 1, "tentarDeNovo() criou outro canal (\(m.canais.count)); o mesmo canal reconecta")
    exigir(c.parados == 0, "tentarDeNovo() parou o canal; ele só acorda")
    exigir(m.cliente.chave() == "chave-nova",
           "depois do tentarDeNovo() o cliente segue com \(String(describing: m.cliente.chave())); a chave tinha que ser relida do arquivo")

    // o próximo pedido já sai com a chave nova
    m.t.limpar()
    await m.store.iniciarPareamento()
    await esperar("o pedido seguinte sair") { !m.t.de("POST", "/v1/pareamento").isEmpty }
    let auth = m.t.de("POST", "/v1/pareamento")[0].autorizacao
    exigir(auth == "Bearer chave-nova", "o pedido depois do tentarDeNovo() saiu com \(String(describing: auth))")
}

/// Arquivo da chave ausente: o usuário sobe a ponte, o arquivo aparece e o
/// "Tentar de novo" acorda o canal.
@MainActor
private func tentarDeNovoChaveAusente() async {
    let m = Montagem(chave: nil)
    await m.store.iniciar()
    let c = m.canal()
    c.mudar(.semChave)
    await esperar("o canal levar a conexão a .semChave") { m.store.conexao == .semChave }

    m.escreverChave("chave-que-chegou")
    await m.store.tentarDeNovo()
    await assentar()
    exigir(c.acordados == 1, "sem chave, tentarDeNovo() deveria chamar acordou() 1 vez, chamou \(c.acordados)")
    exigir(m.canais.count == 1, "sem chave, tentarDeNovo() criou outro canal")
    exigir(m.cliente.chave() == "chave-que-chegou", "sem chave, tentarDeNovo() não leu o arquivo que apareceu")
}

@main
enum Gate {
    @MainActor
    static func main() async {
        defer { try? FileManager.default.removeItem(at: pastaBase) }
        qr()
        escalaInteira()
        await iniciarGuardaENaoRepete()
        await adota409()
        await eventoTrocaQR()
        await expiradoGeraOutro()
        await sucessoRele()
        await tentarDeNovoChaveNaoConfere()
        await tentarDeNovoChaveAusente()
        try? FileManager.default.removeItem(at: pastaBase)
        print("whatsappqrcheck: ok")
    }
}
