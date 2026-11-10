// Gate do preview nítido no card de chegada do WhatsApp (mockup
// docs/vesta/mockups/2026-11-10-whatsapp-cartao-nitido/index.html). Modelo
// puro `WACartaoMidia` em Knobler/WhatsApp/WhatsAppCartaoMidia.swift (arquivo
// próprio: usa `WAResultadoMidia`, do WhatsAppMidia.swift, e o
// whatsappcartaocheck compila o WhatsAppCartao.swift sem ele), os campos
// novos do `CartaoWhatsApp` e a altura do card no layout.
//
//   ver a linha `swift_teste tools/whatsappcartaomidiacheck.swift $VM_FONTES
//   $WA_NUCLEO Knobler/WhatsApp/WhatsAppCartao.swift
//   Knobler/WhatsApp/WhatsAppCartaoMidia.swift` em tools/check.sh.
//
// O que se prova (o que quem usa vê):
//   - o quadro da mídia segue a proporção da imagem na largura do card, entre
//     120 e 200 pt; proporção inválida cai em 120;
//   - só foto baixa o arquivo inteiro; vídeo fica na miniatura;
//   - a etiqueta de duração do vídeo sai em m:ss, e some sem duração;
//   - só `.aguardando` tenta de novo; indisponível, conta desconectada e falha
//     ficam na miniatura;
//   - o card sabe se a mídia é vídeo e quanto dura;
//   - o card no notch cresce com o quadro (foto em pé > foto deitada), sem
//     passar de 200 pt de quadro, e não herda a medida de outra mensagem.
//
// Tudo em memória: nenhuma rede. O histórico real não é tocado.

import AppKit

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappcartaomidiacheck.swift:\(linha))")
        exit(1)
    }
}

private func perto(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.5) -> Bool { abs(a - b) <= tol }

// MARK: - 1. altura do quadro

private func altura() {
    func h(_ proporcao: CGFloat, _ largura: CGFloat = 312) -> CGFloat {
        WACartaoMidia.altura(larguraDisponivel: largura, proporcao: proporcao)
    }
    exigir(h(1.0) == 200, "quadrada em 312 dá 312, clampa em 200; veio \(h(1.0))")
    exigir(perto(h(16.0 / 9.0), 175.5), "16:9 em 312 dá ~175.5; veio \(h(16.0 / 9.0))")
    exigir(h(3.0) == 120, "3:1 em 312 dá 104, clampa em 120; veio \(h(3.0))")
    exigir(h(9.0 / 16.0) == 200, "9:16 (em pé) clampa em 200; veio \(h(9.0 / 16.0))")
    exigir(perto(h(2.0), 156), "2:1 em 312 dá 156 (dentro do intervalo); veio \(h(2.0))")
    // a largura passada conta: não é 312 fixo
    exigir(perto(h(2.0, 280), 140), "2:1 em 280 dá 140; veio \(h(2.0, 280))")
    exigir(perto(h(1.0, 150), 150), "quadrada em 150 dá 150; veio \(h(1.0, 150))")
    // inválidas
    exigir(h(0) == 120, "proporção 0 cai em 120; veio \(h(0))")
    exigir(h(.nan) == 120, "proporção NaN cai em 120; veio \(h(.nan))")
    exigir(h(.infinity) == 120, "proporção infinita cai em 120; veio \(h(.infinity))")
    exigir(h(-1.5) == 120, "proporção negativa cai em 120; veio \(h(-1.5))")
    exigir(h(1.0, 0) == 120, "largura 0 cai em 120; veio \(h(1.0, 0))")
    // nunca fora do intervalo
    for p: CGFloat in [0.1, 0.5, 0.75, 1.2, 1.5, 1.9, 2.4, 2.6, 5, 40] {
        let v = h(p)
        exigir(v >= 120 && v <= 200, "proporção \(p) fora de 120…200: \(v)")
    }
    // mais deitada, mais baixa (dentro do intervalo)
    exigir(h(1.7) > h(2.2), "1.7 tem que dar quadro mais alto que 2.2: \(h(1.7)) vs \(h(2.2))")
}

// MARK: - 2. baixar o arquivo

