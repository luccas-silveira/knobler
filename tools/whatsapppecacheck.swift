// Gate da etapa 12 do WhatsApp: a peça ligada pelo `whatsappEfeitos`.
// Instalar chama o `nascer` uma vez e deixa o serviço vivo; desinstalar chama
// `parar()` uma vez; instalar de novo nasce de novo (uma vez); em instalação
// nova o `subir()` do arranque não chama o `nascer` (a peça nasce
// desinstalada); e quem já instalou ganha o serviço no `subir()` do arranque.
//
// A ligação de verdade (`WhatsAppPeca.ligar()` no `AppDelegate`) só o app
// compila; quem a confere é o `tools/whatsapppecaligacaocheck.sh`.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/Plugin.swift Knobler/Pomodoro.swift Knobler/Reminders.swift \
//     Knobler/Descanso.swift Knobler/NotchSectionOrder.swift Knobler/Peer.swift \
//     Knobler/Wire.swift Knobler/LANMessaging.swift Knobler/MessageStore.swift \
//     Knobler/Permissions.swift Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift \
//     Knobler/NotchNotification.swift Knobler/FileConverter.swift Knobler/ImageConverter.swift \
//     Knobler/DocumentConverter.swift Knobler/VideoConverter.swift \
//     tools/whatsapppecacheck.swift \
//     -o /tmp/whatsapppecacheck && /tmp/whatsapppecacheck
//
// UserDefaults próprios (suítes `whatsapppecacheck.*`), apagados no começo e no
// fim. O domínio do app nunca é lido nem escrito; `PluginHost.shared`,
// `WhatsAppStore` e `WhatsAppSonda` nunca são tocados; nenhuma rede.

import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsapppecacheck.swift:\(linha))")
        WhatsAppPecaCheck.limpar()
        exit(1)
    }
}

/// Serviço de brinquedo no lugar do `WhatsAppStore`: conta quantas vezes parou.
private final class ServicoFalso: PluginServico {
    private(set) var parou = 0
    func parar() { parou += 1 }
}

/// Os efeitos falsos: contam os nascimentos e guardam cada serviço criado.
private final class Fabrica {
    private(set) var nascimentos = 0
    private(set) var criados: [ServicoFalso] = []

    var efeitos: WhatsAppEfeitos {
        WhatsAppEfeitos(nascer: { [unowned self] in
            nascimentos += 1
            let s = ServicoFalso()
            criados.append(s)
            return s
        })
    }
}

@main
enum WhatsAppPecaCheck {
    static let suites = ["novo", "ciclo", "arranque"].map { "whatsapppecacheck.\($0)" }

    static func limpar() {
        for s in suites {
            UserDefaults().removePersistentDomain(forName: s)
            UserDefaults(suiteName: s)?.removePersistentDomain(forName: s)
        }
    }

    /// `UserDefaults` de brinquedo, isolado do domínio do app (molde do plugincheck).
    static func defaultsLimpo(_ nome: String) -> UserDefaults {
        UserDefaults().removePersistentDomain(forName: nome)
        let d = UserDefaults(suiteName: nome)!
        d.removePersistentDomain(forName: nome)
        return d
    }

    static func main() {
        limpar()
        testInstalacaoNovaNaoNasce()
        testInstalarDesinstalarReinstalar()
        testArranqueComAPecaInstalada()
        limpar()
        print("whatsapppecacheck ok")
    }

    // MARK: - instalação nova

    /// Defaults vazios: o host migra, o WhatsApp fica de fora e o `subir()` do
    /// arranque não visita a peça — nenhum `nascer`, nenhuma conexão.
    static func testInstalacaoNovaNaoNasce() {
        let d = defaultsLimpo(suites[0])
        let fab = Fabrica()
        let host = PluginHost(defaults: d)
        host.whatsappEfeitos = fab.efeitos
        host.subir()

        exigir(!host.estaInstalado(.whatsapp), "instalação nova já veio com o WhatsApp instalado")
        exigir(fab.nascimentos == 0,
               "subir() em instalação nova chamou o nascer do WhatsApp \(fab.nascimentos)×")
        exigir(!host.estaVivo(.whatsapp), "WhatsApp vivo sem estar instalado")
        exigir(host.servico(.whatsapp, as: ServicoFalso.self) == nil, "achou serviço do WhatsApp do nada")
        exigir(host.estadoDoCard(.whatsapp) == .instalar,
               "card do WhatsApp em instalação nova: \(host.estadoDoCard(.whatsapp)) (esperado INSTALAR)")
    }

    // MARK: - instalar, desinstalar, instalar de novo

