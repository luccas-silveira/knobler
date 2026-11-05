// Gate da etapa 4 do WhatsApp: sondagem de identificação da ponte
// (Knobler/WhatsApp/WhatsAppSonda.swift). Contrato: docs/whatsapp-ponte.md
// (chave em :50-66 — "O Knobler só sonda a ponte se o arquivo existir. Sem
// arquivo, nenhuma conexão é aberta"; identificação em GET /v1/ponte).
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift \
//     Knobler/WhatsApp/WhatsAppCliente.swift Knobler/WhatsApp/WhatsAppSonda.swift \
//     tools/whatsappsondacheck.swift \
//     -o /tmp/whatsappsondacheck && /tmp/whatsappsondacheck
//
// Nada sai pela rede: a fábrica de cliente monta um `WACliente` com transporte
// falso, que conta cada pedido e devolve respostas roteirizadas. A chave mora
// numa pasta de NSTemporaryDirectory(); a chave de verdade da ponte nunca é lida
// e `WhatsAppSonda.shared` nunca é instanciado.

import Combine
import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappsondacheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - transporte falso

/// Pedido que chegou sem resposta roteirizada (a sonda pediu mais do que devia).
private struct SemRoteiro: Error {}

private final class TransporteFalso: WATransporte {
    var fila: [(Int, Data)] = []
    private(set) var pedidos: [URLRequest] = []

    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        pedidos.append(pedido)
        guard !fila.isEmpty else { throw SemRoteiro() }
        let (status, corpo) = fila.removeFirst()
        let r = HTTPURLResponse(url: pedido.url ?? URL(string: "http://127.0.0.1")!,
                                statusCode: status, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "application/json"])!
        return (corpo, r)
    }
}

private let ponteJSON = #"{"ok": true, "servico": "whatsapp-ponte", "contrato": 1, "versao": "a1b2c3d"}"#
private let naoAutorizado = #"{"ok": false, "erro": "nao_autorizado", "detalhe": "chave"}"#

private func ok(_ corpo: String = ponteJSON) -> (Int, Data) { (200, Data(corpo.utf8)) }
private func status401() -> (Int, Data) { (401, Data(naoAutorizado.utf8)) }

// MARK: - ambiente

private let pastaBase = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("whatsappsondacheck-\(getpid())", isDirectory: true)
private var contador = 0

private func gravar(_ texto: String, em url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try! Data(texto.utf8).write(to: url)
}

/// Uma sonda isolada: arquivo de chave próprio (gravado ou não), transporte
/// falso compartilhado por todos os clientes que a fábrica montar, e contador
/// de chamadas da fábrica.
private final class Cenario {
    let arquivo: URL
    let transporte = TransporteFalso()
    var fabricados = 0
    var sonda: WhatsAppSonda!

    @MainActor
    init(chave: String?) {
        contador += 1
        arquivo = pastaBase.appendingPathComponent("s\(contador)", isDirectory: true)
            .appendingPathComponent("api-key")
        if let chave { gravar(chave + "\n", em: arquivo) }
        let arquivo = self.arquivo
        let transporte = self.transporte
        sonda = WhatsAppSonda(
            existeChave: { WAChaveDaPonte.existe(em: arquivo) },
            fabricaDeCliente: { [unowned self] in
                self.fabricados += 1
                return WACliente(porta: 8099, caminhoDaChave: arquivo, transporte: transporte)
            })
    }

    var pedidos: Int { transporte.pedidos.count }
}

private func descrever(_ c: WAConclusaoDaSonda?) -> String {
    c.map { String(describing: $0) } ?? "nil"
}

