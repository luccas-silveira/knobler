// Gate da etapa 1 do visualizador do WhatsApp: foto e vídeo abrem dentro do
// notch, cobrindo a coluna da conversa (mockup aprovado em
// docs/vesta/mockups/2026-11-10-whatsapp-visualizador/index.html).
//
//   ver a linha `swift_teste tools/whatsappvisualizadorcheck.swift $VM_FONTES
//   $WA_NUCLEO Knobler/WhatsApp/WhatsAppCartao.swift
//   Knobler/WhatsApp/WhatsAppApresentacao.swift
//   Knobler/WhatsApp/WhatsAppConversaModelo.swift
//   Knobler/WhatsApp/WhatsAppVisualizador.swift` em tools/check.sh.
//
// O que se prova (o que quem usa vê):
//   - clicar em foto ou vídeo pede `.verNoNotch`; documento, áudio, figurinha,
//     mídia indisponível e bolha local continuam como eram;
//   - o estado do visualizador a partir do que `store.midia.arquivo` respondeu:
//     arquivo vira foto ou vídeo pelo tipo, aguardando vira carregando,
//     indisponível vira indisponível, conta desconectada e falha viram
//     "Não deu para abrir…";
//   - os textos: "Buscando a foto/o vídeo no celular…", o aviso de
//     indisponível com o primeiro nome de quem mandou (some quando é minha), o
//     de erro sem segunda frase, o nome no topo ("Você" quando é minha), a
//     legenda só quando há texto e o subtítulo "<conversa> · hoje, 14:41";
//   - no NotchViewModel, o que está sendo visto é por tela: abrir preenche na
//     hora; o X, trocar de conversa e fechar o notch zeram.
//
// A ligação nas views (a bolha não abre mais no app padrão, a conversa mostra
// o visualizador por cima, fontes do snapshot, cenários) fica no
// tools/whatsappvisualizadorligacaocheck.sh.
//
// Nada sai pela rede nem toca disco do usuário: só funções puras e dois
// `NotchViewModel` em memória, com o histórico de notificações desligado.

import AppKit

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappvisualizadorcheck.swift:\(linha))")
        exit(1)
    }
}

private func igual(_ veio: String?, _ esperado: String?, _ caso: String, linha: UInt = #line) {
    exigir(veio == esperado,
           "\(caso): esperado \(esperado.map { "\"\($0)\"" } ?? "nil"), veio \(veio.map { "\"\($0)\"" } ?? "nil")",
           linha: linha)
}

// MARK: - números e relógio do teste

private let A = "554791744143"                      // conta
private let EU = A + "@s.whatsapp.net"
private let X = "554799990001@s.whatsapp.net"       // conversa individual (Marina Costa)
private let G = "120363000000000001@g.us"           // grupo (Operacional ZOI)
private let DIEGO = "554799000002@s.whatsapp.net"

private let kX = WAChave(conta: A, jid: X)
private let kG = WAChave(conta: A, jid: G)

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    return c
}()

private func data(mes: Int = 11, dia: Int, hora: Int, minuto: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: mes, day: dia, hour: hora, minute: minuto))!
}

private func ts(mes: Int = 11, dia: Int, hora: Int, minuto: Int = 0) -> Int {
    Int(data(mes: mes, dia: dia, hora: hora, minuto: minuto).timeIntervalSince1970)
}

/// "Agora" do teste: 10 de novembro de 2026, 15:00 em São Paulo.
private let agora = data(dia: 10, hora: 15)

// MARK: - fixtures

private func midia(_ mimetype: String, nome: String = "", segundos: Int? = nil) -> WAMidia {
    WAMidia(mimetype: mimetype, nome: nome, tamanho: 840_000, segundos: segundos, miniatura: true, baixada: true)
}

