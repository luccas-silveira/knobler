//
//  tools/plugincheck.swift — self-check da máquina de peças (plugins).
//  NÃO faz parte do alvo do app.
//
//  Nasce na Fase 1 do mapa `.wayfinder/marketplace` e ganha casos a cada fase.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/Plugin.swift Knobler/Pomodoro.swift Knobler/Reminders.swift \
//    Knobler/Descanso.swift Knobler/NotchSectionOrder.swift Knobler/Peer.swift \
//    Knobler/Wire.swift Knobler/LANMessaging.swift Knobler/MessageStore.swift \
//    Knobler/Permissions.swift Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift \
//    Knobler/NotchNotification.swift tools/plugincheck.swift -o /tmp/plugincheck && /tmp/plugincheck
//

import Foundation

@main
struct PluginCheck {
    static func main() {
        testRegistroCobreTodosOsIds()
        testSecaoDaFichaExisteNoEnum()
        testDefaultsVazioViraOsOnze()
        testMigracaoRodaUmaVezSo()
        testIdDesconhecidoIgnoradoCalado()
        testPecaDesligadaNaoNasce()
        testPecaDesinstaladaNaoNasce()
        testTimerLigaComAPecaViva()
        testSuperficiesSomemComAPeca()
        testSemDescansoNaoTravaATela()
        testEstadoDoCardNaVitrine()
        testCardMudoNasNaoConvertidas()
        testLembretesNascemEParam()
        testDescansoNasceEPara()
        testMensagensNascemEParam()
        testWebhooksNascemEParam()
        testDitadoNasceEPara()
        print("✅ plugincheck ok")
    }

    /// `UserDefaults` de brinquedo, isolado do domínio do app.
    static func defaultsLimpo(_ nome: String) -> UserDefaults {
        UserDefaults().removePersistentDomain(forName: nome)
        let d = UserDefaults(suiteName: nome)!
        d.removePersistentDomain(forName: nome)
        return d
    }

    // MARK: - O registro

    static func testRegistroCobreTodosOsIds() {
        assert(PluginRegistry.completo, "peça fora do registro")
        assert(PluginRegistry.todos.count == PluginID.allCases.count,
               "id repetido no registro")
        assert(PluginRegistry.deFabrica.count == 4,
               "as de fábrica são quatro (ticket 002)")
        for peca in PluginRegistry.todos {
            assert(!peca.nome.isEmpty && !peca.descricao.isEmpty && !peca.simbolo.isEmpty,
                   "ficha incompleta: \(peca.id.rawValue)")
        }
    }

    /// A ficha só cita o nome da seção (o enum fica como está, decisão de 003):
    /// erro de digitação aqui só apareceria na tela, então o gate confere.
    static func testSecaoDaFichaExisteNoEnum() {
        for peca in PluginRegistry.todos {
            guard let secao = peca.secao else { continue }
            assert(NotchSection(rawValue: secao) != nil,
                   "seção inexistente na ficha \(peca.id.rawValue): \(secao)")
        }
    }

    // MARK: - O instalado

    /// Instalação do zero: ninguém perde feature — os 11 vêm ligados.
    static func testDefaultsVazioViraOsOnze() {
        let d = defaultsLimpo("plugincheck.novo")
        assert(PluginsInstalados.ler(d).isEmpty, "defaults não estava limpo")
        PluginsInstalados.migrarSePreciso(d)
        assert(PluginsInstalados.ler(d) == Set(PluginID.allCases),
               "migração não instalou os 11: \(PluginsInstalados.ler(d))")
    }

    /// A migração é uma vez só — senão desinstalar não colaria: a peça voltaria
    /// instalada no próximo launch.
    static func testMigracaoRodaUmaVezSo() {
        let d = defaultsLimpo("plugincheck.duasvezes")
        PluginsInstalados.migrarSePreciso(d)
        PluginsInstalados.gravar([.pomodoro], d)
        PluginsInstalados.migrarSePreciso(d)
        assert(PluginsInstalados.ler(d) == [.pomodoro],
               "a migração rodou de novo e reinstalou tudo")
    }

