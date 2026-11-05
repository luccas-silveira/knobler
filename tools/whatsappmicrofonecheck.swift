// Gate da etapa 14 do WhatsApp: o silêncio por microfone desconta o uso do
// próprio Knobler (ditado e gravação de áudio no notch). Gravar um áudio de
// 40 s não pode calar os cards, mas uma chamada de verdade que continuou depois
// da gravação volta a silenciar passado o limiar.
//
// Só as regras puras de Knobler/NotificationRules.swift e o contador de
// Knobler/UsoProprioDoMicrofone.swift; a ligação no MicRecorder e no
// AppDelegate é o whatsappmicrofoneligacaocheck.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/NotificationRules.swift Knobler/UsoProprioDoMicrofone.swift \
//     tools/whatsappmicrofonecheck.swift \
//     -o /tmp/whatsappmicrofonecheck && /tmp/whatsappmicrofonecheck

import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappmicrofonecheck.swift:\(linha))")
        exit(1)
    }
}

@main
enum WhatsAppMicrofoneCheck {
    static func main() {
        testComoAntes()
        testProprioAtivo()
        testProprioTerminou()
        testUsoProprio()
        testUsoProprioConcorrente()
        print("whatsappmicrofonecheck ok")
    }

    private static let agora = Date(timeIntervalSince1970: 3_000_000)
    private static func ha(_ s: TimeInterval) -> Date { agora.addingTimeInterval(-s) }

    // MARK: - sem os parâmetros novos, como antes

    static func testComoAntes() {
        func chamada(_ desde: Date?) -> Bool {
            NotificationRules.micIndicaChamada(desde: desde, agora: agora)
        }
        exigir(!chamada(nil), "microfone apagado não é chamada")
        exigir(!chamada(ha(19)), "mic aceso há 19 s não é chamada")
        exigir(chamada(ha(20)), "mic aceso há 20 s é chamada")
        exigir(chamada(ha(600)), "mic aceso há 10 min é chamada")

        // os parâmetros novos nos valores padrão dão o mesmo resultado
        func explicita(_ desde: Date?) -> Bool {
            NotificationRules.micIndicaChamada(
                desde: desde, agora: agora, proprioAtivo: false, proprioTerminouEm: nil)
        }
        exigir(!explicita(ha(19)), "proprioAtivo false, sem fim de uso: 19 s não é chamada")
        exigir(explicita(ha(20)), "proprioAtivo false, sem fim de uso: 20 s é chamada")
        exigir(!explicita(nil), "proprioAtivo false, mic apagado não é chamada")
    }

    // MARK: - gravando agora: nunca é chamada

    static func testProprioAtivo() {
        func chamada(_ desde: Date?, limiar: TimeInterval = 20) -> Bool {
            NotificationRules.micIndicaChamada(
                desde: desde, agora: agora, limiar: limiar, proprioAtivo: true)
        }
        exigir(!chamada(ha(40)), "gravando um áudio de 40 s: não é chamada (os cards seguem descendo)")
        exigir(!chamada(ha(20)), "gravando, mic aceso há 20 s: não é chamada")
        exigir(!chamada(ha(3600)), "gravando, mic aceso há 1 h: não é chamada")
        exigir(!chamada(ha(0)), "gravando, mic acabou de acender: não é chamada")
        exigir(!chamada(nil), "gravando, mic apagado: não é chamada")
        exigir(!chamada(ha(40), limiar: 1), "gravando com limiar de 1 s: não é chamada")
        // gravando com um fim de uso antigo gravado também não
        exigir(!NotificationRules.micIndicaChamada(
                    desde: ha(120), agora: agora, proprioAtivo: true, proprioTerminouEm: ha(90)),
               "gravando de novo (fim anterior há 90 s, mic há 120 s): não é chamada")
    }

    // MARK: - o uso próprio terminou: conta a partir do fim

