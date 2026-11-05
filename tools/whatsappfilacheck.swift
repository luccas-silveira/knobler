// Gate da etapa 10 do WhatsApp: a fila de notificação com o campo do WhatsApp
// em uso — precedência do modo, teclado no card, tamanho do card de chegada,
// supressão da conversa aberta naquela tela, junção por conversa sem apagar o
// histórico, prazo de 20 s e o `abrirWhatsApp(chave:conta:)`.
//
//   ver a linha `swift_teste tools/whatsappfilacheck.swift $VM_FONTES` em
//   tools/check.sh (mesmas fontes do eventoscheck).
//
// O histórico persiste em disco: `arquivo = nil` antes de qualquer card, senão
// o card falso iria parar no notificationHistory.json do usuário.
// Duas telas = dois `NotchViewModel`, como o AppDelegate faz por monitor.
// Os temporizadores do VM são `asyncAfter` na main: o fim do prazo é conferido
// rodando o `RunLoop.main` (≈23 s no total, numa linha do tempo só).

import AppKit

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappfilacheck.swift:\(linha))")
        exit(1)
    }
}

private func esperar(_ segundos: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(segundos))
}

/// Roda a main até `pronto` ou até `limite` (instante absoluto). O `asyncAfter`
/// tem folga de disparo (o sistema junta temporizadores), então prazo longo
/// se confere com teto, não com instante exato.
private func esperarAte(_ limite: Date, _ pronto: () -> Bool) {
    while !pronto() && Date() < limite {
        RunLoop.main.run(until: min(limite, Date().addingTimeInterval(0.05)))
    }
}

private let conta4143 = "554791744143"
private let conversaX = "554791744143|5547@s.whatsapp.net"
private let conversaY = "554791744143|5548@s.whatsapp.net"

private func cartao(_ chave: String = conversaX, conta: String = conta4143,
                    miniatura: Bool = false, texto: String = "oi") -> NotchNotification {
    let jid = String(chave.split(separator: "|").last ?? "")
    return NotchNotification(
        appName: "WhatsApp", title: "Fulano", body: texto, subtitle: "4143",
        whatsapp: CartaoWhatsApp(chave: chave, conta: conta, jid: jid, rotuloDaConta: "4143",
                                 grupo: nil, contagem: 1, temMiniatura: miniatura,
                                 mensagemID: UUID().uuidString))
}

private func comum(_ titulo: String = "Mail", webhookID: String? = nil) -> NotchNotification {
    NotchNotification(appName: "Mail", title: titulo, body: "corpo", webhookID: webhookID)
}

private func noHistorico(_ id: UUID) -> Int {
    NotificationHistory.shared.items.filter { $0.id == id }.count
}

/// Card aberto nesta tela, na seção do WhatsApp.
private func abrirNaSecao(_ vm: NotchViewModel) {
    vm.setExpandedDirect(true)
    vm.secoes = [.whatsapp, .musica]
    vm.focar(.whatsapp)
}

/// Fecha o card ativo e espera o respiro de 0,35 s antes do próximo da fila.
private func dispensar(_ vm: NotchViewModel) {
    vm.dismissActiveNotification()
    esperar(0.5)
}

@main
enum WhatsAppFilaCheck {
    @MainActor static func main() {
        // hermético: nada do histórico real entra nem sai
        NotificationHistory.shared.arquivo = nil
        NotificationHistory.shared.limpar()
        UserDefaults.standard.set(NotchSectionOrder.padrao.map(\.rawValue), forKey: "notchSectionOrder")
        UserDefaults.standard.set([String](), forKey: "notchSectionsFixadas")

        testPrecedencia()
        testTecladoNoCard()
        testTamanhoDoCard()
        testTamanhoDecididoPeloVM()
        testDuasTelasUmaLinha()
        testSupressaoDaConversaAberta()
        testJuncaoPorConversa()
        testWebhookSegueSubstituindo()
        testCampoEmUsoNaSecao()
        testAbrirWhatsApp()
        testFecharZeraEdicao()
        testCodableSemWhatsApp()
        testPrazos()
        print("whatsappfilacheck ok")
    }