private func msg(_ id: String, de remetente: String, nome: String? = nil, ts t: Int = 0,
                 tipo: WATipoMensagem = .texto, texto: String = "", midia m: WAMidia? = nil,
                 conversa: String = X) -> WAMensagem {
    let deMim = remetente == EU
    return WAMensagem(id: id, conversa: conversa, remetente: remetente, remetenteNome: nome,
                      deMim: deMim, ts: t, tipo: tipo, texto: texto, midia: m, citacao: nil,
                      reacoes: [], editada: nil, apagada: nil, status: deMim ? .entregue : nil)
}

private func bolha(_ m: WAMensagem, envio: WAEnvio? = nil, indisponivel: Bool = false) -> WABolha {
    var b = WABolha(mensagem: m)
    b.envio = envio
    b.midiaIndisponivel = indisponivel
    return b
}

private func conversa(_ jid: String, nome: String, tipo: WATipoConversa) -> WAConversa {
    WAConversa(jid: jid, jids: [jid], tipo: tipo, nome: nome, naoLidas: 0,
               marcadaNaoLida: false, ts: ts(dia: 10, hora: 14), ultima: nil)
}

private let marina = conversa(X, nome: "Marina Costa", tipo: .individual)
private let operacional = conversa(G, nome: "Operacional ZOI", tipo: .grupo)

private let fotoDoDiego = msg("g1", de: DIEGO, nome: "Diego Martins", tipo: .imagem,
                              texto: "Set montado pra gravação de amanhã", midia: midia("image/jpeg"),
                              conversa: G)
private let videoDoDiego = msg("g2", de: DIEGO, nome: "Diego Martins", tipo: .video,
                               midia: midia("video/mp4", segundos: 42), conversa: G)
private let minhaFoto = msg("g3", de: EU, tipo: .imagem, midia: midia("image/jpeg"), conversa: G)
private let meuVideo = msg("g4", de: EU, tipo: .video, midia: midia("video/mp4", segundos: 9), conversa: G)
private let fotoDaMarina = msg("x1", de: X, tipo: .imagem, midia: midia("image/jpeg"))

// MARK: - 1. o clique

private func acaoDoClique() {
    func acao(_ b: WABolha) -> WAAcaoDaBolha { WAConversaModelo.acao(bolha: b) }

    let doc = msg("c3", de: X, tipo: .documento, midia: midia("application/pdf", nome: "contrato.pdf"))
    let audio = msg("c4", de: X, tipo: .audio, midia: midia("audio/mpeg", segundos: 95))
    let voz = msg("c5", de: X, tipo: .voz, midia: midia("audio/ogg; codecs=opus", segundos: 37))
    let figurinha = msg("c7", de: X, tipo: .figurinha, midia: midia("image/webp"))
    let texto = msg("c6", de: X, texto: "oi")

    // foto e vídeo, recebidos ou meus, abrem dentro do notch
    for (nome, m) in [("foto recebida", fotoDoDiego), ("vídeo recebido", videoDoDiego),
                      ("foto minha", minhaFoto), ("vídeo meu", meuVideo), ("foto individual", fotoDaMarina)] {
        exigir(acao(bolha(m)) == .verNoNotch, "clique em \(nome) → .verNoNotch, veio \(acao(bolha(m)))")
    }
    // o resto não muda
    exigir(acao(bolha(doc)) == .mostrarNoFinder, "documento → .mostrarNoFinder, veio \(acao(bolha(doc)))")
    exigir(acao(bolha(audio)) == .tocarAudio, "áudio → .tocarAudio, veio \(acao(bolha(audio)))")
    exigir(acao(bolha(voz)) == .tocarAudio, "voz → .tocarAudio, veio \(acao(bolha(voz)))")
    exigir(acao(bolha(figurinha)) == .nenhuma, "figurinha → .nenhuma, veio \(acao(bolha(figurinha)))")
    exigir(acao(bolha(texto)) == .nenhuma, "texto → .nenhuma, veio \(acao(bolha(texto)))")
    exigir(acao(bolha(fotoDoDiego, indisponivel: true)) == .nenhuma,
           "foto com mídia indisponível → .nenhuma (a bolha já diz), veio \(acao(bolha(fotoDoDiego, indisponivel: true)))")
    exigir(acao(bolha(videoDoDiego, indisponivel: true)) == .nenhuma,
           "vídeo com mídia indisponível → .nenhuma, veio \(acao(bolha(videoDoDiego, indisponivel: true)))")
    // bolha local: o arquivo ainda não é da ponte, não há o que buscar
    let fotoLocal = msg("local-r9", de: EU, tipo: .imagem, midia: midia("image/jpeg"))
    let videoLocal = msg("local-r7", de: EU, tipo: .video, midia: midia("video/mp4", segundos: 3))
    exigir(acao(bolha(fotoLocal, envio: .enviando(ref: "r9"))) == .nenhuma,
           "foto local enviando → .nenhuma, veio \(acao(bolha(fotoLocal, envio: .enviando(ref: "r9"))))")
    exigir(acao(bolha(videoLocal, envio: .enviando(ref: "r7"))) == .nenhuma,
           "vídeo local enviando → .nenhuma, veio \(acao(bolha(videoLocal, envio: .enviando(ref: "r7"))))")
}