private func baixaArquivo() {
    exigir(WACartaoMidia.baixaArquivo(tipo: .imagem), "foto baixa o arquivo inteiro")
    let nao: [WATipoMensagem] = [.video, .documento, .figurinha, .audio, .voz, .texto, .outro("enquete")]
    for t in nao {
        exigir(!WACartaoMidia.baixaArquivo(tipo: t), "\(t) não baixa o arquivo no card")
    }
}

// MARK: - 3. duração do vídeo

private func duracao() {
    let casos: [(Int?, String?)] = [
        (42, "0:42"), (65, "1:05"), (720, "12:00"), (5, "0:05"), (59, "0:59"),
        (60, "1:00"), (61, "1:01"), (599, "9:59"),
        (nil, nil), (0, nil), (-3, nil),
    ]
    for (s, esperado) in casos {
        let v = WACartaoMidia.duracao(segundos: s)
        exigir(v == esperado, "duracao(\(String(describing: s))) é \(String(describing: esperado)), veio \(String(describing: v))")
    }
}

// MARK: - 4. tentar de novo

private func tentarDeNovo() {
    let url = URL(fileURLWithPath: "/tmp/foto.jpg")
    exigir(WACartaoMidia.tentarDeNovo(.aguardando), ".aguardando tenta de novo")
    exigir(!WACartaoMidia.tentarDeNovo(.arquivo(url)), ".arquivo já chegou: não tenta de novo")
    exigir(!WACartaoMidia.tentarDeNovo(.indisponivel), ".indisponivel fica na miniatura")
    exigir(!WACartaoMidia.tentarDeNovo(.contaDesconectada), ".contaDesconectada fica na miniatura")
    exigir(!WACartaoMidia.tentarDeNovo(.falhou), ".falhou fica na miniatura")
}

// MARK: - 5. campos do card

private let N4143 = "554791744143"
private let PEDRO = "554799990001@s.whatsapp.net"
private let AGORA = Date(timeIntervalSince1970: 1_762_270_500)
private let T = 1_762_270_500

private func mensagem(id: String = "3EB0A1B2", tipo: WATipoMensagem = .texto, texto: String = "oi",
                      midia: WAMidia? = nil) -> WAMensagem {
    WAMensagem(id: id, conversa: PEDRO, remetente: PEDRO, remetenteNome: nil, deMim: false,
               ts: T - 5, tipo: tipo, texto: texto, midia: midia, citacao: nil, reacoes: [],
               editada: nil, apagada: nil, status: nil)
}

private func midia(_ mime: String, segundos: Int? = nil, miniatura: Bool = true) -> WAMidia {
    WAMidia(mimetype: mime, nome: "arquivo", tamanho: 1234, segundos: segundos,
            miniatura: miniatura, baixada: false)
}

private let PEDRO_CONVERSA = WAConversa(jid: PEDRO, jids: [PEDRO], tipo: .individual, nome: "Pedro Alves",
                                        naoLidas: 1, marcadaNaoLida: false, ts: T - 5, ultima: nil)

private func montar(_ m: WAMensagem) -> NotchNotification {
    WACartao.montar(mensagem: m, conversa: PEDRO_CONVERSA, conta: nil, numero: N4143,
                    contagem: 1, agora: AGORA)
}