    // MARK: - precedência (puro)

    static func estado(_ monta: (inout NotchContentState) -> Void) -> NotchContentState {
        var s = NotchContentState()
        monta(&s)
        return s
    }

    static func testPrecedencia() {
        exigir(estado { $0.editingWhatsApp = true; $0.dictation = true }.mode == .music,
               "ditado tomou o lugar do campo do WhatsApp")
        exigir(estado { $0.editingWhatsApp = true; $0.notification = true }.mode == .music,
               "card comum tomou o lugar do campo do WhatsApp")
        exigir(estado { $0.editingWhatsApp = true; $0.notification = true; $0.whatsappCard = true }.mode
               == .notification, "campo em uso no card de chegada não manteve o card")
        exigir(estado { $0.editingWhatsApp = true; $0.question = true }.mode == .question,
               "pergunta não venceu o campo do WhatsApp")
        exigir(estado { $0.editingWhatsApp = true; $0.incoming = true }.mode == .message,
               "card da LAN não venceu o campo do WhatsApp")
        exigir(estado { $0.editingWhatsApp = true; $0.expanded = true; $0.focus = .whatsapp }.mode == .music,
               "campo em uso na seção não ficou na seção")
        // sem o campo, tudo como antes
        exigir(estado { $0.dictation = true; $0.notification = true }.mode == .dictation,
               "sem o campo, o ditado deixou de vencer o card")
        exigir(estado { $0.dictation = true; $0.notification = true; $0.whatsappCard = true }.mode
               == .dictation, "sem o campo, o card do WhatsApp venceu o ditado")
        exigir(estado { $0.dictation = true; $0.expanded = true; $0.focus = .whatsapp }.mode == .dictation,
               "sem o campo, o ditado deixou de vencer o card aberto")
        exigir(estado { $0.notification = true; $0.whatsappCard = true }.mode == .notification,
               "card do WhatsApp sozinho não é .notification")
    }

    static func testTecladoNoCard() {
        exigir(estado { $0.notification = true; $0.whatsappCard = true }.keyboard,
               "card do WhatsApp sem teclado: não dá pra responder")
        exigir(!estado { $0.notification = true }.keyboard, "card comum ganhou teclado")
    }

    // MARK: - tamanho do card de chegada (puro)

    static func medida(whatsapp: Bool, miniatura: Bool, notch: CGFloat = 32) -> CGSize {
        var l = NotchPresentation.Layout()
        l.notch = CGSize(width: 200, height: notch)
        l.realNotch = true
        l.notificationWhatsApp = whatsapp
        l.notificationMiniatura = miniatura
        return NotchPresentation(content: estado { $0.notification = true; $0.whatsappCard = whatsapp },
                                 layout: l).size
    }

    static func testTamanhoDoCard() {
        exigir(medida(whatsapp: true, miniatura: false) == CGSize(width: 360, height: 32 + 96),
               "card do WhatsApp: \(medida(whatsapp: true, miniatura: false))")
        exigir(medida(whatsapp: true, miniatura: true) == CGSize(width: 360, height: 32 + 96 + 126),
               "card do WhatsApp com miniatura: \(medida(whatsapp: true, miniatura: true))")
        exigir(medida(whatsapp: true, miniatura: false, notch: 38) == CGSize(width: 360, height: 38 + 96),
               "card do WhatsApp não soma o topInset")
        exigir(medida(whatsapp: false, miniatura: false) == CGSize(width: 380, height: 32 + 56),
               "notificação comum mudou: \(medida(whatsapp: false, miniatura: false))")
    }