    /// Id que este build não conhece é ignorado calado — e **não** é apagado:
    /// peça que volte com o mesmo nome volta instalada (ticket 005).
    static func testIdDesconhecidoIgnoradoCalado() {
        let d = defaultsLimpo("plugincheck.orfao")
        d.set(["pomodoro", "peca-de-outra-versao"], forKey: PluginsInstalados.chave)
        assert(PluginsInstalados.ler(d) == [.pomodoro],
               "id desconhecido virou peça")

        PluginsInstalados.gravar([.pomodoro, .descanso], d)
        let gravado = d.stringArray(forKey: PluginsInstalados.chave) ?? []
        assert(gravado.contains("peca-de-outra-versao"), "id órfão foi apagado: \(gravado)")
        assert(Set(gravado) == ["pomodoro", "descanso", "peca-de-outra-versao"], "\(gravado)")
    }

    // MARK: - O host

    static func testPecaDesligadaNaoNasce() {
        let d = defaultsLimpo("plugincheck.host")
        PluginsInstalados.gravar([.pomodoro], d)
        d.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)

        let host = PluginHost(defaults: d)
        host.subir()
        assert(host.estaVivo(.pomodoro), "a cobaia não nasceu")
        assert(!host.estaInstalado(.descanso), "peça desinstalada apareceu instalada")
        assert(host.secoes == ["pomodoro"], "seções: \(host.secoes)")
        assert(host.paineis == ["pomodoro"], "painéis: \(host.paineis)")
        assert(host.rotas.isEmpty, "rotas: \(host.rotas)")