private func camposDoCartao() {
    let video = montar(mensagem(tipo: .video, texto: "", midia: midia("video/mp4", segundos: 42))).whatsapp
    exigir(video?.ehVideo == true, "vídeo: ehVideo true")
    exigir(video?.segundosDoVideo == 42, "vídeo de 42 s: segundosDoVideo 42, veio \(String(describing: video?.segundosDoVideo))")
    exigir(video?.temMiniatura == true, "vídeo com miniatura segue com temMiniatura")

    let semDuracao = montar(mensagem(tipo: .video, texto: "", midia: midia("video/mp4", segundos: nil))).whatsapp
    exigir(semDuracao?.ehVideo == true, "vídeo sem duração ainda é vídeo")
    exigir(semDuracao?.segundosDoVideo == nil, "vídeo sem duração: segundosDoVideo nil")

    let longo = montar(mensagem(tipo: .video, texto: "olha", midia: midia("video/mp4", segundos: 720))).whatsapp
    exigir(longo?.segundosDoVideo == 720, "vídeo de 12 min com legenda: 720, veio \(String(describing: longo?.segundosDoVideo))")

    // foto com `segundos` preenchido por engano não vira vídeo nem ganha duração
    let foto = montar(mensagem(tipo: .imagem, texto: "", midia: midia("image/jpeg", segundos: 10))).whatsapp
    exigir(foto?.ehVideo == false, "foto: ehVideo false")
    exigir(foto?.segundosDoVideo == nil, "foto: segundosDoVideo nil, veio \(String(describing: foto?.segundosDoVideo))")
    exigir(foto?.temMiniatura == true, "foto com miniatura segue com temMiniatura")

    let texto = montar(mensagem()).whatsapp
    exigir(texto?.ehVideo == false, "texto: ehVideo false")
    exigir(texto?.segundosDoVideo == nil, "texto: segundosDoVideo nil")

    let voz = montar(mensagem(tipo: .voz, texto: "", midia: midia("audio/ogg", segundos: 30, miniatura: false))).whatsapp
    exigir(voz?.ehVideo == false, "mensagem de voz não é vídeo")
    exigir(voz?.segundosDoVideo == nil, "mensagem de voz de 30 s não ganha etiqueta de vídeo")
}

// MARK: - 6. altura do card no notch

/// O card de 360 pt: 96 de corpo + quadro + 6 de espaço, debaixo do notch.
private let NOTCH: CGFloat = 32
private let CORPO: CGFloat = 96
private let ESPACO: CGFloat = 6

private func medida(_ vm: NotchViewModel) -> (NotchPresentation.Layout, CGSize) {
    var l = NotchPresentation.Layout()
    l.notch = CGSize(width: 200, height: NOTCH)
    l.realNotch = true
    // começa sujo: a função tem que sobrescrever, não só somar
    l.notificationMidiaAltura = 999
    vm.aplicarCartaoWhatsApp(em: &l)
    return (l, NotchPresentation(content: vm.contentState(), layout: l).size)
}

private func medidaPura(miniatura: Bool, quadro: CGFloat) -> CGSize {
    var l = NotchPresentation.Layout()
    l.notch = CGSize(width: 200, height: NOTCH)
    l.realNotch = true
    l.notificationWhatsApp = true
    l.notificationMiniatura = miniatura
    l.notificationMidiaAltura = quadro
    var vm: NotchViewModel? = NotchViewModel()
    vm!.enqueue(montar(mensagem(id: "pura-\(UUID().uuidString)", tipo: .imagem, texto: "",
                                midia: midia("image/jpeg"))))
    let s = NotchPresentation(content: vm!.contentState(), layout: l).size
    vm = nil
    return s
}

private func foto(_ id: String) -> NotchNotification {
    montar(mensagem(id: id, tipo: .imagem, texto: "", midia: midia("image/jpeg")))
}