    static func medidaPeloVM(_ vm: NotchViewModel) -> (NotchPresentation.Layout, CGSize) {
        // começa ligado: a função tem que desligar, não só ligar
        var l = NotchPresentation.Layout()
        l.notch = CGSize(width: 200, height: 32)
        l.realNotch = true
        l.notificationWhatsApp = true
        l.notificationMiniatura = true
        vm.aplicarCartaoWhatsApp(em: &l)
        return (l, NotchPresentation(content: vm.contentState(), layout: l).size)
    }

    static func testTamanhoDecididoPeloVM() {
        let semMini = NotchViewModel()
        semMini.enqueue(cartao(miniatura: false))
        let (l1, s1) = medidaPeloVM(semMini)
        exigir(l1.notificationWhatsApp && !l1.notificationMiniatura, "VM: layout do card sem miniatura")
        exigir(s1 == CGSize(width: 360, height: 128), "VM: card sem miniatura mede \(s1)")

        let comMini = NotchViewModel()
        comMini.enqueue(cartao(miniatura: true))
        let (l2, s2) = medidaPeloVM(comMini)
        exigir(l2.notificationWhatsApp && l2.notificationMiniatura, "VM: layout do card com miniatura")
        exigir(s2 == CGSize(width: 360, height: 254), "VM: card com miniatura mede \(s2)")

        let comumAtiva = NotchViewModel()
        comumAtiva.enqueue(comum())
        let (l3, s3) = medidaPeloVM(comumAtiva)
        exigir(!l3.notificationWhatsApp && !l3.notificationMiniatura, "VM: notificação comum virou card do WhatsApp")
        exigir(s3 == CGSize(width: 380, height: 88), "VM: notificação comum mede \(s3)")

        let vazio = NotchViewModel()
        let (l4, _) = medidaPeloVM(vazio)
        exigir(!l4.notificationWhatsApp && !l4.notificationMiniatura, "VM: sem notificação, layout do WhatsApp ligado")
    }

    // MARK: - duas telas

    static func testDuasTelasUmaLinha() {
        let a = NotchViewModel(), b = NotchViewModel()
        let antes = NotificationHistory.shared.items.count
        let c = cartao()
        a.enqueue(c)
        b.enqueue(c)
        exigir(a.activeNotification?.id == c.id, "card não apareceu na tela A")
        exigir(b.activeNotification?.id == c.id, "card não apareceu na tela B")
        exigir(a.activeNotification?.whatsapp?.chave == conversaX, "card perdeu a chave da conversa")
        exigir(noHistorico(c.id) == 1, "histórico com \(noHistorico(c.id)) linhas do mesmo card")
        exigir(NotificationHistory.shared.items.count == antes + 1, "histórico ganhou mais de uma linha")
    }

    static func testSupressaoDaConversaAberta() {
        let a = NotchViewModel(), b = NotchViewModel()
        abrirNaSecao(a)
        a.whatsappConversaAberta = conversaX
        exigir(a.expanded && a.focus == .whatsapp, "montagem: tela A não ficou na seção do WhatsApp")
        let c = cartao(texto: "mensagem na conversa aberta")
        a.enqueue(c)
        b.enqueue(c)
        exigir(a.activeNotification == nil, "card da conversa aberta apareceu na própria tela")
        exigir(b.activeNotification?.id == c.id, "card da conversa aberta em A sumiu da tela B")
        exigir(noHistorico(c.id) == 1, "card suprimido não foi para o histórico")

        // card de outra conversa aparece em A
        let outro = cartao(conversaY, texto: "outra conversa")
        a.enqueue(outro)
        exigir(a.activeNotification?.id == outro.id, "card de outra conversa não apareceu em A")

        // suprimido é descartado, não guardado: fechar o card não o ressuscita
        dispensar(a)
        a.setExpandedDirect(false)
        esperar(0.5)
        exigir(a.activeNotification?.id != c.id, "card suprimido ficou na fila e apareceu depois")

        // mesma conversa aberta, card fechado: aparece
        let fechado = NotchViewModel()
        fechado.secoes = [.whatsapp, .musica]
        fechado.focar(.whatsapp)
        fechado.whatsappConversaAberta = conversaX
        exigir(!fechado.expanded, "montagem: card deveria estar fechado")
        let c2 = cartao(texto: "com o card fechado")
        fechado.enqueue(c2)
        exigir(fechado.activeNotification?.id == c2.id, "card fechado suprimiu a notificação")

        // card aberto em outra seção, mesma conversa guardada: aparece
        let outraSecao = NotchViewModel()
        outraSecao.setExpandedDirect(true)
        outraSecao.secoes = [.whatsapp, .musica]
        outraSecao.focar(.musica)
        outraSecao.whatsappConversaAberta = conversaX
        let c3 = cartao(texto: "card aberto na música")
        outraSecao.enqueue(c3)
        exigir(outraSecao.activeNotification?.id == c3.id, "foco fora do WhatsApp suprimiu a notificação")
    }

