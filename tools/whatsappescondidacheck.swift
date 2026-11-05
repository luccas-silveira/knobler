// Gate da etapa 9 do WhatsApp: a peça nasce junto com a seção e escondida —
// desinstalada em instalação nova, nunca acrescentada a quem já migrou, fora
// da vitrine sem a ponte identificada, e instalar não abre conexão.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/Plugin.swift Knobler/Pomodoro.swift Knobler/Reminders.swift \
//     Knobler/Descanso.swift Knobler/NotchSectionOrder.swift Knobler/Peer.swift \
//     Knobler/Wire.swift Knobler/LANMessaging.swift Knobler/MessageStore.swift \
//     Knobler/Permissions.swift Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift \
//     Knobler/NotchNotification.swift Knobler/FileConverter.swift Knobler/ImageConverter.swift \
//     Knobler/DocumentConverter.swift Knobler/VideoConverter.swift \
//     tools/whatsappescondidacheck.swift \
//     -o /tmp/whatsappescondidacheck && /tmp/whatsappescondidacheck
//
// UserDefaults próprios (suítes `whatsappescondidacheck.*`), apagados no começo
// e no fim. O domínio do app nunca é lido nem escrito; `PluginHost.shared` e
// `WhatsAppSonda` nunca são instanciados; nenhuma rede.

import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappescondidacheck.swift:\(linha))")
        WhatsAppEscondidaCheck.limpar()
        exit(1)
    }
}

/// Serviço de brinquedo: prova que a ficha nasce pelo `deps.whatsapp`.
private final class ServicoFalso: PluginServico {
    private(set) var parou = 0
    func parar() { parou += 1 }
}

@main
enum WhatsAppEscondidaCheck {
    static let suites = ["novo", "migrado", "antesDeAgentes", "tudo", "instalar", "fiacao"]
        .map { "whatsappescondidacheck.\($0)" }

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

    /// Lista que a migração v1 gravou antes do WhatsApp existir (todas menos
    /// Monitores e Texto da tela), escrita à mão: não deriva do enum novo.
    static let listaDeAntes = [
        "pomodoro", "lembretes", "descanso", "mensagens", "webhooks", "ditado",
        "espelho", "anotacao", "notaRapida", "previewLink", "conversao", "agentes",
    ]