    static func testInstalarDesinstalarReinstalar() {
        let d = defaultsLimpo(suites[1])
        let fab = Fabrica()
        let host = PluginHost(defaults: d)
        host.whatsappEfeitos = fab.efeitos
        host.subir()
        exigir(fab.nascimentos == 0, "subir() chamou o nascer antes de instalar")

        // instalar liga o estado: um nascimento, serviço vivo
        host.instalar(.whatsapp)
        exigir(host.estaInstalado(.whatsapp), "instalar(.whatsapp) não marcou a peça como instalada")
        exigir(fab.nascimentos == 1,
               "instalar(.whatsapp) chamou o nascer \(fab.nascimentos)× (esperado 1)")
        exigir(host.estaVivo(.whatsapp), "instalar(.whatsapp) não deixou o serviço vivo")
        guard let primeiro = fab.criados.first else {
            exigir(false, "nenhum serviço criado"); return
        }
        exigir(host.servico(.whatsapp, as: ServicoFalso.self) === primeiro,
               "o serviço vivo não é o que o nascer devolveu")
        exigir(host.estadoDoCard(.whatsapp) == .abrir,
               "card depois de instalar: \(host.estadoDoCard(.whatsapp)) (esperado ABRIR)")
        exigir(PluginsInstalados.ler(d).contains(.whatsapp), "instalar não gravou a peça no disco")

        // instalar de novo o que já está instalado não nasce outra vez
        host.instalar(.whatsapp)
        exigir(fab.nascimentos == 1,
               "instalar(.whatsapp) repetido chamou o nascer de novo (\(fab.nascimentos)×)")
        exigir(primeiro.parou == 0, "instalar repetido parou o serviço vivo")

        // desinstalar desliga: parar() uma vez, serviço solto
        host.desinstalar(.whatsapp)
        exigir(primeiro.parou == 1,
               "desinstalar(.whatsapp) chamou parar() \(primeiro.parou)× (esperado 1)")
        exigir(!host.estaInstalado(.whatsapp), "desinstalar não tirou a peça da lista")
        exigir(!host.estaVivo(.whatsapp), "o serviço sobreviveu à desinstalação")
        exigir(host.servico(.whatsapp, as: ServicoFalso.self) == nil, "serviço ainda acessível depois de desinstalar")
        exigir(fab.nascimentos == 1, "desinstalar chamou o nascer")
        exigir(!PluginsInstalados.ler(d).contains(.whatsapp), "desinstalar não gravou no disco")

        // desinstalar de novo não para outra vez
        host.desinstalar(.whatsapp)
        exigir(primeiro.parou == 1, "desinstalar repetido chamou parar() de novo (\(primeiro.parou)×)")

        // instalar de novo nasce de novo, uma vez, com serviço novo
        host.instalar(.whatsapp)
        exigir(fab.nascimentos == 2,
               "reinstalar chamou o nascer \(fab.nascimentos - 1)× (esperado 1, total 2)")
        exigir(host.estaVivo(.whatsapp), "reinstalar não deixou o serviço vivo")
        guard fab.criados.count == 2 else {
            exigir(false, "reinstalar não criou serviço novo"); return
        }
        let segundo = fab.criados[1]
        exigir(segundo !== primeiro, "reinstalar reaproveitou o serviço parado")
        exigir(host.servico(.whatsapp, as: ServicoFalso.self) === segundo,
               "o serviço vivo depois de reinstalar não é o recém-nascido")
        exigir(segundo.parou == 0, "o serviço reinstalado nasceu parado")
        exigir(primeiro.parou == 1, "reinstalar parou o serviço antigo de novo")

        host.desinstalar(.whatsapp)
        exigir(segundo.parou == 1, "o segundo serviço não parou na desinstalação")
    }

    // MARK: - arranque com a peça instalada

    /// Quem instalou ontem abre o app hoje: o `subir()` do arranque chama o
    /// `nascer` uma vez e o serviço fica vivo. E se o app não atribuir os
    /// efeitos (o padrão), instalar não cria serviço nenhum.
    static func testArranqueComAPecaInstalada() {
        let d = defaultsLimpo(suites[2])
        do {
            let host = PluginHost(defaults: d)
            exigir(host.servico(.whatsapp, as: ServicoFalso.self) == nil, "serviço antes de tudo")
            host.instalar(.whatsapp)  // efeitos padrão: nascer devolve nil
            exigir(host.estaInstalado(.whatsapp), "instalar sem efeitos não marcou a peça")
            exigir(!host.estaVivo(.whatsapp), "o nascer padrão criou serviço (devia devolver nil)")
        }
        let fab = Fabrica()
        let host = PluginHost(defaults: d)
        host.whatsappEfeitos = fab.efeitos
        exigir(host.estaInstalado(.whatsapp), "a instalação não sobreviveu ao relançamento")
        exigir(fab.nascimentos == 0, "o nascer rodou antes do subir()")
        host.subir()
        exigir(fab.nascimentos == 1,
               "subir() com a peça instalada chamou o nascer \(fab.nascimentos)× (esperado 1)")
        exigir(host.estaVivo(.whatsapp), "subir() não deixou o WhatsApp vivo com a peça instalada")
        exigir(host.servico(.whatsapp, as: ServicoFalso.self) === fab.criados.first,
               "o serviço vivo no arranque não é o que o nascer devolveu")
        host.desinstalar(.whatsapp)
        exigir(fab.criados.first?.parou == 1, "desinstalar depois do arranque não parou o serviço")
    }
}