    // MARK: - junção por conversa

    static func testJuncaoPorConversa() {
        // ativo: o segundo substitui o primeiro
        let vm = NotchViewModel()
        let m1 = cartao(texto: "primeira"), m2 = cartao(texto: "segunda")
        exigir(m1.id != m2.id && m1.webhookID == nil && m2.webhookID == nil, "montagem: ids/webhookID")
        vm.enqueue(m1)
        vm.enqueue(m2)
        exigir(vm.activeNotification?.id == m2.id, "segunda mensagem não substituiu o card ativo")
        exigir(noHistorico(m1.id) == 1 && noHistorico(m2.id) == 1,
               "histórico perdeu uma das mensagens da conversa")
        dispensar(vm)
        exigir(vm.activeNotification == nil, "mensagem da mesma conversa empilhou atrás do card ativo")

        // outra conversa não substitui: entra na fila
        let o1 = cartao(conversaY, texto: "outra")
        vm.enqueue(m1)
        vm.enqueue(o1)
        exigir(vm.activeNotification?.id == m1.id, "card de outra conversa substituiu o ativo")
        dispensar(vm)
        exigir(vm.activeNotification?.id == o1.id, "card de outra conversa não ficou na fila")
        dispensar(vm)
        exigir(vm.activeNotification == nil, "fila com sobra")

        // na fila: substitui no lugar, sem empilhar e sem passar outra conversa
        let fila = NotchViewModel()
        let n = comum("na frente")
        let q1 = cartao(texto: "q1"), qy = cartao(conversaY, texto: "qy"), q2 = cartao(texto: "q2")
        fila.enqueue(n)
        fila.enqueue(q1)
        fila.enqueue(qy)
        fila.enqueue(q2)
        exigir(fila.activeNotification?.id == n.id, "card na fila tomou o lugar do ativo")
        dispensar(fila)
        exigir(fila.activeNotification?.id == q2.id, "na fila, a segunda mensagem não substituiu a primeira no lugar")
        dispensar(fila)
        exigir(fila.activeNotification?.id == qy.id, "card de outra conversa sumiu ou foi substituído na fila")
        dispensar(fila)
        exigir(fila.activeNotification == nil, "mensagem da mesma conversa empilhou na fila")
        for m in [q1, qy, q2] {
            exigir(noHistorico(m.id) == 1, "histórico sem a mensagem \(m.body)")
        }
    }

    static func testWebhookSegueSubstituindo() {
        let vm = NotchViewModel()
        let w1 = comum("progresso 1", webhookID: "deploy"), w2 = comum("progresso 2", webhookID: "deploy")
        vm.enqueue(w1)
        vm.enqueue(w2)
        exigir(vm.activeNotification?.id == w2.id, "webhook: não substituiu o card")
        exigir(noHistorico(w1.id) == 0 && noHistorico(w2.id) == 1, "webhook: histórico deixou de substituir a linha")
        dispensar(vm)
        exigir(vm.activeNotification == nil, "webhook: empilhou")
    }

