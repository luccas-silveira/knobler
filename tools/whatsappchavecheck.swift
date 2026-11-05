// Gate da etapa 2 do WhatsApp: arquivo da chave da ponte, porta configurável
// e leitura da resposta de identificação (Knobler/WhatsApp/WhatsAppChave.swift).
// Contrato: docs/whatsapp-ponte.md (chave em :50-66, tabela de `GET /` em :441-447).
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift \
//     tools/whatsappchavecheck.swift \
//     -o /tmp/whatsappchavecheck && /tmp/whatsappchavecheck
//
// Nunca lê a chave de verdade: no caminho padrão só calcula o caminho e
// pergunta se existe, e confere que isso não criou nem apagou a pasta.

import Foundation

private func exigir(_ cond: Bool, _ msg: String) {
    if !cond {
        print("FALHOU: \(msg)")
        exit(1)
    }
}

/// (existe, é pasta) do caminho, sem criar nada.
private func estado(_ path: String) -> (Bool, Bool) {
    var pasta: ObjCBool = false
    let existe = FileManager.default.fileExists(atPath: path, isDirectory: &pasta)
    return (existe, pasta.boolValue)
}

@main
enum Gate {
    static func main() {
        caminhoPadrao()
        arquivoDaChave()
        porta()
        sonda()
        print("ok")
    }

    // MARK: - caminho padrão, sem mexer no disco

    static func caminhoPadrao() {
        let suporte = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let pastaDaPonte = suporte.appendingPathComponent("whatsapp-bridge", isDirectory: true)
        let antes = estado(pastaDaPonte.path)
        let arquivoAntes = estado(pastaDaPonte.appendingPathComponent("api-key").path)

        let caminho = WAChaveDaPonte.caminhoPadrao
        let existe = WAChaveDaPonte.existe()

        let depois = estado(pastaDaPonte.path)
        exigir(depois == antes,
               "calcular caminhoPadrao/existe() mudou a pasta whatsapp-bridge: antes \(antes), depois \(depois)")
        exigir(estado(pastaDaPonte.appendingPathComponent("api-key").path) == arquivoAntes,
               "calcular caminhoPadrao/existe() mudou o arquivo api-key")

        exigir(caminho.path.hasSuffix("Library/Application Support/whatsapp-bridge/api-key"),
               "caminhoPadrao não termina em Library/Application Support/whatsapp-bridge/api-key: \(caminho.path)")
        exigir(caminho.standardizedFileURL.path
                == suporte.appendingPathComponent("whatsapp-bridge/api-key").standardizedFileURL.path,
               "caminhoPadrao não está no Application Support do usuário: \(caminho.path)")

        // existe() no padrão diz a verdade sobre o arquivo de agora (arquivo, não pasta)
        exigir(existe == (arquivoAntes.0 && !arquivoAntes.1),
               "existe() no caminho padrão devolveu \(existe), mas o arquivo está \(arquivoAntes)")
    }

    // MARK: - leitura do arquivo numa pasta temporária