    static func main() {
        limpar()
        // "não trava": instalar não pode esperar conexão nenhuma
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
            print("FALHOU: o gate travou por 20 s (tools/whatsappescondidacheck.swift)")
            limpar()
            exit(1)
        }
        testFicha()
        testInstalacaoNova()
        testQuemJaMigrou()
        testInstalarEDesinstalar()
        testFiacaoDoNascer()
        testVitrine()
        limpar()
        print("whatsappescondidacheck ok")
    }

    // MARK: - ficha

    static func testFicha() {
        exigir(PluginID.whatsapp.rawValue == "whatsapp", "rawValue da peça (vai pro UserDefaults)")
        exigir(PluginID(rawValue: "whatsapp") == .whatsapp, "id salvo não volta pra peça")
        exigir(PluginRegistry.completo, "registro sem a ficha de algum id")
        exigir(PluginRegistry.todos.filter { $0.id == .whatsapp }.count == 1,
               "ficha do WhatsApp ausente ou repetida em PluginRegistry.todos")
        guard let f = PluginRegistry.ficha(.whatsapp) else {
            exigir(false, "PluginRegistry.ficha(.whatsapp) é nil"); return
        }
        exigir(f.nome == "WhatsApp", "nome: \(f.nome)")
        exigir(!f.descricao.isEmpty, "descrição vazia")
        exigir(f.simbolo == "phone.bubble.fill", "símbolo: \(f.simbolo)")
        exigir(f.secao == "whatsapp", "seção da ficha: \(String(describing: f.secao))")
        exigir(f.secao.flatMap(NotchSection.init(rawValue:)) == .whatsapp,
               "seção da ficha não é NotchSection.whatsapp")
        exigir(f.pronta, "ficha do WhatsApp não está pronta (a vitrine mostraria \"Em breve\")")
    }

    // MARK: - instalação nova

    static func testInstalacaoNova() {
        let d = defaultsLimpo(suites[0])
        exigir(PluginsInstalados.ler(d).isEmpty, "defaults não estava limpo")
        PluginsInstalados.migrarSePreciso(d)
        let lidos = PluginsInstalados.ler(d)
        exigir(!lidos.contains(.whatsapp), "instalação nova já veio com o WhatsApp instalado")
        exigir(!lidos.contains(.monitores), "instalação nova instalou Monitores")
        exigir(!lidos.contains(.textoDaTela), "instalação nova instalou Texto da tela")
        exigir(lidos == Set(PluginID.allCases).subtracting([.monitores, .textoDaTela, .whatsapp]),
               "migração mexeu nas outras peças: \(lidos.map(\.rawValue).sorted())")

        // o host sobre defaults vazios faz a migração ele mesmo
        let d2 = defaultsLimpo(suites[0])
        let host = PluginHost(defaults: d2)
        exigir(!host.estaInstalado(.whatsapp), "host novo instalou o WhatsApp")
        exigir(NotchSection.desinstaladas(host).contains(.whatsapp),
               "seção whatsapp não está entre as desinstaladas: aparece na faixa de quem não tem a ponte")
        exigir(host.secoesEscondidas.contains("whatsapp"), "secoesEscondidas sem whatsapp")
        exigir(host.estadoDoCard(.whatsapp) == .instalar,
               "card do WhatsApp em instalação nova: \(host.estadoDoCard(.whatsapp))")
        exigir(!host.estaVivo(.whatsapp), "WhatsApp vivo sem estar instalado")
    }

    // MARK: - quem já migrou

    static func testQuemJaMigrou() {
        // (a) migrou na v1, já passou pelo passo de Agentes
        do {
            let d = defaultsLimpo(suites[1])
            d.set(listaDeAntes, forKey: PluginsInstalados.chave)
            d.set(1, forKey: PluginsInstalados.chaveMigracao)
            d.set(true, forKey: PluginsInstalados.chaveAgentes)
            let host = PluginHost(defaults: d)
            exigir(!host.estaInstalado(.whatsapp), "quem já migrou ganhou o WhatsApp")
            exigir(!PluginsInstalados.ler(d).contains(.whatsapp), "WhatsApp gravado na lista de quem já migrou")
            exigir(NotchSection.desinstaladas(host).contains(.whatsapp),
                   "seção whatsapp visível pra quem já migrou")
            exigir(host.estadoDoCard(.whatsapp) == .instalar, "card: \(host.estadoDoCard(.whatsapp))")
            // segunda abertura do app: continua sem
            let outra = PluginHost(defaults: d)
            exigir(!outra.estaInstalado(.whatsapp), "WhatsApp apareceu na segunda abertura")
        }
        // (b) migrou antes do passo de Agentes: ganha Agentes, não ganha WhatsApp
        do {
            let d = defaultsLimpo(suites[2])
            d.set(listaDeAntes.filter { $0 != "agentes" }, forKey: PluginsInstalados.chave)
            d.set(1, forKey: PluginsInstalados.chaveMigracao)
            let host = PluginHost(defaults: d)
            exigir(host.estaInstalado(.agentes), "o passo de Agentes parou de rodar")
            exigir(!host.estaInstalado(.whatsapp), "o passo de Agentes trouxe o WhatsApp junto")
            exigir(NotchSection.desinstaladas(host).contains(.whatsapp), "seção whatsapp visível")
        }
        // (c) quem tinha tudo instalado (inclusive Monitores e Texto da tela)
        do {
            let d = defaultsLimpo(suites[3])
            d.set(listaDeAntes + ["monitores", "textoDaTela"], forKey: PluginsInstalados.chave)
            d.set(1, forKey: PluginsInstalados.chaveMigracao)
            d.set(true, forKey: PluginsInstalados.chaveAgentes)
            let host = PluginHost(defaults: d)
            exigir(!host.estaInstalado(.whatsapp), "quem tinha tudo ganhou o WhatsApp")
            exigir(host.estaInstalado(.monitores) && host.estaInstalado(.textoDaTela),
                   "o host perdeu peça já instalada")
        }
    }

    // MARK: - instalar e desinstalar

    static func testInstalarEDesinstalar() {
        let d = defaultsLimpo(suites[4])
        let host = PluginHost(defaults: d)
        // efeitos padrão: ninguém liga o nascer nesta etapa
        exigir(host.whatsappEfeitos.nascer() == nil, "WhatsAppEfeitos() padrão nasce um serviço")
        exigir(WhatsAppEfeitos().nascer() == nil, "WhatsAppEfeitos() padrão nasce um serviço")

        host.instalar(.whatsapp)
        exigir(host.estaInstalado(.whatsapp), "instalar não instalou")
        exigir(!NotchSection.desinstaladas(host).contains(.whatsapp),
               "seção whatsapp continua escondida depois de instalar")
        exigir(!host.secoesEscondidas.contains("whatsapp"), "secoesEscondidas ainda tem whatsapp")
        exigir(host.estadoDoCard(.whatsapp) == .abrir, "card depois de instalar: \(host.estadoDoCard(.whatsapp))")
        exigir(!host.estaVivo(.whatsapp), "instalar com efeitos padrão deixou serviço vivo")
        exigir(PluginsInstalados.ler(d).contains(.whatsapp), "instalar não gravou no UserDefaults")
        exigir(PluginHost(defaults: d).estaInstalado(.whatsapp), "instalação não sobreviveu à reabertura")

        host.desinstalar(.whatsapp)
        exigir(!host.estaInstalado(.whatsapp), "desinstalar não desinstalou")
        exigir(NotchSection.desinstaladas(host).contains(.whatsapp),
               "seção whatsapp não voltou a ficar escondida")
        exigir(host.secoesEscondidas.contains("whatsapp"), "secoesEscondidas sem whatsapp depois de desinstalar")
        exigir(host.estadoDoCard(.whatsapp) == .instalar, "card depois de desinstalar: \(host.estadoDoCard(.whatsapp))")
        exigir(!PluginHost(defaults: d).estaInstalado(.whatsapp), "desinstalação não sobreviveu à reabertura")
    }

    /// A ficha nasce pelo `deps.whatsapp.nascer` que o host empresta (molde da
    /// Nota rápida): quando o app ligar o serviço, instalar o põe vivo e
    /// desinstalar o para.
    static func testFiacaoDoNascer() {
        let d = defaultsLimpo(suites[5])
        let host = PluginHost(defaults: d)
        let falso = ServicoFalso()
        var nascimentos = 0
        host.whatsappEfeitos.nascer = { nascimentos += 1; return falso }
        host.instalar(.whatsapp)
        exigir(nascimentos == 1, "instalar chamou o nascer \(nascimentos) vez(es)")
        exigir(host.estaVivo(.whatsapp), "serviço do WhatsApp não ficou vivo")
        exigir(host.servico(.whatsapp, as: ServicoFalso.self) === falso, "serviço vivo não é o que o nascer devolveu")
        host.desinstalar(.whatsapp)
        exigir(falso.parou == 1, "desinstalar não parou o serviço (parou \(falso.parou))")
        exigir(!host.estaVivo(.whatsapp), "serviço continuou vivo depois de desinstalar")

        // a ficha lê o efeito de PluginDeps, não um valor fixo
        var deps = PluginDeps(instalado: { _ in false })
        exigir(PluginRegistry.ficha(.whatsapp)?.nascer(deps) == nil, "ficha nasceu com efeitos padrão")
        deps.whatsapp.nascer = { falso }
        exigir(PluginRegistry.ficha(.whatsapp)?.nascer(deps) === falso, "ficha não nasce por deps.whatsapp")
    }

    // MARK: - vitrine

    static func testVitrine() {
        let todas = PluginRegistry.todos.map(\.id)
        let sem = PluginRegistry.naVitrine(ponteIdentificada: false).map(\.id)
        exigir(!sem.contains(.whatsapp), "vitrine mostra o WhatsApp sem a ponte identificada")
        exigir(sem == todas.filter { $0 != .whatsapp }, "vitrine sem a ponte mexeu nas outras: \(sem)")
        let com = PluginRegistry.naVitrine(ponteIdentificada: true).map(\.id)
        exigir(com.contains(.whatsapp), "vitrine não mostra o WhatsApp com a ponte identificada")
        exigir(com == todas, "vitrine com a ponte fora da ordem do registro: \(com)")
        // esconder é filtro na vitrine, nunca tirar a ficha do registro
        exigir(PluginRegistry.ficha(.whatsapp) != nil && PluginRegistry.completo,
               "a vitrine escondeu tirando a ficha do registro")
    }
}
