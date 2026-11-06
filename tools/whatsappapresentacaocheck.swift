// Gate da etapa 21 do WhatsApp: textos e decisões puras de apresentação
// (Knobler/WhatsApp/WhatsAppApresentacao.swift). Prévia da linha da lista,
// hora da linha, separador de dia, duração, tamanho de arquivo, tique do
// status, estado da conta, rótulo da conta e os textos exatos de cada estado
// (mockup docs/vesta/mockups/2026-11-04-whatsapp/index.html).
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppEstado.swift \
//     Knobler/NotchNotification.swift Knobler/WhatsApp/WhatsAppCartao.swift \
//     Knobler/WhatsApp/WhatsAppApresentacao.swift tools/whatsappapresentacaocheck.swift \
//     -o /tmp/whatsappapresentacaocheck && /tmp/whatsappapresentacaocheck
//
// API que o gate fixa (além do que o plano já nomeia):
//   WAApresentacao.previa(ultima: WAUltima?, grupo: Bool, rascunho: String?) -> WAPrevia
//   WAApresentacao.hora(ts: Int, agora: Date, calendario: Calendar) -> String
//   WAApresentacao.separadorDeDia(ts: Int, agora: Date, calendario: Calendar) -> String
//   WAApresentacao.duracao(_ segundos: Int) -> String
//   WAApresentacao.tamanho(mimetype: String, bytes: Int) -> String
//   WAApresentacao.tique(_ estado: WAEstadoDaBolha) -> WATique
//   WAApresentacao.estadoDaConta(_ estado: WAEstadoConta) -> WAEstadoDaContaNaTela
//   WATextos.citacao(nome: String?)  — nil é a mensagem minha ("você")
//
// Tudo em memória: nenhuma rede, nenhum arquivo, nenhum UserDefaults.

import Foundation

private var falhas = 0

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappapresentacaocheck.swift:\(linha))")
        falhas += 1
    }
}

private func igual<T: Equatable>(_ obtido: T, _ esperado: T, _ msg: String, linha: UInt = #line) {
    exigir(obtido == esperado, "\(msg): obtido \(String(describing: obtido)), esperado \(String(describing: esperado))",
           linha: linha)
}

// MARK: - fábricas

private let DIEGO = "5547999990000@s.whatsapp.net"
private let TIA = "5547999990002@s.whatsapp.net"

private func ultima(tipo: WATipoMensagem = .texto, previa: String = "Fechado! Mando o briefing até sexta.",
                    remetente: String = DIEGO, remetenteNome: String? = nil, deMim: Bool = false,
                    apagada: Int? = nil, segundos: Int? = nil) -> WAUltima {
    WAUltima(id: "3EB0A1B2", deMim: deMim, remetente: remetente, remetenteNome: remetenteNome,
             tipo: tipo, previa: previa, ts: 1_762_270_500, apagada: apagada, segundos: segundos)
}

private func conta(_ numero: String, nome: String?) -> WAConta {
    WAConta(conta: numero, jid: "\(numero)@s.whatsapp.net", nome: nome, padrao: false,
            estado: .conectada, motivo: nil, desde: 1_762_000_000,
            naoLidas: 0, conversasNaoLidas: 0)
}

/// Confere os cinco campos da prévia de uma vez.
private func previa(_ p: WAPrevia, icone: String?, prefixo: String?, texto: String,
                    rascunho: Bool = false, apagada: Bool = false, _ caso: String, linha: UInt = #line) {
    igual(p.icone, icone, "\(caso): ícone", linha: linha)
    igual(p.prefixo, prefixo, "\(caso): prefixo", linha: linha)
    igual(p.texto, texto, "\(caso): texto", linha: linha)
    igual(p.rascunho, rascunho, "\(caso): rascunho", linha: linha)
    igual(p.apagada, apagada, "\(caso): apagada", linha: linha)
}

private func calendario(_ fuso: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: fuso)!
    c.locale = Locale(identifier: "pt_BR")
    return c
}

private func data(_ c: Calendar, _ a: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
    c.date(from: DateComponents(year: a, month: m, day: d, hour: h, minute: min))!
}