    // MARK: - campo em uso

    static func testCampoEmUsoNaSecao() {
        let vm = NotchViewModel()
        abrirNaSecao(vm)
        vm.atualizarEdicaoWhatsApp(true)
        exigir(vm.whatsappEditando, "atualizarEdicaoWhatsApp(true) não marcou edição")
        let n = comum("enquanto digita"), w = cartao(conversaY, texto: "enquanto digita")
        vm.enqueue(n)
        vm.enqueue(w)
        exigir(vm.activeNotification == nil, "notificação apareceu com o campo do WhatsApp em uso")
        exigir(vm.contentState().editingWhatsApp, "contentState sem editingWhatsApp")
        exigir(vm.mode == .music, "campo em uso na seção: modo \(vm.mode)")
        exigir(noHistorico(n.id) == 1 && noHistorico(w.id) == 1, "fila sem histórico")
        vm.atualizarEdicaoWhatsApp(false)
        exigir(vm.activeNotification?.id == n.id, "soltar o campo não soltou o primeiro da fila")
        exigir(!vm.contentState().editingWhatsApp, "campo solto e editingWhatsApp ainda ligado")
    }

    // MARK: - abrirWhatsApp

    static func testAbrirWhatsApp() {
        // card fechado, card de chegada daquela conversa ativo
        let vm = NotchViewModel()
        let c = cartao()
        vm.enqueue(c)
        vm.abrirWhatsApp(chave: conversaX, conta: conta4143)
        exigir(vm.activeNotification == nil, "abrirWhatsApp não dispensou o card daquela conversa")
        exigir(vm.whatsappContaSelecionada == conta4143, "conta não selecionada")
        exigir(vm.whatsappConversaAberta == conversaX, "conversa não aberta")
        exigir(vm.expanded, "abrirWhatsApp não abriu o card")
        exigir(vm.focus == .whatsapp || vm.focoPendente == .whatsapp, "foco não pedido em .whatsapp")

        // card já aberto em outra seção: o foco vai direto
        let aberto = NotchViewModel()
        aberto.setExpandedDirect(true)
        aberto.secoes = [.musica, .whatsapp]
        aberto.focar(.musica)
        aberto.abrirWhatsApp(chave: conversaY, conta: conta4143)
        exigir(aberto.focus == .whatsapp, "card aberto: foco ficou em \(String(describing: aberto.focus))")
        exigir(aberto.whatsappConversaAberta == conversaY, "card aberto: conversa não aberta")

        // card de chegada de outra conversa fica
        let outra = NotchViewModel()
        let y = cartao(conversaY)
        outra.enqueue(y)
        outra.abrirWhatsApp(chave: conversaX, conta: conta4143)
        exigir(outra.activeNotification?.id == y.id, "abrirWhatsApp dispensou card de outra conversa")
    }

    static func testFecharZeraEdicao() {
        let vm = NotchViewModel()
        abrirNaSecao(vm)
        vm.whatsappConversaAberta = conversaX
        vm.atualizarEdicaoWhatsApp(true)
        vm.setExpandedDirect(false)
        exigir(!vm.whatsappEditando, "fechar o card não zerou whatsappEditando")
        exigir(vm.whatsappConversaAberta == conversaX, "fechar o card esqueceu a conversa aberta")
        exigir(!vm.contentState().editingWhatsApp, "card fechado e editingWhatsApp ligado")
    }

    // MARK: - histórico em disco

    static func testCodableSemWhatsApp() {
        let n = cartao(miniatura: true, texto: "vai pro disco")
        guard let data = try? JSONEncoder().encode(n) else { return exigir(false, "encode falhou") }
        let json = String(decoding: data, as: UTF8.self)
        exigir(!json.contains("5547@s.whatsapp.net") && !json.contains("whatsapp"),
               "cartão do WhatsApp foi para o JSON do histórico: \(json)")
        guard let d = try? JSONDecoder().decode(NotchNotification.self, from: data) else {
            return exigir(false, "decode falhou")
        }
        exigir(d.whatsapp == nil, "decode trouxe whatsapp de volta")
        var esperado = n
        esperado.whatsapp = nil
        exigir(d == esperado, "decode mudou o resto da notificação")
        exigir(d.id == n.id && d.body == n.body && d.subtitle == n.subtitle && d.date == n.date,
               "decode perdeu id/corpo/subtítulo/data")
    }

