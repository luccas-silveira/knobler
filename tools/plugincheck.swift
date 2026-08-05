//
//  tools/plugincheck.swift — self-check da máquina de peças (plugins).
//  NÃO faz parte do alvo do app.
//
//  Nasce na Fase 1 do mapa `.wayfinder/marketplace` e ganha casos a cada fase.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/Plugin.swift Knobler/Pomodoro.swift Knobler/NotchSectionOrder.swift \
//    tools/plugincheck.swift -o /tmp/plugincheck && /tmp/plugincheck
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
        PluginsInstalados.gravar([.pomodoro], d)
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
}