private func ts(_ c: Calendar, _ a: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Int {
    Int(data(c, a, m, d, h, min).timeIntervalSince1970)
}

// MARK: - casos

private func casosDePrevia() {
    let A = WAApresentacao.self

    // rascunho não vazio vence tudo, até mensagem apagada
    previa(A.previa(ultima: ultima(), grupo: false, rascunho: "Carlos, ajustei o orçamento de dezembro e…"),
           icone: nil, prefixo: "Rascunho:", texto: "Carlos, ajustei o orçamento de dezembro e…",
           rascunho: true, "rascunho sobre texto")
    previa(A.previa(ultima: ultima(previa: "", apagada: 1_762_270_600), grupo: false, rascunho: "volto já"),
           icone: nil, prefixo: "Rascunho:", texto: "volto já", rascunho: true, "rascunho sobre apagada")
    previa(A.previa(ultima: nil, grupo: false, rascunho: "oi"),
           icone: nil, prefixo: "Rascunho:", texto: "oi", rascunho: true, "rascunho sem última")
    // rascunho vazio não é rascunho
    previa(A.previa(ultima: ultima(), grupo: false, rascunho: ""),
           icone: nil, prefixo: nil, texto: "Fechado! Mando o briefing até sexta.", "rascunho vazio")

    // texto
    previa(A.previa(ultima: ultima(), grupo: false, rascunho: nil),
           icone: nil, prefixo: nil, texto: "Fechado! Mando o briefing até sexta.", "texto")

    // grupo: primeiro nome do remetente com dois-pontos; individual nunca tem prefixo
    previa(A.previa(ultima: ultima(previa: "Bom dia, pessoal!", remetenteNome: "Diego Martins"),
                    grupo: true, rascunho: nil),
           icone: nil, prefixo: "Diego:", texto: "Bom dia, pessoal!", "grupo com texto")
    previa(A.previa(ultima: ultima(previa: "Bom dia, pessoal!", remetenteNome: "Diego Martins"),
                    grupo: false, rascunho: nil),
           icone: nil, prefixo: nil, texto: "Bom dia, pessoal!", "individual com nome do remetente")
    previa(A.previa(ultima: ultima(tipo: .figurinha, previa: "", remetente: TIA, remetenteNome: "Tia Lúcia"),
                    grupo: true, rascunho: nil),
           icone: "face.smiling", prefixo: "Tia:", texto: "Figurinha", "grupo com figurinha")

    // mídia
    previa(A.previa(ultima: ultima(tipo: .imagem, previa: ""), grupo: false, rascunho: nil),
           icone: "camera", prefixo: nil, texto: "Foto", "imagem sem legenda")
    previa(A.previa(ultima: ultima(tipo: .video, previa: ""), grupo: false, rascunho: nil),
           icone: "video", prefixo: nil, texto: "Vídeo", "vídeo sem segundos")
    previa(A.previa(ultima: ultima(tipo: .video, previa: "", segundos: 18), grupo: false, rascunho: nil),
           icone: "video", prefixo: nil, texto: "Vídeo · 0:18", "vídeo com segundos")
    previa(A.previa(ultima: ultima(tipo: .audio, previa: ""), grupo: false, rascunho: nil),
           icone: "mic", prefixo: nil, texto: "Áudio", "áudio sem segundos")
    previa(A.previa(ultima: ultima(tipo: .audio, previa: "", segundos: 37), grupo: false, rascunho: nil),
           icone: "mic", prefixo: nil, texto: "Áudio · 0:37", "áudio com segundos")
    previa(A.previa(ultima: ultima(tipo: .voz, previa: ""), grupo: false, rascunho: nil),
           icone: "mic", prefixo: nil, texto: "Áudio", "voz sem segundos")
    previa(A.previa(ultima: ultima(tipo: .voz, previa: "", segundos: 37), grupo: false, rascunho: nil),
           icone: "mic", prefixo: nil, texto: "Áudio · 0:37", "voz com segundos")
    previa(A.previa(ultima: ultima(tipo: .documento, previa: "Proposta-Seller-nov26-v2.pdf"),
                    grupo: false, rascunho: nil),
           icone: "doc.text", prefixo: nil, texto: "Proposta-Seller-nov26-v2.pdf", "documento")
    previa(A.previa(ultima: ultima(tipo: .figurinha, previa: ""), grupo: false, rascunho: nil),
           icone: "face.smiling", prefixo: nil, texto: "Figurinha", "figurinha")

    // apagada vence o tipo
    previa(A.previa(ultima: ultima(previa: "", apagada: 1_762_270_600), grupo: false, rascunho: nil),
           icone: "nosign", prefixo: nil, texto: "Mensagem apagada", apagada: true, "texto apagado")
    let fotoApagada = A.previa(ultima: ultima(tipo: .imagem, previa: "", apagada: 1_762_270_600),
                               grupo: false, rascunho: nil)
    igual(fotoApagada.icone, "nosign", "foto apagada: ícone")
    igual(fotoApagada.texto, "Mensagem apagada", "foto apagada: texto")
    igual(fotoApagada.apagada, true, "foto apagada: apagada")

    // sem última mensagem
    previa(A.previa(ultima: nil, grupo: false, rascunho: nil),
           icone: nil, prefixo: nil, texto: "", "sem última")
}

private func casosDeHora() {
    let A = WAApresentacao.self
    let sp = calendario("America/Sao_Paulo")
    // quinta, 5 de novembro de 2026, 14:40 em São Paulo
    let agora = data(sp, 2026, 11, 5, 14, 40)

    igual(A.hora(ts: ts(sp, 2026, 11, 5, 14, 32), agora: agora, calendario: sp), "14:32", "hora: mesmo dia")
    igual(A.hora(ts: ts(sp, 2026, 11, 5, 9, 5), agora: agora, calendario: sp), "09:05", "hora: mesmo dia de manhã")
    igual(A.hora(ts: ts(sp, 2026, 11, 4, 18, 0), agora: agora, calendario: sp), "Ontem", "hora: ontem")
    igual(A.hora(ts: ts(sp, 2026, 11, 2, 10, 0), agora: agora, calendario: sp), "seg", "hora: segunda (3 dias)")
    igual(A.hora(ts: ts(sp, 2026, 10, 30, 10, 0), agora: agora, calendario: sp), "sex", "hora: sexta (6 dias)")
    igual(A.hora(ts: ts(sp, 2026, 10, 29, 10, 0), agora: agora, calendario: sp), "29/10/26", "hora: 7 dias")

    // terça, 10 de novembro: 03/11 já tem 7 dias, 04/11 tem 6
    let depois = data(sp, 2026, 11, 10, 9, 0)
    igual(A.hora(ts: ts(sp, 2026, 11, 3, 16, 0), agora: depois, calendario: sp), "03/11/26", "hora: mais velho")
    igual(A.hora(ts: ts(sp, 2026, 11, 4, 16, 0), agora: depois, calendario: sp), "qua", "hora: quarta (6 dias)")
    igual(A.hora(ts: ts(sp, 2025, 12, 31, 16, 0), agora: depois, calendario: sp), "31/12/25", "hora: ano passado")

    // o dia é o do calendário, não um bloco de 24 h
    let meiaNoite = data(sp, 2026, 11, 5, 0, 10)
    igual(A.hora(ts: ts(sp, 2026, 11, 4, 23, 50), agora: meiaNoite, calendario: sp), "Ontem",
          "hora: 20 min atrás mas ontem")
    let fimDoDia = data(sp, 2026, 11, 5, 23, 59)
    igual(A.hora(ts: ts(sp, 2026, 11, 5, 0, 5), agora: fimDoDia, calendario: sp), "00:05",
          "hora: 24 h quase cheias mas hoje")

    // o fuso é o do calendário: 22:30 de 04/11 em SP é 01:30 de 05/11 em UTC
    igual(A.hora(ts: ts(sp, 2026, 11, 4, 22, 30), agora: agora, calendario: sp), "Ontem",
          "hora: fuso de São Paulo, não UTC")
    let tq = calendario("Asia/Tokyo")
    let agoraTq = data(tq, 2026, 11, 5, 14, 40)
    igual(A.hora(ts: ts(tq, 2026, 11, 5, 9, 5), agora: agoraTq, calendario: tq), "09:05",
          "hora: formata no fuso do calendário (Tóquio)")
    igual(A.hora(ts: ts(tq, 2026, 11, 2, 9, 5), agora: agoraTq, calendario: tq), "seg",
          "hora: dia da semana no fuso do calendário (Tóquio)")
}

private func casosDeSeparador() {
    let A = WAApresentacao.self
    let sp = calendario("America/Sao_Paulo")
    let agora = data(sp, 2026, 11, 5, 14, 40)

    igual(A.separadorDeDia(ts: ts(sp, 2026, 11, 5, 8, 0), agora: agora, calendario: sp), "Hoje", "separador: hoje")
    igual(A.separadorDeDia(ts: ts(sp, 2026, 11, 4, 23, 0), agora: agora, calendario: sp), "Ontem", "separador: ontem")
    igual(A.separadorDeDia(ts: ts(sp, 2026, 11, 3, 10, 0), agora: agora, calendario: sp), "3 de novembro",
          "separador: anteontem é data, não dia da semana")
    igual(A.separadorDeDia(ts: ts(sp, 2026, 10, 29, 10, 0), agora: agora, calendario: sp), "29 de outubro",
          "separador: outro mês")
    let meiaNoite = data(sp, 2026, 11, 5, 0, 10)
    igual(A.separadorDeDia(ts: ts(sp, 2026, 11, 4, 23, 50), agora: meiaNoite, calendario: sp), "Ontem",
          "separador: dia do calendário, não 24 h")
}

private func casosDeDuracao() {
    let A = WAApresentacao.self
    igual(A.duracao(37), "0:37", "duração 37")
    igual(A.duracao(65), "1:05", "duração 65")
    igual(A.duracao(3723), "1:02:03", "duração 3723")
    igual(A.duracao(0), "0:00", "duração 0")
    igual(A.duracao(600), "10:00", "duração 600")
    igual(A.duracao(3600), "1:00:00", "duração 3600")
}

private func casosDeTamanho() {
    let A = WAApresentacao.self
    igual(A.tamanho(mimetype: "application/pdf", bytes: 839_680), "PDF · 820 KB", "tamanho: PDF em KB")
    igual(A.tamanho(mimetype: "application/pdf", bytes: 1_258_291), "PDF · 1,2 MB", "tamanho: PDF em MB, vírgula")
    igual(A.tamanho(mimetype: "application/octet-stream", bytes: 839_680), "820 KB",
          "tamanho: subtipo desconhecido é só o tamanho")
    igual(A.tamanho(mimetype: "application/octet-stream", bytes: 1_258_291), "1,2 MB",
          "tamanho: subtipo desconhecido em MB")
}

private func casosDeTique() {
    let A = WAApresentacao.self
    igual(A.tique(.enviando), .relogio, "tique: enviando")
    igual(A.tique(.enviada), .um, "tique: enviada")
    igual(A.tique(.entregue), .dois, "tique: entregue")
    igual(A.tique(.lida), .doisLida, "tique: lida")
    igual(A.tique(.falhou), .nenhum, "tique: falhou")
    igual(A.tique(.recebida), .nenhum, "tique: recebida")
}

private func casosDeConta() {
    let A = WAApresentacao.self
    func estado(_ e: WAEstadoConta, _ rotulo: String?, qr: Bool, linha: UInt = #line) {
        let t = A.estadoDaConta(e)
        igual(t.rotulo, rotulo, "estado da conta \(e): rótulo", linha: linha)
        igual(t.precisaQR, qr, "estado da conta \(e): precisaQR", linha: linha)
    }
    estado(.conectada, nil, qr: false)
    estado(.deslogada, "desconectada", qr: true)
    estado(.desconectada, "reconectando", qr: false)
    estado(.conectando, "reconectando", qr: false)
    estado(.substituida, "em uso noutro processo", qr: false)
    estado(.suspensa, "suspensa", qr: false)

    igual(WACartao.rotuloDaConta(conta: conta("554791744143", nome: "Luccas Silveira"), numero: "554791744143"),
          "Luccas Silveira · 4143", "rótulo da conta com nome")
    igual(WACartao.rotuloDaConta(conta: conta("554792508292", nome: nil), numero: "554792508292"),
          "WhatsApp · 8292", "rótulo da conta sem nome")
}

private func casosDeTextos() {
    let X = WATextos.self

    // ponte fora
    igual(X.ponteForaTitulo, "A ponte do WhatsApp não está respondendo.", "ponte fora: título")
    igual(X.ponteForaApoio, "O Knobler tenta de novo sozinho. Para religar agora, rode no Terminal:", "ponte fora: apoio")
    igual(X.ponteForaComando, "~/Code/whatsapp-mcp/whatsapp-bridge/servico.sh", "ponte fora: comando")
    igual(X.ponteForaRodape, "Enquanto isso, os cards voltam a vir do WhatsApp Desktop.", "ponte fora: rodapé")

    // chave recusada e chave ausente: mesmo título, mesmo botão, apoio diferente
    let recusada = "A ponte recusou a chave que o Knobler leu. Os dois precisam ler o mesmo arquivo de chave; confira o arquivo e tente de novo."
    let ausente = "O Knobler não achou o arquivo de chave da ponte em ~/Library/Application Support/whatsapp-bridge/api-key. A ponte cria esse arquivo quando sobe; confira se ela está rodando e tente de novo."
    igual(X.chaveTitulo, "A chave da ponte não confere.", "chave: título")
    igual(X.chaveApoio, recusada, "chave: apoio da recusada")
    igual(X.chaveAusenteApoio, ausente, "chave: apoio da ausente")
    igual(X.tentarDeNovo, "Tentar de novo", "chave: botão")
    igual(X.apoioDaChave(ausente: true), ausente, "apoioDaChave(ausente: true)")
    igual(X.apoioDaChave(ausente: false), recusada, "apoioDaChave(ausente: false)")

    // incompatível
    igual(X.incompativelTitulo, "A ponte do WhatsApp é de outra versão.", "incompatível: título")
    igual(X.incompativelApoio, "Atualize a ponte ou o Knobler para a mesma versão do contrato.", "incompatível: apoio")

    // QR, com o rótulo da mesma fonte do card
    let r4143 = WACartao.rotuloDaConta(conta: conta("554791744143", nome: "Luccas Silveira"), numero: "554791744143")
    let r8292 = WACartao.rotuloDaConta(conta: conta("554792508292", nome: nil), numero: "554792508292")
    igual(X.qrTitulo(rotulo: r4143),
          "Luccas Silveira · 4143 desconectada — escaneie o QR no celular: WhatsApp › Aparelhos conectados › Conectar aparelho",
          "QR: título")
    igual(X.qrApoio(outra: r8292),
          "O código troca sozinho enquanto espera. WhatsApp · 8292 segue funcionando.", "QR: apoio")
    igual(X.qrApoio(outra: r4143),
          "O código troca sozinho enquanto espera. Luccas Silveira · 4143 segue funcionando.", "QR: apoio, outra conta")

    // QR expirado
    igual(X.qrExpiradoTitulo, "QR expirado", "QR expirado: título")
    igual(X.qrGerarOutro, "Gerar outro", "QR expirado: botão")
    igual(X.qrExpiradoApoio, "O código vale por cerca de 160 s. Gere outro e escaneie de novo.", "QR expirado: apoio")

    // lista
    igual(X.carregando, "Carregando conversas…", "carregando")
    igual(X.vazioTitulo, "Nenhuma conversa ainda", "vazio: título")
    igual(X.vazioApoio, "A primeira mensagem que chegar nesta conta aparece aqui.", "vazio: apoio")
    igual(X.semPareamento, "As conversas desta conta voltam depois de parear.", "conta sem pareamento")

    // bolha
    igual(X.falhaTitulo, "não enviada", "falha: rótulo")
    igual(X.falhaAcao, "tentar de novo", "falha: ação")
    igual(X.midiaIndisponivel, "mídia indisponível", "mídia indisponível")
    igual(X.apagada, "Mensagem apagada", "apagada")

    // compositor
    igual(X.placeholderConversa, "Mensagem", "placeholder da conversa")
    igual(X.placeholderResposta, "Responder…", "placeholder da resposta")
    igual(X.gravando, "Gravando", "gravação")
    igual(X.ouvindo, "Ouvindo", "ditado")
    igual(X.marcarComoLida, "Marcar como lida", "botão marcar como lida")
    igual(X.citacao(nome: nil), "Respondendo a você", "citação de mensagem minha")
    igual(X.citacao(nome: "Ana Ribeiro"), "Respondendo a Ana Ribeiro", "citação de outra pessoa")

    // a prévia apagada usa o mesmo texto da bolha apagada
    let p = WAApresentacao.previa(ultima: ultima(previa: "", apagada: 1), grupo: false, rascunho: nil)
    igual(p.texto, X.apagada, "prévia apagada = WATextos.apagada")
}

@main
enum Gate {
    static func main() {
        casosDePrevia()
        casosDeHora()
        casosDeSeparador()
        casosDeDuracao()
        casosDeTamanho()
        casosDeTique()
        casosDeConta()
        casosDeTextos()
        if falhas > 0 {
            print("FALHOU: \(falhas) asserção(ões) em tools/whatsappapresentacaocheck.swift")
            exit(1)
        }
        print("ok: whatsappapresentacaocheck")
    }
}