    static func testProprioTerminou() {
        func chamada(_ desde: Date?, terminou: Date?, limiar: TimeInterval = 20) -> Bool {
            NotificationRules.micIndicaChamada(
                desde: desde, agora: agora, limiar: limiar,
                proprioAtivo: false, proprioTerminouEm: terminou)
        }
        exigir(!chamada(ha(60), terminou: ha(5)),
               "mic aceso há 60 s, gravação terminou há 5 s: não é chamada")
        exigir(chamada(ha(60), terminou: ha(25)),
               "mic aceso há 60 s, gravação terminou há 25 s: é chamada (a call continuou)")
        exigir(!chamada(ha(60), terminou: ha(19)),
               "mic aceso há 60 s, gravação terminou há 19 s: não é chamada")
        exigir(chamada(ha(60), terminou: ha(20)),
               "mic aceso há 60 s, gravação terminou há 20 s: é chamada (no limiar)")

        // o fim do uso próprio é anterior ao mic acender: vale o `desde`
        exigir(!chamada(ha(10), terminou: ha(100)),
               "gravação terminou há 100 s e o mic acendeu há 10 s: não é chamada (conta do mais recente)")
        exigir(chamada(ha(30), terminou: ha(100)),
               "gravação terminou há 100 s e o mic acendeu há 30 s: é chamada")

        // mic apagado continua não sendo chamada
        exigir(!chamada(nil, terminou: ha(100)), "mic apagado com fim de uso há 100 s: não é chamada")
        exigir(!chamada(nil, terminou: ha(5)), "mic apagado com fim de uso há 5 s: não é chamada")

        // o limiar passado continua valendo junto do fim de uso
        exigir(!chamada(ha(60), terminou: ha(25), limiar: 30),
               "limiar de 30 s, gravação terminou há 25 s: não é chamada")
        exigir(chamada(ha(60), terminou: ha(25), limiar: 25),
               "limiar de 25 s, gravação terminou há 25 s: é chamada")
    }

    // MARK: - o contador do uso próprio

    static func testUsoProprio() {
        let uso = UsoProprioDoMicrofone.shared
        exigir(!uso.ativo, "nada começou: ativo é false")

        // terminou() sem comecou() não deixa o contador negativo
        uso.terminou()
        uso.terminou()
        exigir(!uso.ativo, "terminou() sem comecou(): ativo segue false")
        uso.comecou()
        exigir(uso.ativo, "comecou() depois de terminou() solto: ativo é true (o contador não ficou negativo)")

        let fim = Date(timeIntervalSince1970: 4_000_000)
        uso.terminou(agora: fim)
        exigir(!uso.ativo, "um comecou() e um terminou(): ativo é false")
        exigir(uso.terminouEm == fim, "terminou(agora:) grava terminouEm (\(String(describing: uso.terminouEm)))")

        // ditado e gravação ao mesmo tempo: só desliga quando os dois acabam
        uso.comecou()
        uso.comecou()
        exigir(uso.ativo, "comecou() duas vezes: ativo é true")
        let primeiro = Date(timeIntervalSince1970: 4_000_100)
        uso.terminou(agora: primeiro)
        exigir(uso.ativo, "comecou() duas vezes e terminou() uma: ativo segue true")
        let segundo = Date(timeIntervalSince1970: 4_000_200)
        uso.terminou(agora: segundo)
        exigir(!uso.ativo, "o segundo terminou(agora:) deixa ativo false")
        exigir(uso.terminouEm == segundo,
               "o segundo terminou(agora:) grava terminouEm = o fim do último uso (\(String(describing: uso.terminouEm)))")

        // de novo terminou() solto depois de tudo terminar: não fica negativo
        uso.terminou()
        uso.terminou()
        uso.comecou()
        exigir(uso.ativo, "comecou() depois de dois terminou() soltos: ativo é true")
        uso.terminou()
        exigir(!uso.ativo, "e o terminou() correspondente deixa ativo false")
        exigir(uso.terminouEm != nil, "terminou() com a data padrão grava terminouEm")
    }

    /// O gravador pode ser parado fora da main: o contador não perde passos
    /// com chamadas de várias threads.
    static func testUsoProprioConcorrente() {
        let uso = UsoProprioDoMicrofone.shared
        exigir(!uso.ativo, "antes do teste concorrente: ativo é false")
        let n = 5000
        DispatchQueue.concurrentPerform(iterations: n) { _ in uso.comecou() }
        exigir(uso.ativo, "\(n) comecou() concorrentes: ativo é true")
        DispatchQueue.concurrentPerform(iterations: n - 1) { _ in uso.terminou() }
        exigir(uso.ativo, "\(n) comecou() e \(n - 1) terminou() concorrentes: ativo segue true")
        uso.terminou()
        exigir(!uso.ativo, "\(n) comecou() e \(n) terminou(): ativo é false")
    }
}