@main
enum WhatsAppSondaCheck {
    @MainActor
    static func main() async {
        defer { try? FileManager.default.removeItem(at: pastaBase) }

        // Fonte única para a vitrine e a lista de atalhos: existe um `shared`.
        // Só a referência é compilada; a closure nunca roda (o `shared` leria a
        // chave real da ponte).
        let _: () -> WhatsAppSonda = { WhatsAppSonda.shared }

        // MARK: estado inicial: nunca sondou
        do {
            let c = Cenario(chave: "chave-a")
            exigir(c.sonda.conclusao == nil,
                   "antes de sondar, conclusao deveria ser nil, veio \(descrever(c.sonda.conclusao))")
            exigir(c.sonda.identificada == false, "antes de sondar, identificada deveria ser false")
            exigir(c.fabricados == 0, "montar a sonda não pode montar cliente (fábrica chamada \(c.fabricados)x)")
            exigir(c.pedidos == 0, "montar a sonda não pode abrir conexão (\(c.pedidos) pedido(s))")
        }

        // MARK: sem arquivo de chave: nenhuma conexão
        do {
            let c = Cenario(chave: nil)
            await c.sonda.sondar()
            exigir(c.sonda.conclusao == .semChave,
                   "sem arquivo de chave, sondar() deveria concluir .semChave, veio \(descrever(c.sonda.conclusao))")
            exigir(c.sonda.identificada == false, "sem arquivo de chave, identificada deveria ser false")
            exigir(c.fabricados == 0,
                   "sem arquivo de chave, a fábrica de cliente não pode ser chamada (foi \(c.fabricados)x)")
            exigir(c.pedidos == 0, "sem arquivo de chave, o transporte não pode receber pedido (\(c.pedidos))")

            // sondarSeVelha segue a mesma regra
            await c.sonda.sondarSeVelha(agora: Date().addingTimeInterval(3600))
            exigir(c.sonda.conclusao == .semChave,
                   "sem arquivo de chave, sondarSeVelha deveria manter .semChave, veio \(descrever(c.sonda.conclusao))")
            exigir(c.fabricados == 0, "sem arquivo de chave, sondarSeVelha chamou a fábrica \(c.fabricados)x")
            exigir(c.pedidos == 0, "sem arquivo de chave, sondarSeVelha abriu \(c.pedidos) pedido(s)")
        }

        // MARK: a chave aparece depois (a ponte foi instalada com o app aberto)
        do {
            let c = Cenario(chave: nil)
            await c.sonda.sondar()
            exigir(c.sonda.conclusao == .semChave, "primeira sonda sem chave: veio \(descrever(c.sonda.conclusao))")
            gravar("chave-a\n", em: c.arquivo)
            c.transporte.fila = [ok()]
            await c.sonda.sondar()
            exigir(c.sonda.conclusao == .presente(versao: "a1b2c3d"),
                   "com a chave gravada depois, sondar() deveria identificar a ponte, veio \(descrever(c.sonda.conclusao))")
            exigir(c.sonda.identificada, "com a chave gravada depois, identificada deveria ser true")
            exigir(c.pedidos == 1, "com a chave gravada depois, esperava 1 pedido, chegaram \(c.pedidos)")
        }

        // MARK: com chave e GET /v1/ponte 200 do contrato: identificada
        do {
            let c = Cenario(chave: "chave-a")
            c.transporte.fila = [ok()]
            var avisos = 0
            let assinatura = c.sonda.objectWillChange.sink { _ in avisos += 1 }
            await c.sonda.sondar()
            assinatura.cancel()
            exigir(c.sonda.conclusao == .presente(versao: "a1b2c3d"),
                   "200 do contrato deveria concluir .presente(versao: \"a1b2c3d\"), veio \(descrever(c.sonda.conclusao))")
            exigir(c.sonda.identificada, "200 do contrato: identificada deveria ser true")
            exigir(c.pedidos == 1, "200 do contrato: esperava 1 pedido, chegaram \(c.pedidos)")
            let p = c.transporte.pedidos[0]
            exigir(p.httpMethod == "GET" && p.url?.path == "/v1/ponte",
                   "a sonda deveria pedir GET /v1/ponte, pediu \(p.httpMethod ?? "?") \(p.url?.path ?? "?")")
            exigir(avisos >= 1, "a conclusão mudou e a tela não foi avisada (objectWillChange não disparou)")

            // a ponte sumiu (arquivo apagado): a conclusão não fica velha
            try? FileManager.default.removeItem(at: c.arquivo)
            await c.sonda.sondar()
            exigir(c.sonda.conclusao == .semChave,
                   "arquivo apagado depois de identificar: deveria concluir .semChave, veio \(descrever(c.sonda.conclusao))")
            exigir(c.sonda.identificada == false, "arquivo apagado depois de identificar: identificada deveria ser false")
            exigir(c.pedidos == 1, "arquivo apagado: nenhum pedido novo deveria sair, chegaram \(c.pedidos)")
        }

        // MARK: dois 401: a chave não confere
        do {
            let c = Cenario(chave: "chave-a")
            c.transporte.fila = [status401(), status401()]
            await c.sonda.sondar()
            exigir(c.sonda.conclusao == .chaveNaoConfere,
                   "dois 401 deveriam concluir .chaveNaoConfere, veio \(descrever(c.sonda.conclusao))")
            exigir(c.sonda.identificada == false, "dois 401: identificada deveria ser false")
        }

        // MARK: outro serviço na porta
        do {
            let c = Cenario(chave: "chave-a")
            c.transporte.fila = [ok(#"{"hello":"world"}"#)]
            await c.sonda.sondar()
            exigir(c.sonda.conclusao == .naoEAPonte,
                   "200 com {\"hello\":\"world\"} deveria concluir .naoEAPonte, veio \(descrever(c.sonda.conclusao))")
            exigir(c.sonda.identificada == false, "outro serviço na porta: identificada deveria ser false")
        }

        // MARK: estrangulamento de 30 s
        do {
            let t = Date()
            let c = Cenario(chave: "chave-a")
            c.transporte.fila = [ok(), ok()]
            await c.sonda.sondarSeVelha(agora: t)
            exigir(c.pedidos == 1, "primeira sondarSeVelha deveria sondar (1 pedido), chegaram \(c.pedidos)")
            exigir(c.sonda.identificada, "primeira sondarSeVelha com 200 do contrato: identificada deveria ser true")
            await c.sonda.sondarSeVelha(agora: t.addingTimeInterval(10))
            exigir(c.pedidos == 1, "sondarSeVelha 10 s depois não deveria sondar de novo, chegaram \(c.pedidos) pedidos")
            exigir(c.sonda.identificada, "sondarSeVelha pulada não pode apagar a conclusão anterior")
        }
        do {
            let t = Date()
            let c = Cenario(chave: "chave-a")
            c.transporte.fila = [ok(), ok()]
            await c.sonda.sondarSeVelha(agora: t)
            await c.sonda.sondarSeVelha(agora: t.addingTimeInterval(31))
            exigir(c.pedidos == 2, "sondarSeVelha 31 s depois deveria sondar de novo (2 pedidos), chegaram \(c.pedidos)")
        }
        do {
            // chamar a cada 10 s não pode adiar a sondagem para sempre: a janela
            // conta da última sondagem feita, não da última chamada.
            let t = Date()
            let c = Cenario(chave: "chave-a")
            c.transporte.fila = [ok(), ok()]
            await c.sonda.sondarSeVelha(agora: t)
            await c.sonda.sondarSeVelha(agora: t.addingTimeInterval(10))
            await c.sonda.sondarSeVelha(agora: t.addingTimeInterval(20))
            exigir(c.pedidos == 1, "sondarSeVelha a 10 e 20 s não deveria sondar, chegaram \(c.pedidos) pedidos")
            await c.sonda.sondarSeVelha(agora: t.addingTimeInterval(31))
            exigir(c.pedidos == 2,
                   "sondarSeVelha 31 s depois da última sondagem deveria sondar, mesmo com chamadas no meio; chegaram \(c.pedidos)")
        }

        // MARK: sondar() sempre sonda
        do {
            let t = Date()
            let c = Cenario(chave: "chave-a")
            c.transporte.fila = [ok(), ok(), ok()]
            await c.sonda.sondarSeVelha(agora: t)
            await c.sonda.sondar()
            exigir(c.pedidos == 2, "sondar() logo depois de sondarSeVelha deveria sondar, chegaram \(c.pedidos) pedidos")
            await c.sonda.sondar()
            exigir(c.pedidos == 3, "sondar() repetido deveria sondar de novo, chegaram \(c.pedidos) pedidos")
        }
        do {
            // a conclusão acompanha a última sondagem, não a primeira
            let c = Cenario(chave: "chave-a")
            c.transporte.fila = [ok(), ok(#"{"hello":"world"}"#)]
            await c.sonda.sondar()
            exigir(c.sonda.identificada, "primeira sondagem com 200 do contrato: identificada deveria ser true")
            await c.sonda.sondar()
            exigir(c.sonda.conclusao == .naoEAPonte,
                   "segunda sondagem com outro serviço deveria virar .naoEAPonte, veio \(descrever(c.sonda.conclusao))")
            exigir(c.sonda.identificada == false, "segunda sondagem com outro serviço: identificada deveria ser false")
        }

        print("whatsappsondacheck: ok")
    }
}
