// Gate da etapa 3 do WhatsApp: cliente HTTP da ponte (Knobler/WhatsApp/WhatsAppCliente.swift).
// Contrato: docs/whatsapp-ponte.md (chave em :28-66, rotas em :424-722, erros em :982-1020).
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift \
//     Knobler/WhatsApp/WhatsAppCliente.swift tools/whatsappclientecheck.swift \
//     -o /tmp/whatsappclientecheck && /tmp/whatsappclientecheck
//
// Nada sai pela rede: o cliente fala com um transporte falso que grava cada
// `URLRequest` e devolve respostas roteirizadas. A chave mora numa pasta de
// NSTemporaryDirectory(); a chave de verdade da ponte nunca é lida.
// O binário roda sem Info.plist, então não prova o ATS: quem prova a exceção
// é o tools/whatsappatscheck.sh.

import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappclientecheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - transporte falso

private enum Roteiro {
    case http(Int, [String: String], Data)
    case falha(URLError.Code)
}

/// Pedido que chegou sem resposta roteirizada (o cliente pediu mais do que devia).
private struct SemRoteiro: Error {}

private final class TransporteFalso: WATransporte {
    var fila: [Roteiro] = []
    private(set) var pedidos: [URLRequest] = []
    /// Chamado com o número (1, 2, …) do pedido, antes de responder.
    var aoPedir: ((Int) -> Void)?

    /// O pedido de índice `i` (0 = primeiro); reprova se ele não chegou.
    func pedido(_ i: Int, linha: UInt = #line) -> URLRequest {
        exigir(i < pedidos.count, "esperava pelo menos \(i + 1) pedido(s) no transporte, chegaram \(pedidos.count)",
               linha: linha)
        return pedidos[i]
    }

    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        pedidos.append(pedido)
        aoPedir?(pedidos.count)
        guard !fila.isEmpty else { throw SemRoteiro() }
        switch fila.removeFirst() {
        case .falha(let codigo):
            throw URLError(codigo)
        case let .http(status, cabecalhos, corpo):
            let r = HTTPURLResponse(url: pedido.url ?? URL(string: "http://127.0.0.1")!,
                                    statusCode: status, httpVersion: "HTTP/1.1",
                                    headerFields: cabecalhos)!
            return (corpo, r)
        }
    }
}

private func ok(_ corpo: String) -> Roteiro {
    .http(200, ["Content-Type": "application/json"], Data(corpo.utf8))
}