    static func arquivoDaChave() {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("whatsappchavecheck-\(getpid())", isDirectory: true)
        try? fm.removeItem(at: base)
        try! fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer {
            // o arquivo 000 precisa voltar a ter dono pra pasta sumir
            try? fm.setAttributes([.posixPermissions: 0o600],
                                  ofItemAtPath: base.appendingPathComponent("trancada").path)
            try? fm.removeItem(at: base)
        }

        // sem arquivo
        let ausente = base.appendingPathComponent("api-key")
        exigir(WAChaveDaPonte.existe(em: ausente) == false, "sem arquivo, existe devolveu true")
        exigir(WAChaveDaPonte.ler(em: ausente) == nil, "sem arquivo, ler não devolveu nil")
        exigir(!fm.fileExists(atPath: ausente.path), "existe/ler criaram o arquivo da chave")

        // espaço e quebra nas pontas são cortados
        let comEspaco = base.appendingPathComponent("com-espaco")
        try! "  abc123\n".write(to: comEspaco, atomically: true, encoding: .utf8)
        exigir(WAChaveDaPonte.existe(em: comEspaco), "arquivo com chave: existe devolveu false")
        let lida = WAChaveDaPonte.ler(em: comEspaco)
        exigir(lida == "abc123", "\"  abc123\\n\" leu \(String(describing: lida)), esperado \"abc123\"")

        // tab e CRLF também são ponta
        let crlf = base.appendingPathComponent("crlf")
        try! "\t\r\nabc123\r\n\t".write(to: crlf, atomically: true, encoding: .utf8)
        let lidaCrlf = WAChaveDaPonte.ler(em: crlf)
        exigir(lidaCrlf == "abc123", "\"\\t\\r\\nabc123\\r\\n\\t\" leu \(String(describing: lidaCrlf))")

        // não valida formato: o contrato manda só cortar e guardar
        let curta = base.appendingPathComponent("curta")
        try! "x".write(to: curta, atomically: true, encoding: .utf8)
        exigir(WAChaveDaPonte.ler(em: curta) == "x", "chave fora do formato não foi devolvida como está")

        // só espaço e quebra
        let vazia = base.appendingPathComponent("vazia")
        try! "  \n\n \t \r\n".write(to: vazia, atomically: true, encoding: .utf8)
        exigir(WAChaveDaPonte.ler(em: vazia) == nil, "arquivo só com espaços e quebras não leu nil")
        let zero = base.appendingPathComponent("zero")
        try! Data().write(to: zero)
        exigir(WAChaveDaPonte.ler(em: zero) == nil, "arquivo vazio não leu nil")

        // caminho que é pasta
        let pasta = base.appendingPathComponent("pasta", isDirectory: true)
        try! fm.createDirectory(at: pasta, withIntermediateDirectories: true)
        exigir(WAChaveDaPonte.existe(em: pasta) == false, "caminho que é pasta deu existe == true")
        exigir(WAChaveDaPonte.ler(em: pasta) == nil, "caminho que é pasta não leu nil")

        // ilegível (modo 000): nil sem travar. Root lê qualquer coisa, então
        // a asserção só vale para usuário comum (a CI e o Mac do dev).
        let trancada = base.appendingPathComponent("trancada")
        try! "abc123\n".write(to: trancada, atomically: true, encoding: .utf8)
        try! fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: trancada.path)
        let lidaTrancada = WAChaveDaPonte.ler(em: trancada)
        if getuid() != 0 {
            exigir(lidaTrancada == nil, "arquivo com modo 000 leu \(String(describing: lidaTrancada))")
        }
    }

    // MARK: - porta configurável

    static func porta() {
        exigir(WAConfig.chavePorta == "whatsappPortaDaPonte",
               "chave da porta no UserDefaults é \(WAConfig.chavePorta)")

        let suite = "com.zoi.knobler.whatsappchavecheck-\(getpid())"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        defer { d.removePersistentDomain(forName: suite) }

        exigir(WAConfig.porta(d) == 8099, "UserDefaults vazio deu porta \(WAConfig.porta(d)), esperado 8099")

        d.set(18099, forKey: "whatsappPortaDaPonte")
        exigir(WAConfig.porta(d) == 18099, "whatsappPortaDaPonte = 18099 deu porta \(WAConfig.porta(d))")

        for invalida in [0, -1, 70000] {
            d.set(invalida, forKey: "whatsappPortaDaPonte")
            exigir(WAConfig.porta(d) == 8099,
                   "whatsappPortaDaPonte = \(invalida) deu porta \(WAConfig.porta(d)), esperado 8099")
        }

        let base = WAConfig.base(porta: 8099).absoluteString
        exigir(base == "http://127.0.0.1:8099", "base(porta: 8099) é \(base)")
        let outra = WAConfig.base(porta: 18099).absoluteString
        exigir(outra == "http://127.0.0.1:18099", "base(porta: 18099) é \(outra)")
    }

    // MARK: - conclusão da sonda de GET /

    static func sonda() {
        func corpo(_ s: String) -> Data { Data(s.utf8) }
        let ponte = corpo(#"{"ok":true,"servico":"whatsapp-ponte","contrato":1,"versao":"a1b2c3d"}"#)

        func caso(_ status: Int?, _ dados: Data?, _ esperado: WAConclusaoDaSonda, _ nome: String) {
            let r = WAConclusaoDaSonda.concluir(status: status, corpo: dados)
            exigir(r == esperado, "\(nome): concluiu \(r), esperado \(esperado)")
        }

        caso(200, ponte, .presente(versao: "a1b2c3d"), "200 com a ponte, contrato 1")
        caso(200, corpo(#"{"ok":true,"servico":"whatsapp-ponte","contrato":1,"versao":"dev"}"#),
             .presente(versao: "dev"), "200 com versao dev")
        caso(200, corpo(#"{"ok":true,"servico":"whatsapp-ponte","contrato":2,"versao":"a1b2c3d"}"#),
             .incompativel(contrato: 2), "200 com contrato 2")
        caso(200, corpo(#"{"ok":true,"servico":"whatsapp-ponte","contrato":0,"versao":"a1b2c3d"}"#),
             .incompativel(contrato: 0), "200 com contrato 0")
        caso(200, corpo(#"{"ok":true,"servico":"outro-servico","contrato":1,"versao":"a1b2c3d"}"#),
             .naoEAPonte, "200 com outro servico")
        caso(200, corpo("<html>oi</html>"), .naoEAPonte, "200 com corpo que não é JSON")
        caso(200, corpo(#"{"ok":true}"#), .naoEAPonte, "200 com JSON sem os campos")
        caso(200, nil, .naoEAPonte, "200 sem corpo")
        caso(201, ponte, .naoEAPonte, "201 com o corpo da ponte (só vale 200)")
        caso(401, nil, .chaveNaoConfere, "401")
        caso(401, corpo(#"{"ok":false,"erro":"chave"}"#), .chaveNaoConfere, "401 com corpo")
        caso(nil, nil, .foraDoAr, "sem status (conexão recusada)")
        caso(nil, ponte, .foraDoAr, "sem status, mesmo com corpo")
        caso(403, ponte, .naoEAPonte, "403")
        caso(404, nil, .naoEAPonte, "404")
        caso(500, corpo("erro"), .naoEAPonte, "500")

        // só a ponte identificada conta como identificada
        let todos: [WAConclusaoDaSonda] = [
            .presente(versao: "a1b2c3d"), .incompativel(contrato: 2), .chaveNaoConfere,
            .foraDoAr, .naoEAPonte, .semChave,
        ]
        for c in todos {
            let esperado: Bool
            if case .presente = c { esperado = true } else { esperado = false }
            exigir(c.identificada == esperado, "\(c).identificada é \(c.identificada), esperado \(esperado)")
        }
    }
}