// MARK: - 2. o estado do visualizador

private func estadoDoVisualizador() {
    func e(_ r: WAResultadoMidia, _ m: WAMostraMidia) -> WAEstadoDoVisualizador {
        WAVisualizador.estado(resultado: r, midia: m)
    }
    let jpg = URL(fileURLWithPath: "/tmp/knobler-wa/g1.jpg")
    let mp4 = URL(fileURLWithPath: "/tmp/knobler-wa/g2.mp4")

    exigir(e(.arquivo(jpg), .imagem) == .foto(jpg), "arquivo de foto → .foto(url), veio \(e(.arquivo(jpg), .imagem))")
    exigir(e(.arquivo(mp4), .video) == .video(mp4), "arquivo de vídeo → .video(url) (player), veio \(e(.arquivo(mp4), .video))")
    exigir(e(.aguardando, .imagem) == .carregando, "aguardando (foto) → .carregando, veio \(e(.aguardando, .imagem))")
    exigir(e(.aguardando, .video) == .carregando, "aguardando (vídeo) → .carregando, veio \(e(.aguardando, .video))")
    exigir(e(.indisponivel, .imagem) == .indisponivel, "indisponível → .indisponivel, veio \(e(.indisponivel, .imagem))")
    exigir(e(.indisponivel, .video) == .indisponivel, "indisponível (vídeo) → .indisponivel, veio \(e(.indisponivel, .video))")
    // conta fora do ar e falha não são "o celular apagou": não podem pedir reenvio
    for m in [WAMostraMidia.imagem, .video] {
        exigir(e(.contaDesconectada, m) == .naoDeuParaAbrir,
               "conta desconectada (\(m)) → .naoDeuParaAbrir, veio \(e(.contaDesconectada, m))")
        exigir(e(.falhou, m) == .naoDeuParaAbrir, "falhou (\(m)) → .naoDeuParaAbrir, veio \(e(.falhou, m))")
    }
}

// MARK: - 3. textos