private func erro(_ status: Int, _ codigo: String, detalhe: String? = "x", extra: String = "") -> Roteiro {
    let d = detalhe.map { #", "detalhe": "\#($0)""# } ?? ""
    return .http(status, ["Content-Type": "application/json"],
                 Data(#"{"ok": false, "erro": "\#(codigo)"\#(d)\#(extra)}"#.utf8))
}

// MARK: - ambiente

private let porta = 18099
private let pastaBase = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("whatsappclientecheck-\(getpid())", isDirectory: true)
private var contador = 0

private func gravar(_ texto: String, em url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try! Data(texto.utf8).write(to: url)
}

/// Cliente novo com a chave `chave` num arquivo temporário próprio (ou sem arquivo).
private func novoCliente(chave: String? = "chave-a") -> (WACliente, TransporteFalso, URL) {
    contador += 1
    let arquivo = pastaBase.appendingPathComponent("c\(contador)", isDirectory: true)
        .appendingPathComponent("api-key")
    if let chave { gravar(chave + "\n", em: arquivo) }
    let t = TransporteFalso()
    return (WACliente(porta: porta, caminhoDaChave: arquivo, transporte: t), t, arquivo)
}

private func erroDe<T>(_ op: () async throws -> T) async -> Error? {
    do { _ = try await op(); return nil } catch { return error }
}

/// Exige que `op` lance exatamente `esperado`.
private func exigirLanca<T>(_ esperado: WAErroDoCliente, _ contexto: String, linha: UInt = #line,
                            _ op: () async throws -> T) async {
    let e = await erroDe(op)
    exigir(e != nil, "\(contexto): não lançou (esperado \(esperado))", linha: linha)
    exigir((e as? WAErroDoCliente) == esperado,
           "\(contexto): lançou \(String(describing: e!)), esperado \(esperado)", linha: linha)
}

/// Executa e exige sucesso.
private func exigirOk<T>(_ contexto: String, linha: UInt = #line, _ op: () async throws -> T) async -> T {
    do { return try await op() } catch {
        exigir(false, "\(contexto): lançou \(error)", linha: linha)
        fatalError()
    }
}

private func cabecalho(_ p: URLRequest, _ nome: String) -> String? { p.value(forHTTPHeaderField: nome) }

private func query(_ p: URLRequest, _ contexto: String) -> [String: String] {
    let c = URLComponents(url: p.url!, resolvingAgainstBaseURL: false)!
    var q: [String: String] = [:]
    for item in c.queryItems ?? [] {
        exigir(q[item.name] == nil, "\(contexto): parâmetro \(item.name) repetido na query")
        q[item.name] = item.value ?? ""
    }
    return q
}

/// Confere o que vale para todo pedido e o que é desta rota.
private func conferir(_ p: URLRequest, _ metodo: String, _ caminho: String,
                      query esperada: [String: String]? = nil, prazo: Double? = nil,
                      chave: String = "chave-a", _ contexto: String, linha: UInt = #line) {
    let url = p.url!
    exigir(url.scheme == "http" && url.host == "127.0.0.1" && url.port == porta,
           "\(contexto): pedido não foi para http://127.0.0.1:\(porta): \(url.absoluteString)", linha: linha)
    exigir((p.httpMethod ?? "GET") == metodo,
           "\(contexto): método \(p.httpMethod ?? "nil"), esperado \(metodo)", linha: linha)
    exigir(url.path == caminho, "\(contexto): caminho \(url.path), esperado \(caminho)", linha: linha)
    exigir(!url.path.contains("@") && !url.path.contains("%40"),
           "\(contexto): JID no caminho: \(url.path)", linha: linha)
    exigir(cabecalho(p, "Authorization") == "Bearer \(chave)",
           "\(contexto): Authorization \(cabecalho(p, "Authorization") ?? "ausente"), esperado Bearer \(chave)",
           linha: linha)
    exigir(cabecalho(p, "Origin") == nil, "\(contexto): pedido leva Origin", linha: linha)
    exigir(cabecalho(p, "Sec-Fetch-Site") == nil, "\(contexto): pedido leva Sec-Fetch-Site", linha: linha)
    if metodo == "GET" || metodo == "DELETE" {
        exigir((p.httpBody ?? Data()).isEmpty, "\(contexto): \(metodo) com corpo", linha: linha)
    }
    if let esperada {
        let q = query(p, contexto)
        exigir(q == esperada, "\(contexto): query \(q), esperada \(esperada)", linha: linha)
    }
    if let prazo {
        exigir(p.timeoutInterval == prazo,
               "\(contexto): timeoutInterval \(p.timeoutInterval), esperado \(prazo)", linha: linha)
    }
}

/// Corpo JSON do POST: exatamente estas chaves e valores (snake_case, sem chave nula).
private func conferirCorpo(_ p: URLRequest, _ esperado: [String: Any], _ contexto: String, linha: UInt = #line) {
    let tipo = cabecalho(p, "Content-Type") ?? ""
    exigir(tipo.hasPrefix("application/json"),
           "\(contexto): Content-Type \(tipo.isEmpty ? "ausente" : tipo), esperado application/json", linha: linha)
    guard let dados = p.httpBody, !dados.isEmpty else {
        exigir(false, "\(contexto): POST sem corpo", linha: linha); return
    }
    let obj = try? JSONSerialization.jsonObject(with: dados) as? [String: Any]
    exigir(obj != nil, "\(contexto): corpo não é objeto JSON: \(String(decoding: dados, as: UTF8.self))", linha: linha)
    for (k, v) in obj! {
        exigir(!(v is NSNull), "\(contexto): corpo leva chave nula \(k)", linha: linha)
    }
    exigir(Set(obj!.keys) == Set(esperado.keys),
           "\(contexto): chaves do corpo \(obj!.keys.sorted()), esperadas \(esperado.keys.sorted())", linha: linha)
    exigir(NSDictionary(dictionary: obj!).isEqual(to: esperado),
           "\(contexto): corpo \(String(decoding: dados, as: UTF8.self)), esperado \(esperado)", linha: linha)
}

// MARK: - fixtures (formas de docs/whatsapp-ponte.md)

private let conta1 = "554791744143"
private let jidPessoa = "5547999990000@s.whatsapp.net"
private let jidGrupo = "120363406741729308@g.us"

private let contasJSON = #"""
{"ok": true, "contas": [
 {"conta": "554791744143", "jid": "554791744143:17@s.whatsapp.net", "nome": "Luccas", "padrao": true,
  "estado": "conectada", "motivo": null, "desde": 1762270000, "nao_lidas": 12, "conversas_nao_lidas": 3},
 {"conta": "554792508292", "jid": null, "nome": null, "padrao": false, "estado": "deslogada",
  "motivo": "logout", "desde": 1762270100, "nao_lidas": 0, "conversas_nao_lidas": 0}]}
"""#

private let conversaObj = #"""
{"jid": "5547999990000@s.whatsapp.net", "jids": ["5547999990000@s.whatsapp.net"], "tipo": "individual",
 "nome": "Fulano", "nao_lidas": 2, "marcada_nao_lida": false, "ts": 1762270500, "ultima": null}
"""#

private let mensagemObj = #"""
{"id": "3EB0B0B0", "conversa": "5547999990000@s.whatsapp.net", "remetente": "554791744143@s.whatsapp.net",
 "remetente_nome": null, "de_mim": true, "ts": 1762270700, "tipo": "texto", "texto": "chego em 10",
 "midia": null, "citacao": null, "reacoes": [], "editada": null, "apagada": null, "status": "enviada"}
"""#

private let pareamentoObj = #"""
{"id": "p-7f3a9c", "estado": "qr", "qr": "2@AbCd", "qr_expira_em": 1762270620, "fim": null, "conta": null, "motivo": null}
"""#

private let grupoObj = #"""
{"jid": "120363406741729308@g.us", "nome": "COISAS", "descricao": "", "criado": 1575256960,
 "dono": "554792508292@s.whatsapp.net", "so_admins_enviam": false,
 "participantes": [{"jid": "554791744143@s.whatsapp.net", "telefone": "554791744143", "lid": null,
   "nome": "Luccas", "admin": true, "superadmin": false, "eu": true}]}
"""#

private let ponteJSON = #"{"ok": true, "servico": "whatsapp-ponte", "contrato": 1, "versao": "a1b2c3d"}"#
private let envioJSON = #"{"ok": true, "ref": "k-41", "mensagem": \#(mensagemObj)}"#
private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])
private let onda = (0..<64).map { $0 * 100 / 63 }

// MARK: - gate

@main
enum WhatsAppClienteCheck {
    static func main() async {
        defer { try? FileManager.default.removeItem(at: pastaBase) }
        let _: WATransporte = WATransporteURLSession()

        await semChave()
        await leituras()
        await midiaEFoto()
        await envios()
        await pareamento()
        await releituraNo401()
        await foraDoAr()
        await errosDoContrato()
        try? FileManager.default.removeItem(at: pastaBase)
        print("ok")
    }

    // MARK: sem arquivo de chave: nenhuma conexão

    static func semChave() async {
        let (c, t, _) = novoCliente(chave: nil)
        let r = await c.identificar()
        exigir(r == .semChave, "sem chave: identificar() devolveu \(r), esperado .semChave")
        let arq = URL(fileURLWithPath: "/tmp/x.pdf")
        await exigirLanca(.semChave, "sem chave: contas") { try await c.contas() }
        await exigirLanca(.semChave, "sem chave: conversas") { try await c.conversas(conta: conta1) }
        await exigirLanca(.semChave, "sem chave: conversa") { try await c.conversa(conta: conta1, jid: jidPessoa) }
        await exigirLanca(.semChave, "sem chave: mensagens") { try await c.mensagens(conta: conta1, conversa: jidPessoa) }
        await exigirLanca(.semChave, "sem chave: midia") {
            try await c.midia(conta: conta1, conversa: jidPessoa, id: "3EB0", miniatura: true)
        }
        await exigirLanca(.semChave, "sem chave: recuperarMidia") {
            try await c.recuperarMidia(conta: conta1, conversa: jidPessoa, id: "3EB0")
        }
        await exigirLanca(.semChave, "sem chave: foto") { try await c.foto(conta: conta1, jid: jidPessoa, etag: nil) }
        await exigirLanca(.semChave, "sem chave: grupo") { try await c.grupo(conta: conta1, jid: jidGrupo) }
        await exigirLanca(.semChave, "sem chave: enviarTexto") {
            try await c.enviarTexto(conta: conta1, para: jidPessoa, texto: "oi", citar: nil, ref: "k-1")
        }
        await exigirLanca(.semChave, "sem chave: enviarMidia") {
            try await c.enviarMidia(conta: conta1, para: jidPessoa, tipo: "documento", arquivo: arq,
                                    nome: nil, legenda: nil, citar: nil, ref: "k-2")
        }
        await exigirLanca(.semChave, "sem chave: enviarVoz") {
            try await c.enviarVoz(conta: conta1, para: jidPessoa, arquivo: arq, segundos: 3, onda: onda,
                                  citar: nil, ref: "k-3")
        }
        await exigirLanca(.semChave, "sem chave: reagir") {
            try await c.reagir(conta: conta1, conversa: jidPessoa, alvo: "3EB0", emoji: "👍")
        }
        await exigirLanca(.semChave, "sem chave: marcarLida") { try await c.marcarLida(conta: conta1, conversa: jidPessoa) }
        await exigirLanca(.semChave, "sem chave: iniciarPareamento") { try await c.iniciarPareamento() }
        await exigirLanca(.semChave, "sem chave: pareamentoAtual") { try await c.pareamentoAtual() }
        await exigirLanca(.semChave, "sem chave: cancelarPareamento") { try await c.cancelarPareamento() }
        exigir(t.pedidos.isEmpty, "sem chave: \(t.pedidos.count) pedido(s) chegaram ao transporte, esperado 0")
    }

    // MARK: rotas de leitura

    static func leituras() async {
        let (c, t, _) = novoCliente()

        t.fila = [ok(ponteJSON)]
        let id = await c.identificar()
        exigir(id == .presente(versao: "a1b2c3d"), "identificar(): \(id), esperado .presente(versao: a1b2c3d)")
        conferir(t.pedido(0), "GET", "/v1/ponte", query: [:], prazo: 15, "identificar")

        t.fila = [ok(contasJSON)]
        let contas = await exigirOk("contas") { try await c.contas() }
        exigir(contas.map(\.conta) == ["554791744143", "554792508292"], "contas(): \(contas.map(\.conta))")
        conferir(t.pedido(1), "GET", "/v1/contas", query: [:], prazo: 15, "contas")

        t.fila = [ok(#"{"ok": true, "conversas": [\#(conversaObj)], "antes": "c1"}"#)]
        let cv = await exigirOk("conversas") { try await c.conversas(conta: conta1) }
        exigir(cv.conversas.map(\.jid) == [jidPessoa] && cv.antes == "c1", "conversas(): \(cv)")
        conferir(t.pedido(2), "GET", "/v1/conversas", query: ["conta": conta1, "limite": "50"], prazo: 15,
                 "conversas sem cursor")

        t.fila = [ok(#"{"ok": true, "conversas": [], "antes": null}"#)]
        let cv2 = await exigirOk("conversas com cursor") {
            try await c.conversas(conta: conta1, limite: 20, antes: "cur/sor=1")
        }
        exigir(cv2.conversas.isEmpty && cv2.antes == nil, "conversas com cursor: \(cv2)")
        conferir(t.pedido(3), "GET", "/v1/conversas",
                 query: ["conta": conta1, "limite": "20", "antes": "cur/sor=1"], prazo: 15, "conversas com cursor")

        t.fila = [ok(#"{"ok": true, "conversa": \#(conversaObj)}"#)]
        let um = await exigirOk("conversa") { try await c.conversa(conta: conta1, jid: jidPessoa) }
        exigir(um.jid == jidPessoa && um.nome == "Fulano", "conversa(): \(um)")
        conferir(t.pedido(4), "GET", "/v1/conversa", query: ["conta": conta1, "jid": jidPessoa], prazo: 15,
                 "conversa")
        let bruta = URLComponents(url: t.pedido(4).url!, resolvingAgainstBaseURL: false)!.percentEncodedQuery ?? ""
        exigir(bruta.contains("jid=5547999990000%40s.whatsapp.net") || bruta.contains("jid=5547999990000@s.whatsapp.net"),
               "conversa: jid não chegou na query (\(bruta))")

        t.fila = [ok(#"{"ok": true, "conversa": "\#(jidGrupo)", "mensagens": [\#(mensagemObj)], "antes": "m9"}"#)]
        let ms = await exigirOk("mensagens") { try await c.mensagens(conta: conta1, conversa: jidGrupo) }
        exigir(ms.mensagens.map(\.id) == ["3EB0B0B0"] && ms.antes == "m9" && ms.conversa == jidGrupo,
               "mensagens(): \(ms)")
        conferir(t.pedido(5), "GET", "/v1/mensagens",
                 query: ["conta": conta1, "conversa": jidGrupo, "limite": "50"], prazo: 15, "mensagens sem cursor")

        t.fila = [ok(#"{"ok": true, "conversa": "\#(jidGrupo)", "mensagens": [], "antes": null}"#)]
        _ = await exigirOk("mensagens com cursor") {
            try await c.mensagens(conta: conta1, conversa: jidGrupo, limite: 30, antes: "m9")
        }
        conferir(t.pedido(6), "GET", "/v1/mensagens",
                 query: ["conta": conta1, "conversa": jidGrupo, "limite": "30", "antes": "m9"], prazo: 15,
                 "mensagens com cursor")

        t.fila = [ok(#"{"ok": true, "grupo": \#(grupoObj)}"#)]
        let g = await exigirOk("grupo") { try await c.grupo(conta: conta1, jid: jidGrupo) }
        exigir(g.nome == "COISAS" && g.participantes.count == 1, "grupo(): \(g)")
        conferir(t.pedido(7), "GET", "/v1/grupo", query: ["conta": conta1, "jid": jidGrupo], prazo: 15, "grupo")

        exigir(t.pedidos.count == 8, "leituras: \(t.pedidos.count) pedidos, esperado 8 (um por chamada)")
    }

    // MARK: mídia e foto

    static func midiaEFoto() async {
        let (c, t, _) = novoCliente()

        t.fila = [.http(200, ["Content-Type": "image/jpeg"], jpeg)]
        let m = await exigirOk("midia miniatura") {
            try await c.midia(conta: conta1, conversa: jidGrupo, id: "3EB0A1", miniatura: true)
        }
        exigir(m.dados == jpeg, "midia miniatura: bytes diferentes do que a ponte mandou")
        exigir(m.mimetype == "image/jpeg", "midia miniatura: mimetype \(m.mimetype ?? "nil"), esperado image/jpeg")
        conferir(t.pedido(0), "GET", "/v1/midia",
                 query: ["conta": conta1, "conversa": jidGrupo, "id": "3EB0A1", "miniatura": "1"], prazo: 120,
                 "midia miniatura")

        let pdf = Data("%PDF-1.4".utf8)
        t.fila = [.http(200, ["Content-Type": "application/pdf"], pdf)]
        let cheia = await exigirOk("midia cheia") {
            try await c.midia(conta: conta1, conversa: jidGrupo, id: "3EB0A2", miniatura: false)
        }
        exigir(cheia.dados == pdf && cheia.mimetype == "application/pdf",
               "midia cheia: \(cheia.dados.count) bytes, mimetype \(cheia.mimetype ?? "nil")")
        var q = query(t.pedido(1), "midia cheia")
        exigir(q["miniatura"] == nil || q["miniatura"] == "0",
               "midia cheia: miniatura=\(q["miniatura"] ?? "") na query, esperado ausente ou 0")
        q["miniatura"] = nil
        exigir(q == ["conta": conta1, "conversa": jidGrupo, "id": "3EB0A2"], "midia cheia: query \(q)")
        conferir(t.pedido(1), "GET", "/v1/midia", prazo: 120, "midia cheia")

        t.fila = [ok(#"{"ok": true}"#)]
        _ = await exigirOk("recuperarMidia") {
            try await c.recuperarMidia(conta: conta1, conversa: jidGrupo, id: "3EB0A2")
        }
        conferir(t.pedido(2), "POST", "/v1/midia/recuperar", "recuperarMidia")
        conferirCorpo(t.pedido(2), ["conta": conta1, "conversa": jidGrupo, "id": "3EB0A2"], "recuperarMidia")

        // foto sem etag: 200 com ETag entre aspas
        t.fila = [.http(200, ["Content-Type": "image/jpeg", "ETag": "\"abc\""], jpeg)]
        let f1 = await exigirOk("foto nova") { try await c.foto(conta: conta1, jid: jidPessoa, etag: nil) }
        exigir(f1 == .nova(jpeg, etag: "abc"), "foto 200: \(f1), esperado .nova(dados, etag: \"abc\")")
        conferir(t.pedido(3), "GET", "/v1/foto", query: ["conta": conta1, "jid": jidPessoa, "tamanho": "miniatura"],
                 prazo: 15, "foto sem etag")
        exigir(cabecalho(t.pedido(3), "If-None-Match") == nil, "foto sem etag: pedido leva If-None-Match")

        // com etag: If-None-Match entre aspas, 304 = igual
        t.fila = [.http(304, ["ETag": "\"abc\""], Data())]
        let f2 = await exigirOk("foto igual") { try await c.foto(conta: conta1, jid: jidPessoa, etag: "abc") }
        exigir(f2 == .igual, "foto 304: \(f2), esperado .igual")
        exigir(cabecalho(t.pedido(4), "If-None-Match") == "\"abc\"",
               "foto com etag: If-None-Match \(cabecalho(t.pedido(4), "If-None-Match") ?? "ausente"), esperado \"abc\"")
        conferir(t.pedido(4), "GET", "/v1/foto", query: ["conta": conta1, "jid": jidPessoa, "tamanho": "miniatura"],
                 prazo: 15, "foto com etag")

        t.fila = [erro(404, "sem_foto")]
        let f3 = await exigirOk("foto sem foto") { try await c.foto(conta: conta1, jid: jidPessoa, etag: "abc") }
        exigir(f3 == .semFoto, "foto 404 sem_foto: \(f3), esperado .semFoto")

        t.fila = [.http(200, ["Content-Type": "image/jpeg"], jpeg)]
        let f4 = await exigirOk("foto sem ETag") { try await c.foto(conta: conta1, jid: jidPessoa, etag: nil) }
        exigir(f4 == .nova(jpeg, etag: nil), "foto 200 sem ETag: \(f4), esperado .nova(dados, etag: nil)")

        // outro 404 não é "sem foto": é erro da ponte
        t.fila = [erro(404, "conta_inexistente", detalhe: "y")]
        await exigirLanca(.ponte(status: 404, erro: "conta_inexistente", detalhe: "y"), "foto 404 conta_inexistente") {
            try await c.foto(conta: conta1, jid: jidPessoa, etag: nil)
        }
    }

    // MARK: envios

    static func envios() async {
        let (c, t, _) = novoCliente()

        t.fila = [ok(envioJSON)]
        let e1 = await exigirOk("enviarTexto") {
            try await c.enviarTexto(conta: conta1, para: jidPessoa, texto: "chego em 10", citar: nil, ref: "k-41")
        }
        exigir(e1.ref == "k-41" && e1.mensagem.id == "3EB0B0B0" && e1.mensagem.status == .enviada,
               "enviarTexto: \(e1)")
        conferir(t.pedido(0), "POST", "/v1/enviar/texto", prazo: 120, "enviarTexto")
        conferirCorpo(t.pedido(0), ["conta": conta1, "para": jidPessoa, "texto": "chego em 10", "ref": "k-41"],
                      "enviarTexto sem citar")

        t.fila = [ok(envioJSON)]
        _ = await exigirOk("enviarTexto citando") {
            try await c.enviarTexto(conta: conta1, para: jidPessoa, texto: "sim", citar: "3EB0FFEE", ref: "k-44")
        }
        conferirCorpo(t.pedido(1), ["conta": conta1, "para": jidPessoa, "texto": "sim", "citar": "3EB0FFEE",
                                     "ref": "k-44"], "enviarTexto citando")

        // arquivo vai como caminho absoluto, não como file:// URL
        let doc = URL(fileURLWithPath: "/tmp/knobler envio/9F1C.pdf")
        t.fila = [ok(envioJSON)]
        _ = await exigirOk("enviarMidia documento") {
            try await c.enviarMidia(conta: conta1, para: jidGrupo, tipo: "documento", arquivo: doc,
                                    nome: "proposta.pdf", legenda: nil, citar: nil, ref: "k-42")
        }
        conferir(t.pedido(2), "POST", "/v1/enviar/midia", prazo: 120, "enviarMidia")
        conferirCorpo(t.pedido(2), ["conta": conta1, "para": jidGrupo, "tipo": "documento",
                                     "arquivo": "/tmp/knobler envio/9F1C.pdf", "nome": "proposta.pdf",
                                     "ref": "k-42"], "enviarMidia documento")

        let foto = URL(fileURLWithPath: "/tmp/knobler envio/A1.jpg")
        t.fila = [ok(envioJSON)]
        _ = await exigirOk("enviarMidia imagem") {
            try await c.enviarMidia(conta: conta1, para: jidGrupo, tipo: "imagem", arquivo: foto,
                                    nome: nil, legenda: "segue", citar: "3EB0FFEE", ref: "k-45")
        }
        conferirCorpo(t.pedido(3), ["conta": conta1, "para": jidGrupo, "tipo": "imagem",
                                     "arquivo": "/tmp/knobler envio/A1.jpg", "legenda": "segue",
                                     "citar": "3EB0FFEE", "ref": "k-45"], "enviarMidia imagem")

        let voz = URL(fileURLWithPath: "/tmp/knobler envio/voz-7A.ogg")
        t.fila = [ok(envioJSON)]
        _ = await exigirOk("enviarVoz") {
            try await c.enviarVoz(conta: conta1, para: jidPessoa, arquivo: voz, segundos: 12, onda: onda,
                                  citar: nil, ref: "k-43")
        }
        conferir(t.pedido(4), "POST", "/v1/enviar/voz", prazo: 120, "enviarVoz")
        conferirCorpo(t.pedido(4), ["conta": conta1, "para": jidPessoa, "arquivo": "/tmp/knobler envio/voz-7A.ogg",
                                     "segundos": 12, "onda": onda, "ref": "k-43"], "enviarVoz")

        t.fila = [ok(envioJSON)]
        _ = await exigirOk("enviarVoz citando") {
            try await c.enviarVoz(conta: conta1, para: jidPessoa, arquivo: voz, segundos: 1, onda: onda,
                                  citar: "3EB0FFEE", ref: "k-46")
        }
        conferirCorpo(t.pedido(5), ["conta": conta1, "para": jidPessoa, "arquivo": "/tmp/knobler envio/voz-7A.ogg",
                                     "segundos": 1, "onda": onda, "citar": "3EB0FFEE", "ref": "k-46"],
                      "enviarVoz citando")

        t.fila = [ok(#"{"ok": true}"#)]
        _ = await exigirOk("reagir") {
            try await c.reagir(conta: conta1, conversa: jidGrupo, alvo: "3EB0A1B2", emoji: "👍")
        }
        conferir(t.pedido(6), "POST", "/v1/reagir", "reagir")
        conferirCorpo(t.pedido(6), ["conta": conta1, "conversa": jidGrupo, "alvo": "3EB0A1B2", "emoji": "👍"],
                      "reagir")

        // emoji vazio remove a reação: a chave tem que ir, vazia
        t.fila = [ok(#"{"ok": true}"#)]
        _ = await exigirOk("reagir removendo") {
            try await c.reagir(conta: conta1, conversa: jidGrupo, alvo: "3EB0A1B2", emoji: "")
        }
        conferirCorpo(t.pedido(7), ["conta": conta1, "conversa": jidGrupo, "alvo": "3EB0A1B2", "emoji": ""],
                      "reagir removendo")

        t.fila = [ok(#"{"ok": true, "marcadas": 3}"#)]
        let n = await exigirOk("marcarLida") { try await c.marcarLida(conta: conta1, conversa: jidPessoa) }
        exigir(n == 3, "marcarLida devolveu \(n), esperado 3")
        conferir(t.pedido(8), "POST", "/v1/lida", "marcarLida")
        conferirCorpo(t.pedido(8), ["conta": conta1, "conversa": jidPessoa], "marcarLida")

        exigir(t.pedidos.count == 9, "envios: \(t.pedidos.count) pedidos, esperado 9 (um por chamada)")
    }

    // MARK: pareamento

    static func pareamento() async {
        let (c, t, _) = novoCliente()

        t.fila = [ok(#"{"ok": true, "pareamento": \#(pareamentoObj)}"#)]
        let p1 = await exigirOk("iniciarPareamento") { try await c.iniciarPareamento() }
        exigir(p1.id == "p-7f3a9c" && p1.estado == .qr, "iniciarPareamento: \(p1)")
        conferir(t.pedido(0), "POST", "/v1/pareamento", "iniciarPareamento")
        exigir((t.pedido(0).httpBody ?? Data()).isEmpty, "iniciarPareamento: POST com corpo, esperado sem corpo")

        // outro em andamento: 409 traz o atual no corpo, e ele volta sem lançar
        t.fila = [erro(409, "pareamento_em_andamento", extra: #", "pareamento": \#(pareamentoObj)"#)]
        let p2 = await exigirOk("iniciarPareamento 409") { try await c.iniciarPareamento() }
        exigir(p2.id == "p-7f3a9c" && p2.qr == "2@AbCd", "iniciarPareamento 409: \(p2)")

        t.fila = [ok(#"{"ok": true, "pareamento": \#(pareamentoObj)}"#)]
        let p3 = await exigirOk("pareamentoAtual") { try await c.pareamentoAtual() }
        exigir(p3?.id == "p-7f3a9c", "pareamentoAtual 200: \(String(describing: p3))")
        conferir(t.pedido(2), "GET", "/v1/pareamento", query: [:], prazo: 15, "pareamentoAtual")

        t.fila = [erro(404, "sem_pareamento")]
        let p4 = await exigirOk("pareamentoAtual 404") { try await c.pareamentoAtual() }
        exigir(p4 == nil, "pareamentoAtual 404 sem_pareamento: \(String(describing: p4)), esperado nil")

        t.fila = [ok(#"{"ok": true}"#)]
        _ = await exigirOk("cancelarPareamento") { try await c.cancelarPareamento() }
        conferir(t.pedido(4), "DELETE", "/v1/pareamento", "cancelarPareamento")

        exigir(t.pedidos.count == 5, "pareamento: \(t.pedidos.count) pedidos, esperado 5")
    }

    // MARK: 401: relê o arquivo uma vez e repete

    static func releituraNo401() async {
        // o arquivo troca enquanto o primeiro pedido está na rede
        do {
            let (c, t, arq) = novoCliente(chave: "chave-a")
            t.aoPedir = { n in if n == 1 { gravar("chave-b\n", em: arq) } }
            t.fila = [erro(401, "nao_autorizado"), ok(contasJSON)]
            let contas = await exigirOk("401 com chave nova") { try await c.contas() }
            exigir(contas.count == 2, "401 com chave nova: \(contas.count) contas")
            exigir(t.pedidos.count == 2, "401 com chave nova: \(t.pedidos.count) pedidos, esperado 2")
            conferir(t.pedido(0), "GET", "/v1/contas", chave: "chave-a", "401: primeiro pedido")
            conferir(t.pedido(1), "GET", "/v1/contas", chave: "chave-b", "401: pedido repetido")

            // a chave relida fica: o pedido seguinte já sai com ela
            t.aoPedir = nil
            t.fila = [ok(contasJSON)]
            _ = await exigirOk("depois da releitura") { try await c.contas() }
            conferir(t.pedido(2), "GET", "/v1/contas", chave: "chave-b", "pedido depois da releitura")
        }

        // POST repetido leva o mesmo corpo
        do {
            let (c, t, arq) = novoCliente(chave: "chave-a")
            t.aoPedir = { n in if n == 1 { gravar("chave-b", em: arq) } }
            t.fila = [erro(401, "nao_autorizado"), ok(envioJSON)]
            _ = await exigirOk("401 em enviarTexto") {
                try await c.enviarTexto(conta: conta1, para: jidPessoa, texto: "oi", citar: nil, ref: "k-50")
            }
            exigir(t.pedidos.count == 2, "401 em enviarTexto: \(t.pedidos.count) pedidos, esperado 2")
            conferir(t.pedido(1), "POST", "/v1/enviar/texto", prazo: 120, chave: "chave-b", "401: POST repetido")
            conferirCorpo(t.pedido(1), ["conta": conta1, "para": jidPessoa, "texto": "oi", "ref": "k-50"],
                          "401: POST repetido")
        }

        // dois 401 seguidos: a chave não confere, e para no segundo
        do {
            let (c, t, _) = novoCliente(chave: "chave-a")
            t.fila = [erro(401, "nao_autorizado"), erro(401, "nao_autorizado"), ok(contasJSON)]
            await exigirLanca(.chaveNaoConfere, "dois 401") { try await c.contas() }
            exigir(t.pedidos.count == 2, "dois 401: \(t.pedidos.count) pedidos, esperado exatamente 2")
        }

        // identificar() segue a mesma regra
        do {
            let (c, t, _) = novoCliente(chave: "chave-a")
            t.fila = [erro(401, "nao_autorizado"), erro(401, "nao_autorizado"), ok(ponteJSON)]
            let r = await c.identificar()
            exigir(r == .chaveNaoConfere, "identificar() com dois 401: \(r), esperado .chaveNaoConfere")
            exigir(t.pedidos.count == 2, "identificar() com dois 401: \(t.pedidos.count) pedidos, esperado 2")
        }
        do {
            let (c, t, arq) = novoCliente(chave: "chave-a")
            t.aoPedir = { n in if n == 1 { gravar("chave-b", em: arq) } }
            t.fila = [erro(401, "nao_autorizado"), ok(ponteJSON)]
            let r = await c.identificar()
            exigir(r == .presente(versao: "a1b2c3d"), "identificar() com 401 e chave nova: \(r), esperado .presente")
            exigir(t.pedidos.count == 2, "identificar() com 401 e chave nova: \(t.pedidos.count) pedidos, esperado 2")
            conferir(t.pedido(1), "GET", "/v1/ponte", chave: "chave-b", "identificar() repetido")
        }
    }

    // MARK: ponte fora do ar

    static func foraDoAr() async {
        let codigos: [URLError.Code] = [.cannotConnectToHost, .timedOut, .networkConnectionLost, .cannotFindHost,
                                        .appTransportSecurityRequiresSecureConnection]
        for codigo in codigos {
            let (c, t, _) = novoCliente()
            t.fila = [.falha(codigo)]
            await exigirLanca(.foraDoAr, "URLError \(codigo.rawValue) em contas") { try await c.contas() }
            t.fila = [.falha(codigo)]
            await exigirLanca(.foraDoAr, "URLError \(codigo.rawValue) em enviarTexto") {
                try await c.enviarTexto(conta: conta1, para: jidPessoa, texto: "oi", citar: nil, ref: "k-1")
            }
            t.fila = [.falha(codigo)]
            let r = await c.identificar()
            exigir(r == .foraDoAr, "URLError \(codigo.rawValue) em identificar(): \(r), esperado .foraDoAr")
        }
        // a ponte cai entre o 401 e a repetição
        let (c, t, _) = novoCliente()
        t.fila = [erro(401, "nao_autorizado"), .falha(.cannotConnectToHost)]
        await exigirLanca(.foraDoAr, "401 e depois conexão recusada") { try await c.contas() }
    }

    // MARK: corpo de erro do contrato

    static func errosDoContrato() async {
        let (c, t, _) = novoCliente()

        t.fila = [erro(404, "conta_inexistente", detalhe: "a conta 5547 não existe")]
        await exigirLanca(.ponte(status: 404, erro: "conta_inexistente", detalhe: "a conta 5547 não existe"),
                          "404 conta_inexistente") { try await c.conversas(conta: "5547") }

        t.fila = [erro(409, "conta_desconectada", detalhe: "deslogada")]
        let e409 = await erroDe { try await c.enviarTexto(conta: conta1, para: jidPessoa, texto: "oi", citar: nil, ref: "k") }
        exigir((e409 as? WAErroDoCliente) == .ponte(status: 409, erro: "conta_desconectada", detalhe: "deslogada"),
               "409 conta_desconectada: \(String(describing: e409))")
        exigir((e409 as? WAErroDoCliente)?.contaDesconectada == true, "409 conta_desconectada: contaDesconectada != true")
        exigir((e409 as? WAErroDoCliente)?.midiaExpirada == false, "409 conta_desconectada: midiaExpirada == true")

        t.fila = [erro(410, "midia_expirada", detalhe: nil)]
        let e410 = await erroDe { try await c.midia(conta: conta1, conversa: jidGrupo, id: "3EB0A2", miniatura: false) }
        exigir((e410 as? WAErroDoCliente) == .ponte(status: 410, erro: "midia_expirada", detalhe: nil),
               "410 midia_expirada (sem detalhe): \(String(describing: e410))")
        exigir((e410 as? WAErroDoCliente)?.midiaExpirada == true, "410 midia_expirada: midiaExpirada != true")
        exigir((e410 as? WAErroDoCliente)?.contaDesconectada == false, "410 midia_expirada: contaDesconectada == true")

        t.fila = [erro(502, "whatsapp_recusou", detalhe: "recusado")]
        await exigirLanca(.ponte(status: 502, erro: "whatsapp_recusou", detalhe: "recusado"), "502 whatsapp_recusou") {
            try await c.enviarVoz(conta: conta1, para: jidPessoa, arquivo: URL(fileURLWithPath: "/tmp/v.ogg"),
                                  segundos: 2, onda: onda, citar: nil, ref: "k")
        }

        t.fila = [.http(500, ["Content-Type": "text/plain"], Data("Internal Server Error".utf8))]
        await exigirLanca(.ponte(status: 500, erro: "desconhecido", detalhe: nil), "500 sem JSON") {
            try await c.contas()
        }

        t.fila = [.http(200, ["Content-Type": "application/json"], Data("lixo".utf8))]
        await exigirLanca(.respostaInvalida, "200 com corpo que não é JSON") { try await c.contas() }
        t.fila = [ok(#"{"ok": true}"#)]
        await exigirLanca(.respostaInvalida, "200 sem o campo conversas") { try await c.conversas(conta: conta1) }
        t.fila = [ok(#"{"ok": true, "marcadas": "três"}"#)]
        await exigirLanca(.respostaInvalida, "200 com marcadas fora do tipo") {
            try await c.marcarLida(conta: conta1, conversa: jidPessoa)
        }

        for e: WAErroDoCliente in [.semChave, .foraDoAr, .chaveNaoConfere, .respostaInvalida,
                                   .ponte(status: 404, erro: "sem_midia", detalhe: nil)] {
            exigir(!e.contaDesconectada && !e.midiaExpirada, "\(e): contaDesconectada/midiaExpirada deveriam ser false")
        }

        // identificar(): o que não é 200 da ponte, 401 nem falha de conexão é "não é a ponte"
        t.fila = [erro(404, "rota_inexistente")]
        let r = await c.identificar()
        exigir(r == .naoEAPonte, "identificar() com 404: \(r), esperado .naoEAPonte")
    }
}