        // Desinstalar mata o serviço e persiste — é disso que o custo zero depende.
        host.desinstalar(.pomodoro)
        assert(!host.estaVivo(.pomodoro), "serviço sobreviveu à desinstalação")
        assert(PluginsInstalados.ler(d).isEmpty, "desinstalar não persistiu")
    }

    // MARK: - Fase 2: o nascimento condicional

    /// Com a peça fora da lista, `subir()` nem visita a ficha: não há objeto
    /// `Pomodoro`, logo não há `Timer` de 1 s. É o item 1 do piloto (004).
    static func testPecaDesinstaladaNaoNasce() {
        let d = defaultsLimpo("plugincheck.semcobaia")
        PluginsInstalados.gravar([.descanso], d)
        d.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)

        var nasceu = false
        let host = PluginHost(defaults: d)
        host.pomodoroEfeitos.publicarEstado = { _ in nasceu = true }
        host.subir()

        assert(!host.estaInstalado(.pomodoro), "a peça devia estar desinstalada")
        assert(!host.estaVivo(.pomodoro), "a peça desinstalada nasceu mesmo assim")
        assert(host.servico(.pomodoro, as: Pomodoro.self) == nil, "achou serviço do nada")
        assert(!nasceu, "a montagem rodou com a peça desinstalada")
        assert(host.secoes.isEmpty, "seção do Pomodoro sobrou: \(host.secoes)")
    }

    /// A cobaia viva: o tique de 1 s liga com o foco rodando, a montagem da
    /// ficha está de fato ligada, e desinstalar apaga o timer. Item 3 do piloto.
    static func testTimerLigaComAPecaViva() {
        let d = defaultsLimpo("plugincheck.timer")
        // com o Descanso junto: é ele quem trava a tela na pausa (ver
        // `testSemDescansoNaoTravaATela`).
        PluginsInstalados.gravar([.pomodoro, .descanso], d)
        d.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)

        var estados = 0, bordas: [Bool] = [], pausas: [TimeInterval] = []
        let host = PluginHost(defaults: d)
        host.pomodoroEfeitos = PomodoroEfeitos(
            config: { .padrao },
            publicarEstado: { _ in estados += 1 },
            atividadeMudou: { bordas.append($0) },
            fimDeFase: { _, _ in },
            pausaComecou: { pausas.append($0) })
        host.subir()

        guard let pom = host.servico(.pomodoro, as: Pomodoro.self) else {
            fatalError("a cobaia não nasceu")
        }
        assert(!pom.timerAtivo, "timer de pé antes de começar o foco")

        pom.start()
        assert(pom.timerAtivo, "foco rodando e o timer não subiu")
        assert(estados > 0, "a montagem não ligou o publicarEstado")
        assert(bordas == [true], "a borda de atividade não avisou uma vez só: \(bordas)")

        // pular o foco começa a pausa curta — é o gancho que trava a tela
        pom.skip()
        assert(pausas == [Pomodoro.Config.padrao.shortBreak], "pausas: \(pausas)")

        // Desinstalar mata o tique: sem timer, sem custo.
        host.desinstalar(.pomodoro)
        assert(!pom.timerAtivo, "o timer de 1 s sobreviveu à desinstalação")
        assert(bordas == [true, false], "não avisou que a atividade caiu: \(bordas)")
    }

    // MARK: - Fase 3: as superfícies somem

    /// Desinstalar tira a seção do card/faixa E o painel dos Ajustes. As
    /// superfícies que não são de peça nenhuma (Geral, Notch, Música) nunca
    /// aparecem na lista de escondidas, logo nunca somem.
    static func testSuperficiesSomemComAPeca() {
        let d = defaultsLimpo("plugincheck.superficies")
        PluginsInstalados.gravar(Set(PluginID.allCases), d)
        d.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)

        let host = PluginHost(defaults: d)
        assert(host.secoesEscondidas.isEmpty, "escondeu seção com tudo instalado")
        assert(host.paineisEscondidos.isEmpty, "escondeu painel com tudo instalado")
        assert(host.secoes.contains("pomodoro") && host.paineis.contains("pomodoro"))

        host.desinstalar(.pomodoro)
        assert(host.secoesEscondidas == ["pomodoro"], "seções: \(host.secoesEscondidas)")
        assert(host.paineisEscondidos == ["pomodoro"], "painéis: \(host.paineisEscondidos)")
        assert(!host.secoes.contains("pomodoro"), "seção sobreviveu: \(host.secoes)")
        assert(!host.paineis.contains("pomodoro"), "painel sobreviveu: \(host.paineis)")
        // é o que a `NotchSectionOrder.visiveis`/`ordenar` recebem por parâmetro
        assert(NotchSection.desinstaladas(host) == [.pomodoro],
               "conversão pro enum falhou: \(NotchSection.desinstaladas(host))")
        // "Geral"/"Notch" não são de peça nenhuma: não têm como sumir
        assert(!host.paineisEscondidos.contains("geral"))
    }

    /// Sem a peça Descanso não há o que travar a tela: o efeito não roda nem com
    /// o ajuste antigo ligado. No app real o Descanso está sempre presente —
    /// este caminho só é exercitado aqui.
    static func testSemDescansoNaoTravaATela() {
        let d = defaultsLimpo("plugincheck.semdescanso")
        PluginsInstalados.gravar([.pomodoro], d)
        d.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)

        var pausas: [TimeInterval] = []
        let host = PluginHost(defaults: d)
        host.pomodoroEfeitos.pausaComecou = { pausas.append($0) }
        host.subir()
        assert(!host.estaInstalado(.descanso), "o Descanso devia estar de fora")

        guard let pom = host.servico(.pomodoro, as: Pomodoro.self) else {
            fatalError("a cobaia não nasceu")
        }
        pom.start()
        pom.skip()   // entra na pausa curta: é o gancho da trava
        assert(pausas.isEmpty, "travou a tela sem o Descanso instalado: \(pausas)")

        // com a peça de volta, o mesmo caminho trava.
        host.instalar(.descanso)
        var comDescanso: [TimeInterval] = []
        host.pomodoroEfeitos.pausaComecou = { comDescanso.append($0) }
        host.desinstalar(.pomodoro)
        host.instalar(.pomodoro)
        host.servico(.pomodoro, as: Pomodoro.self)?.start()
        host.servico(.pomodoro, as: Pomodoro.self)?.skip()
        assert(comDescanso == [Pomodoro.Config.padrao.shortBreak], "pausas: \(comDescanso)")
    }

    // MARK: - Fase 4: a vitrine

    /// O botão do card sai da lista de instalados, e só dela. Peça instalada diz
    /// ABRIR — nunca um rótulo cinza morto (convenção da App Store, ticket 006) —
    /// e é a única que oferece desinstalar.
    static func testEstadoDoCardNaVitrine() {
        let d = defaultsLimpo("plugincheck.vitrine")
        PluginsInstalados.gravar(Set(PluginID.allCases), d)
        d.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)
        let host = PluginHost(defaults: d)

        assert(host.estadoDoCard(.pomodoro) == .abrir, "instalada e convertida tem que abrir")
        assert(host.estadoDoCard(.pomodoro).temMenuDeDesinstalar,
               "peça instalada não ofereceu desinstalar")

        host.desinstalar(.pomodoro)
        assert(host.estadoDoCard(.pomodoro) == .instalar, "desinstalada tem que oferecer instalar")
        assert(!host.estadoDoCard(.pomodoro).temMenuDeDesinstalar,
               "peça desinstalada ofereceu desinstalar de novo")

        // reinstalar é o desfazer: sem diálogo, sem perda (ticket 007).
        host.instalar(.pomodoro)
        assert(host.estadoDoCard(.pomodoro) == .abrir, "reinstalar não voltou ao estado anterior")
    }

    /// As dez peças que ainda não têm `nascer` de verdade mostram "Em breve" no
    /// lugar do botão — instalar o que não nasce seria mentira (ticket 009). O
    /// estado sai da ficha, não de uma lista à parte que alguém esquece de
    /// atualizar quando converter a próxima peça.
    static func testCardMudoNasNaoConvertidas() {
        let d = defaultsLimpo("plugincheck.mudo")
        PluginsInstalados.gravar(Set(PluginID.allCases), d)
        d.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)
        let host = PluginHost(defaults: d)

        for peca in PluginRegistry.todos where !peca.pronta {
            assert(host.estadoDoCard(peca.id) == .emBreve,
                   "\(peca.nome) não é convertida e mesmo assim ofereceu botão")
            assert(!host.estadoDoCard(peca.id).temMenuDeDesinstalar,
                   "\(peca.nome) ofereceu desinstalar sem nunca ter nascido")
        }

        // Pomodoro, Lembretes, Descanso, Mensagens e Notificações externas são
        // as convertidas nesta fase — se um dia deixar de ser verdade, é este
        // assert que avisa que a vitrine tem card novo pra abrir.
        assert(PluginRegistry.todos.filter(\.pronta).map(\.id) ==
               [.pomodoro, .lembretes, .descanso, .mensagens, .webhooks, .ditado],
               "mudou quem está convertido: \(PluginRegistry.todos.filter(\.pronta).map(\.id))")
    }

    // MARK: - Tarefa 1: Lembretes

    /// A segunda conversão: pronta, nasce só quando instalada, e desligar a
    /// peça desliga o wake que a montagem registrou — observer vazado é o bug
    /// que sobrevive à desinstalação.
    static func testLembretesNascemEParam() {
        assert(PluginRegistry.ficha(.lembretes)?.pronta == true, "Lembretes não está pronta")

        let d = defaultsLimpo("plugincheck.lembretes")
        PluginsInstalados.gravar([.lembretes], d)
        d.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)

        var desligou = false
        let host = PluginHost(defaults: d)
        host.lembretesEfeitos.registrarWake = { _ in { desligou = true } }
        host.subir()

        assert(host.estaVivo(.lembretes), "a peça não nasceu instalada")
        assert(host.servico(.lembretes, as: ReminderScheduler.self) != nil, "não achou o serviço")

        host.desinstalar(.lembretes)
        assert(!host.estaVivo(.lembretes), "o serviço sobreviveu à desinstalação")
        assert(desligou, "o wake não foi desligado — observer vazado")

        // sem a peça na lista de instalados, o serviço não nasce.
        let d2 = defaultsLimpo("plugincheck.semlembretes")
        PluginsInstalados.gravar([.pomodoro], d2)
        d2.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)
        let host2 = PluginHost(defaults: d2)
        host2.subir()
        assert(!host2.estaVivo(.lembretes), "nasceu sem estar instalada")
        assert(host2.servico(.lembretes, as: ReminderScheduler.self) == nil, "achou serviço do nada")
    }

    // MARK: - Tarefa 2: Descanso

    /// A terceira conversão: pronta, nasce só quando instalada, o wake desliga
    /// na desinstalação (mesmo mecanismo dos Lembretes) e `parar()` chama o
    /// efeito de encerrar o overlay em curso — é o que evita um bloqueio de
    /// tela órfão sobrevivendo à desinstalação da peça.
    static func testDescansoNasceEPara() {
        assert(PluginRegistry.ficha(.descanso)?.pronta == true, "Descanso não está pronta")

        let d = defaultsLimpo("plugincheck.descanso")
        PluginsInstalados.gravar([.descanso], d)
        d.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)

        var desligou = false
        var overlayParado = false
        let host = PluginHost(defaults: d)
        host.descansoEfeitos.registrarWake = { _ in { desligou = true } }
        host.descansoEfeitos.pararBloqueioSeAtivo = { overlayParado = true }
        host.subir()

        assert(host.estaVivo(.descanso), "a peça não nasceu instalada")
        assert(host.servico(.descanso, as: DescansoServico.self) != nil, "não achou o serviço")

        host.desinstalar(.descanso)
        assert(!host.estaVivo(.descanso), "o serviço sobreviveu à desinstalação")
        assert(desligou, "o wake não foi desligado — observer vazado")
        assert(overlayParado, "parar() não pediu pro overlay encerrar")

        // sem a peça na lista de instalados, o serviço não nasce.
        let d2 = defaultsLimpo("plugincheck.semdescanso")
        PluginsInstalados.gravar([.pomodoro], d2)
        d2.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)
        let host2 = PluginHost(defaults: d2)
        host2.subir()
        assert(!host2.estaVivo(.descanso), "nasceu sem estar instalada")
        assert(host2.servico(.descanso, as: DescansoServico.self) == nil, "achou serviço do nada")
    }

    // MARK: - Tarefa 3: Mensagens

    /// A quarta conversão: pronta, nasce só quando instalada, e `parar()`
    /// desliga o observer de mudança de nome (mesmo mecanismo do wake nas
    /// duas peças anteriores) — observer vazado é o bug que sobrevive à
    /// desinstalação.
    static func testMensagensNascemEParam() {
        assert(PluginRegistry.ficha(.mensagens)?.pronta == true, "Mensagens não está pronta")

        let d = defaultsLimpo("plugincheck.mensagens")
        PluginsInstalados.gravar([.mensagens], d)
        d.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)

        var desligou = false
        let host = PluginHost(defaults: d)
        host.mensagensEfeitos.registrarMudancaNome = { _ in { desligou = true } }
        host.subir()

        assert(host.estaVivo(.mensagens), "a peça não nasceu instalada")
        assert(host.servico(.mensagens, as: MensagensServico.self) != nil, "não achou o serviço")

        host.desinstalar(.mensagens)
        assert(!host.estaVivo(.mensagens), "o serviço sobreviveu à desinstalação")
        assert(desligou, "o observer de nome não foi desligado — vazou")

        // sem a peça na lista de instalados, o serviço não nasce.
        let d2 = defaultsLimpo("plugincheck.semmensagens")
        PluginsInstalados.gravar([.pomodoro], d2)
        d2.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)
        let host2 = PluginHost(defaults: d2)
        host2.subir()
        assert(!host2.estaVivo(.mensagens), "nasceu sem estar instalada")
        assert(host2.servico(.mensagens, as: MensagensServico.self) == nil, "achou serviço do nada")
    }

    // MARK: - Tarefa 4: Notificações externas (webhooks)

    /// A quinta conversão: pronta, nasce só quando instalada, o ajuste
    /// (opt-in) manda no `start()/stop()` dentro da peça viva, e `parar()`
    /// desliga o observer do ajuste — observer vazado é o bug que sobrevive
    /// à desinstalação, mesmo mecanismo das três peças anteriores.
    static func testWebhooksNascemEParam() {
        assert(PluginRegistry.ficha(.webhooks)?.pronta == true, "Notificações externas não está pronta")

        let d = defaultsLimpo("plugincheck.webhooks")
        PluginsInstalados.gravar([.webhooks], d)
        d.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)

        var desligou = false
        let host = PluginHost(defaults: d)
        host.webhooksEfeitos.registrarMudancaAjuste = { _ in { desligou = true } }
        host.subir()

        assert(host.estaVivo(.webhooks), "a peça não nasceu instalada")
        assert(host.servico(.webhooks, as: WebhookClient.self) != nil, "não achou o serviço")

        host.desinstalar(.webhooks)
        assert(!host.estaVivo(.webhooks), "o serviço sobreviveu à desinstalação")
        assert(desligou, "o observer do ajuste não foi desligado — vazou")

        // sem a peça na lista de instalados, o serviço não nasce.
        let d2 = defaultsLimpo("plugincheck.semwebhooks")
        PluginsInstalados.gravar([.pomodoro], d2)
        d2.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)
        let host2 = PluginHost(defaults: d2)
        host2.subir()
        assert(!host2.estaVivo(.webhooks), "nasceu sem estar instalada")
        assert(host2.servico(.webhooks, as: WebhookClient.self) == nil, "achou serviço do nada")
    }

    // MARK: - Tarefa 5: Ditado

    /// Dublê do `DictationController` pro harness — o real importa FluidAudio,
    /// que este `swiftc` avulso não resolve (por isso `DitadoEfeitos.nascer` é
    /// UM closure emprestado, não efeitos tipados: ver `Plugin.swift`).
    final class DitadoServicoFake: PluginServico {
        var parou = false
        func parar() { parou = true }
    }

    /// A sexta conversão e a primeira com **gancho global**: `montarDitado`
    /// só repassa pro closure emprestado (`deps.ditado.nascer`) — o que dá pra
    /// testar aqui, sem o `DictationController` real, é que a peça pronta
    /// nasce chamando esse closure quando instalada, `parar()` chega até ele
    /// na desinstalação, e sem a peça instalada o closure nem é chamado.
    static func testDitadoNasceEPara() {
        assert(PluginRegistry.ficha(.ditado)?.pronta == true, "Ditado não está pronta")

        let d = defaultsLimpo("plugincheck.ditado")
        PluginsInstalados.gravar([.ditado], d)
        d.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)

        let fake = DitadoServicoFake()
        let host = PluginHost(defaults: d)
        host.ditadoEfeitos.nascer = { fake }
        host.subir()

        assert(host.estaVivo(.ditado), "a peça não nasceu instalada")
        assert(host.servico(.ditado, as: DitadoServicoFake.self) === fake, "não achou o serviço")

        host.desinstalar(.ditado)
        assert(!host.estaVivo(.ditado), "o serviço sobreviveu à desinstalação")
        assert(fake.parou, "parar() não chegou ao closure emprestado")

        // sem a peça na lista de instalados, o closure de nascer nem é chamado.
        var chamou = false
        let d2 = defaultsLimpo("plugincheck.semditado")
        PluginsInstalados.gravar([.pomodoro], d2)
        d2.set(PluginsInstalados.versaoMigracao, forKey: PluginsInstalados.chaveMigracao)
        let host2 = PluginHost(defaults: d2)
        host2.ditadoEfeitos.nascer = { chamou = true; return DitadoServicoFake() }
        host2.subir()
        assert(!host2.estaVivo(.ditado), "nasceu sem estar instalada")
        assert(!chamou, "o closure de nascer foi chamado sem a peça instalada")
    }
}