@MainActor
private func alturaDoCard() {
    let teto = NOTCH + CORPO + 200 + ESPACO
    let base = NOTCH + CORPO + 120 + ESPACO

    // presentation pura: o quadro entra clampado, 0 (ainda não medido) é 120
    exigir(medidaPura(miniatura: true, quadro: 0).height == base,
           "quadro ainda não medido: card de \(base), veio \(medidaPura(miniatura: true, quadro: 0).height)")
    exigir(medidaPura(miniatura: true, quadro: 175.5).height == NOTCH + CORPO + 175.5 + ESPACO,
           "quadro de 175.5: card de \(NOTCH + CORPO + 175.5 + ESPACO), veio \(medidaPura(miniatura: true, quadro: 175.5).height)")
    exigir(medidaPura(miniatura: true, quadro: 500).height == teto,
           "quadro de 500 passa do teto: card de \(teto), veio \(medidaPura(miniatura: true, quadro: 500).height)")
    exigir(medidaPura(miniatura: true, quadro: 40).height == base,
           "quadro de 40 fica no piso: card de \(base), veio \(medidaPura(miniatura: true, quadro: 40).height)")
    exigir(medidaPura(miniatura: false, quadro: 200).height == NOTCH + CORPO,
           "sem miniatura o quadro não conta: \(medidaPura(miniatura: false, quadro: 200).height)")

    // pelo VM, com as alturas do modelo: foto em pé x foto deitada larga
    let emPe = WACartaoMidia.altura(larguraDisponivel: 312, proporcao: 9.0 / 16.0)
    let deitada = WACartaoMidia.altura(larguraDisponivel: 312, proporcao: 16.0 / 9.0)

    let a = NotchViewModel()
    let fa = foto("em-pe")
    a.enqueue(fa)
    let (la0, sa0) = medida(a)
    exigir(la0.notificationMiniatura, "foto com miniatura liga o quadro")
    exigir(sa0.height == base, "foto ainda não medida: card de \(base) (quadro de 120), veio \(sa0.height)")
    var mudou = false
    let obs = a.objectWillChange.sink { _ in mudou = true }
    a.medirMidiaWhatsApp(mensagemID: "em-pe", altura: emPe)
    obs.cancel()
    exigir(mudou, "medirMidiaWhatsApp tem que avisar a NotchView (objectWillChange), senão o card não cresce")
    let (la, sa) = medida(a)
    exigir(la.notificationMidiaAltura == emPe, "layout leva a altura medida: \(la.notificationMidiaAltura)")

    let b = NotchViewModel()
    b.enqueue(foto("deitada"))
    b.medirMidiaWhatsApp(mensagemID: "deitada", altura: deitada)
    let (_, sb) = medida(b)

    exigir(sa.height > sb.height, "foto em pé (\(sa.height)) tem que dar card mais alto que deitada (\(sb.height))")
    exigir(sa.height == teto, "foto em pé: card no teto \(teto), veio \(sa.height)")
    exigir(perto(sb.height, NOTCH + CORPO + 175.5 + ESPACO),
           "foto 16:9: card de \(NOTCH + CORPO + 175.5 + ESPACO), veio \(sb.height)")
    exigir(sa.width == 360 && sb.width == 360, "largura do card não muda: \(sa.width), \(sb.width)")

    // medida absurda não estoura o card
    let c = NotchViewModel()
    c.enqueue(foto("gigante"))
    c.medirMidiaWhatsApp(mensagemID: "gigante", altura: 900)
    exigir(medida(c).1.height == teto, "quadro de 900 medido: card no teto \(teto), veio \(medida(c).1.height)")

    // medida de outra mensagem não vale para o card na tela
    let d = NotchViewModel()
    d.enqueue(foto("atual"))
    d.medirMidiaWhatsApp(mensagemID: "outra", altura: 200)
    exigir(medida(d).1.height == base, "medida de outra mensagem mudou o card: \(medida(d).1.height)")

    // card novo da mesma conversa (substitui o anterior) não herda a medida
    let e = NotchViewModel()
    e.enqueue(foto("primeira"))
    e.medirMidiaWhatsApp(mensagemID: "primeira", altura: 200)
    exigir(medida(e).1.height == teto, "primeira foto medida em 200: \(medida(e).1.height)")
    e.enqueue(foto("segunda"))
    exigir(e.activeNotification?.whatsapp?.mensagemID == "segunda", "o card da mesma conversa foi substituído")
    exigir(medida(e).1.height == base, "card novo herdou a medida da foto anterior: \(medida(e).1.height)")

    // card de texto ignora qualquer medida
    let f = NotchViewModel()
    f.enqueue(montar(mensagem(id: "texto")))
    f.medirMidiaWhatsApp(mensagemID: "texto", altura: 200)
    let (lf, sf) = medida(f)
    exigir(!lf.notificationMiniatura, "texto não liga o quadro")
    exigir(sf.height == NOTCH + CORPO, "card de texto mede \(NOTCH + CORPO), veio \(sf.height)")

    // sem card, o layout zera a medida
    let g = NotchViewModel()
    let (lg, _) = medida(g)
    exigir(lg.notificationMidiaAltura == 0, "sem card, notificationMidiaAltura volta a 0: \(lg.notificationMidiaAltura)")
}

@main
enum Gate {
    @MainActor
    static func main() {
        // hermético: nada do histórico real entra nem sai
        NotificationHistory.shared.arquivo = nil
        altura()
        baixaArquivo()
        duracao()
        tentarDeNovo()
        camposDoCartao()
        alturaDoCard()
        print("whatsappcartaomidiacheck: ok")
    }
}