private func textos() {
    // carregando troca foto/vídeo
    igual(WATextos.buscandoNoCelular(video: false), "Buscando a foto no celular…", "carregando foto")
    igual(WATextos.buscandoNoCelular(video: true), "Buscando o vídeo no celular…", "carregando vídeo")

    // botões do topo
    igual(WATextos.abrirNoPreVisualizacao, "Abrir no Pré-Visualização", "botão abrir")
    igual(WATextos.mostrarNoFinder, "Mostrar no Finder", "botão Finder")
    igual(WATextos.fechar, "Fechar", "botão fechar")

    // avisos: indisponível com o primeiro nome de quem mandou
    func aviso(_ e: WAEstadoDoVisualizador, _ m: WAMensagem, _ c: WAConversa) -> WAAvisoDoVisualizador? {
        WAVisualizador.aviso(e, mensagem: m, conversa: c)
    }
    func mostra(_ a: WAAvisoDoVisualizador?) -> String {
        guard let a else { return "nil" }
        return "(\"\(a.titulo)\", \(a.apoio.map { "\"\($0)\"" } ?? "nil"))"
    }
    func confere(_ veio: WAAvisoDoVisualizador?, _ titulo: String, _ apoio: String?, _ caso: String,
                 linha: UInt = #line) {
        exigir(veio == WAAvisoDoVisualizador(titulo: titulo, apoio: apoio),
               "\(caso): esperado (\"\(titulo)\", \(apoio.map { "\"\($0)\"" } ?? "nil")), veio \(mostra(veio))",
               linha: linha)
    }

    confere(aviso(.indisponivel, fotoDoDiego, operacional),
            "Essa foto não está mais disponível",
            "O celular já apagou o arquivo. Peça para Diego mandar de novo.",
            "foto do Diego indisponível (primeiro nome, não \"Diego Martins\")")
    confere(aviso(.indisponivel, videoDoDiego, operacional),
            "Esse vídeo não está mais disponível",
            "O celular já apagou o arquivo. Peça para Diego mandar de novo.",
            "vídeo do Diego indisponível")
    // individual sem remetenteNome: o nome é o da conversa
    confere(aviso(.indisponivel, fotoDaMarina, marina),
            "Essa foto não está mais disponível",
            "O celular já apagou o arquivo. Peça para Marina mandar de novo.",
            "foto da Marina (individual) indisponível")
    // minha: não faz sentido pedir a mim mesmo
    confere(aviso(.indisponivel, minhaFoto, operacional),
            "Essa foto não está mais disponível", "O celular já apagou o arquivo.",
            "minha foto indisponível (sem \"Peça para…\")")
    confere(aviso(.indisponivel, meuVideo, operacional),
            "Esse vídeo não está mais disponível", "O celular já apagou o arquivo.",
            "meu vídeo indisponível")

    // erro: mesmo layout, sem a segunda frase
    confere(aviso(.naoDeuParaAbrir, fotoDoDiego, operacional),
            "Não deu para abrir a foto agora", nil, "erro na foto")
    confere(aviso(.naoDeuParaAbrir, videoDoDiego, operacional),
            "Não deu para abrir o vídeo agora", nil, "erro no vídeo")

    // carregando, foto e vídeo não têm aviso
    let url = URL(fileURLWithPath: "/tmp/knobler-wa/g1.jpg")
    exigir(aviso(.carregando, fotoDoDiego, operacional) == nil, "carregando não mostra aviso")
    exigir(aviso(.foto(url), fotoDoDiego, operacional) == nil, "foto carregada não mostra aviso")
    exigir(aviso(.video(url), videoDoDiego, operacional) == nil, "vídeo carregado não mostra aviso")

    // topo: quem mandou
    igual(WAVisualizador.remetente(mensagem: fotoDoDiego, conversa: operacional), "Diego Martins",
          "remetente no grupo")
    igual(WAVisualizador.remetente(mensagem: minhaFoto, conversa: operacional), "Você", "remetente: minha")
    igual(WAVisualizador.remetente(mensagem: fotoDaMarina, conversa: marina), "Marina Costa",
          "remetente na individual (nome da conversa)")

    // legenda: o texto da mensagem, só se houver
    igual(WAVisualizador.legenda(fotoDoDiego), "Set montado pra gravação de amanhã", "legenda com texto")
    igual(WAVisualizador.legenda(videoDoDiego), nil, "sem texto, sem legenda")
    igual(WAVisualizador.legenda(msg("s1", de: X, tipo: .imagem, texto: "  \n ", midia: midia("image/jpeg"))),
          nil, "legenda só de espaços não aparece")

    // subtítulo: "<conversa> · <quando>", por dia de calendário (não blocos de 24 h)
    func sub(_ t: Int, agora a: Date = agora) -> String {
        WAVisualizador.subtitulo(conversa: "Operacional ZOI", ts: t, agora: a, calendario: cal)
    }
    igual(sub(ts(dia: 10, hora: 14, minuto: 41)), "Operacional ZOI · hoje, 14:41", "subtítulo hoje")
    igual(sub(ts(dia: 10, hora: 0, minuto: 5)), "Operacional ZOI · hoje, 00:05", "subtítulo hoje de madrugada")
    igual(sub(ts(dia: 9, hora: 9, minuto: 40)), "Operacional ZOI · ontem, 09:40", "subtítulo ontem")
    igual(sub(ts(dia: 9, hora: 23, minuto: 55), agora: data(dia: 10, hora: 0, minuto: 30)),
          "Operacional ZOI · ontem, 23:55", "35 min atrás, mas noutro dia: ontem")
    igual(sub(ts(dia: 7, hora: 10)), "Operacional ZOI · 7 de nov., 10:00", "subtítulo 3 dias atrás: data curta")
    igual(sub(ts(mes: 10, dia: 2, hora: 18, minuto: 5)), "Operacional ZOI · 2 de out., 18:05",
          "subtítulo de outubro (mockup)")
}