    // MARK: - prazos (linha do tempo única, ≈23 s)

    static func testPrazos() {
        exigir(NotchViewModel.whatsappDuracao == 20, "whatsappDuracao = \(NotchViewModel.whatsappDuracao)")

        let curto = NotchViewModel()
        let n = comum("5 s")
        curto.enqueue(n)

        let longo = NotchViewModel()
        let w = cartao(texto: "20 s")
        longo.enqueue(w)

        // campo em uso no próprio card de chegada: segura o card e a fila
        let preso = NotchViewModel()
        let wp = cartao(texto: "respondendo"), np = comum("atrás do card")
        preso.enqueue(wp)
        preso.atualizarEdicaoWhatsApp(true)
        preso.enqueue(np)
        exigir(preso.activeNotification?.id == wp.id, "notificação comum tirou o card em resposta")
        exigir(preso.contentState().whatsappCard, "contentState sem whatsappCard")
        exigir(preso.contentState().editingWhatsApp, "campo no card não conta como edição")
        exigir(preso.mode == .notification, "campo em uso no card: modo \(preso.mode)")
        var l = NotchPresentation.Layout()
        preso.aplicarCartaoWhatsApp(em: &l)
        exigir(NotchPresentation(content: preso.contentState(), layout: l).keyboard,
               "card em resposta sem teclado")

        // soltou o campo: o prazo volta a correr
        let solto = NotchViewModel()
        let ws = cartao(texto: "respondeu e largou"), ns = comum("atrás do card solto")
        solto.enqueue(ws)
        solto.atualizarEdicaoWhatsApp(true)
        solto.enqueue(ns)
        solto.atualizarEdicaoWhatsApp(false)
        exigir(solto.activeNotification?.id == ws.id, "soltar o campo derrubou o card na hora")

        let t0 = Date()
        esperarAte(t0.addingTimeInterval(7)) { curto.activeNotification == nil }
        exigir(curto.activeNotification == nil, "notificação comum não sumiu em 5 s")
        exigir(longo.activeNotification?.id == w.id, "card do WhatsApp sumiu antes de 20 s")
        exigir(preso.activeNotification?.id == wp.id, "card em resposta sumiu sozinho")
        exigir(solto.activeNotification?.id == ws.id, "card solto sumiu antes de 20 s")

        // ainda em pé perto do fim do prazo (pega prazo de 10 ou 15 s)
        esperarAte(t0.addingTimeInterval(19)) { false }
        exigir(longo.activeNotification?.id == w.id, "card do WhatsApp sumiu antes de 20 s")
        exigir(solto.activeNotification?.id == ws.id, "card solto sumiu antes de 20 s")

        esperarAte(t0.addingTimeInterval(24)) {
            longo.activeNotification == nil && solto.activeNotification?.id == ns.id
        }
        exigir(longo.activeNotification == nil, "card do WhatsApp não sumiu em 20 s")
        // o prazo velho do card preso, se não foi cancelado, cai junto com o do
        // `longo`; a folga do disparo pede mais uns segundos de margem
        esperarAte(t0.addingTimeInterval(23)) { preso.activeNotification?.id != wp.id }
        exigir(preso.activeNotification?.id == wp.id, "card sumiu sozinho com o campo em uso (prazo não cancelado)")
        exigir(solto.activeNotification?.id != ws.id, "soltar o campo não religou o prazo do card")
        exigir(solto.activeNotification?.id == ns.id, "notificação na fila atrás do card não apareceu")
    }
}