// MARK: - 4. o estado no NotchViewModel

@MainActor
private func estadoNoViewModel() {
    let a = NotchViewModel(), b = NotchViewModel()
    for vm in [a, b] {
        vm.setExpandedDirect(true)
        vm.whatsappConversaAberta = kG.texto
    }
    exigir(a.whatsappVisualizando == nil, "o visualizador nasce fechado")

    // abrir preenche na hora (não espera o arquivo), só nesta tela
    a.verMidiaWhatsApp(chave: kG.texto, mensagemID: "g1")
    exigir(a.whatsappVisualizando == WhatsAppVisto(chave: kG.texto, mensagemID: "g1"),
           "clicar na foto não abriu o visualizador: \(String(describing: a.whatsappVisualizando))")
    exigir(b.whatsappVisualizando == nil, "abrir numa tela abriu o visualizador na outra")

    // abrir outra mídia troca o que se vê
    a.verMidiaWhatsApp(chave: kG.texto, mensagemID: "g2")
    exigir(a.whatsappVisualizando?.mensagemID == "g2", "clicar noutra mídia não trocou o visualizador")

    // X
    a.fecharVisualizadorWhatsApp()
    exigir(a.whatsappVisualizando == nil, "o X não fechou o visualizador")

    // reatribuir a MESMA conversa (a seção adota a padrão) não fecha
    a.verMidiaWhatsApp(chave: kG.texto, mensagemID: "g1")
    a.whatsappConversaAberta = kG.texto
    exigir(a.whatsappVisualizando != nil, "reatribuir a mesma conversa fechou o visualizador")

    // trocar de conversa fecha
    b.verMidiaWhatsApp(chave: kG.texto, mensagemID: "g1")
    a.whatsappConversaAberta = kX.texto
    exigir(a.whatsappVisualizando == nil,
           "trocar de conversa não fechou o visualizador: \(String(describing: a.whatsappVisualizando))")
    exigir(b.whatsappVisualizando != nil, "trocar de conversa numa tela fechou o visualizador da outra")

    // abrir outra conversa pelo card também é trocar de conversa
    a.whatsappConversaAberta = kG.texto
    a.verMidiaWhatsApp(chave: kG.texto, mensagemID: "g1")
    a.abrirWhatsApp(chave: kX.texto, conta: A)
    exigir(a.whatsappVisualizando == nil, "abrir outra conversa pelo card não fechou o visualizador")

    // fechar o notch fecha
    a.verMidiaWhatsApp(chave: kX.texto, mensagemID: "x1")
    a.setExpandedDirect(false)
    exigir(a.whatsappVisualizando == nil, "fechar o notch não fechou o visualizador")
    exigir(b.whatsappVisualizando != nil, "fechar o notch numa tela fechou o visualizador da outra")
}

// MARK: - main

@main
enum Gate {
    @MainActor
    static func main() async {
        // hermético: nada do histórico real entra nem sai
        NotificationHistory.shared.arquivo = nil
        acaoDoClique()
        estadoDoVisualizador()
        textos()
        estadoNoViewModel()
        print("whatsappvisualizadorcheck ok")
    }
}
