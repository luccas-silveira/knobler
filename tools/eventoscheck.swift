//
//  tools/eventoscheck.swift — self-check do carimbo de eventos por seção.
//  NÃO faz parte do alvo do app.
//
//  Guarda o critério de aceitação do card em foco: **tique não carimba**.
//  Se alguém afrouxar as guardas dos `didSet` do NotchViewModel (trocar por um
//  `!=` seco, por exemplo), o tique de `remaining`/`progress` volta a carimbar,
//  a janela de promoção de 10 s nunca expira e a seção mora no topo pra sempre.
//  Este check falha antes disso chegar no app.
//
//  Rodar: ver a linha `eventoscheck` em tools/check.sh.
//

import AppKit

@main
struct EventosCheck {
    static func main() {
        // hermético: a ordem-base sai do UserDefaults real da máquina, então
        // fixa-se a de fábrica antes do primeiro acesso ao AppSettings.shared.
        UserDefaults.standard.set(NotchSectionOrder.padrao.map(\.rawValue),
                                  forKey: "notchSectionOrder")
        testPomodoroTiqueNaoCarimba()
        testPomodoroFaseECorridaCarimbam()
        testAtividadeProgressoNaoCarimba()
        testAtividadeTituloEDetalheCarimbam()
        testEspelhoSoCarimbaNaVirada()
        testMensagemCarimba()
        testEstadoDasSecoes()
        testFocoInicialEhAPrimeira()
        testFocoInicialPulaFixadaVazia()
        testFocoCaiNaPrimeiraQuandoNadaTemConteudo()
        testFocarTravaESobreviveAoRecalculo()
        testRecolherSoltaATrava()
        testFocarVizinhoCirculaNasDuasDirecoes()
        testFocoTravadoQuePerdeConteudo()
        testTravaDaNotaVenceAEscolhaManual()
        testPedidoDeFocoComOCardJaAberto()
        testPedidoDeFocoSemConteudoEspera()
        testFecharOCardApagaOPedido()
        testPublicarAltura()
        // estes mexem na preferência salva; ficam por último pra não desarrumar
        // a ordem de fábrica que os testes acima assumem.
        testOrdemSalvaPassaPorSanear()
        testOrdemPersistidaSobreviveAoRoundTrip()
        testBaseQueChegaNoOrdenarNaoTemDuplicata()
        print("✅ eventoscheck ok")
    }

    // MARK: - fixtures

    static func pomo(_ phase: PomodoroPhase = .focus,
                     _ run: PomodoroRunState = .running,
                     remaining: TimeInterval = 300) -> PomodoroState {
        PomodoroState(phase: phase, runState: run, remaining: remaining,
                      completedFocus: 0, cyclesUntilLong: 4)
    }

    static func atividade(title: String = "Baixando",
                          detail: String = "arquivo.zip",
                          progress: Double? = 0) -> NotchActivity {
        NotchActivity(id: "a", title: title, detail: detail,
                      progress: progress, updatedAt: Date())
    }

    /// O carimbo é `Date()`; pra comparar "mudou?" sem depender do relógio,
    /// zera-se o registro entre os passos e verifica-se se ele voltou.
    static func carimbou(_ vm: NotchViewModel, _ s: NotchSection,
                         _ acao: () -> Void) -> Bool {
        vm.marcarEvento(s, at: .distantPast)
        acao()
        return vm.eventos[s] != .distantPast
    }

    // MARK: - Pomodoro

    /// O tique de 1 s só mexe em `remaining` — não pode carimbar.
    static func testPomodoroTiqueNaoCarimba() {
        let vm = NotchViewModel()
        vm.pomodoro = pomo(remaining: 300)
        for restante in stride(from: 299.0, through: 295.0, by: -1) {
            let bateu = carimbou(vm, .pomodoro) { vm.pomodoro = pomo(remaining: restante) }
            assert(!bateu, "tique de remaining (\(restante)s) carimbou o Pomodoro")
        }
    }

    /// Virar de foco pra pausa, pausar/retomar e começar/parar são eventos.
    static func testPomodoroFaseECorridaCarimbam() {
        let vm = NotchViewModel()
        assert(carimbou(vm, .pomodoro) { vm.pomodoro = pomo() },
               "começar o Pomodoro não carimbou")
        assert(carimbou(vm, .pomodoro) { vm.pomodoro = pomo(.shortBreak, .running) },
               "virada de fase não carimbou")
        assert(carimbou(vm, .pomodoro) { vm.pomodoro = pomo(.shortBreak, .paused) },
               "mudança de runState não carimbou")
        assert(carimbou(vm, .pomodoro) { vm.pomodoro = nil },
               "parar o Pomodoro não carimbou")
    }

    // MARK: - Atividade

    /// `progress` e `updatedAt` andam a cada passo — não podem carimbar.
    static func testAtividadeProgressoNaoCarimba() {
        let vm = NotchViewModel()
        vm.activity = atividade(progress: 0)
        for passo in stride(from: 0.1, through: 0.9, by: 0.1) {
            let bateu = carimbou(vm, .atividade) { vm.activity = atividade(progress: passo) }
            assert(!bateu, "passo de progress (\(passo)) carimbou a atividade")
        }
        // updatedAt novo sem nada mais mudar também é tique
        let bateu = carimbou(vm, .atividade) { vm.activity = atividade(progress: 0.9) }
        assert(!bateu, "updatedAt novo carimbou a atividade")
    }

    static func testAtividadeTituloEDetalheCarimbam() {
        let vm = NotchViewModel()
        assert(carimbou(vm, .atividade) { vm.activity = atividade() },
               "atividade aparecendo não carimbou")
        assert(carimbou(vm, .atividade) { vm.activity = atividade(title: "Convertendo") },
               "troca de título não carimbou")
        assert(carimbou(vm, .atividade) { vm.activity = atividade(title: "Convertendo",
                                                                 detail: "outro.zip") },
               "troca de detalhe não carimbou")
        assert(carimbou(vm, .atividade) { vm.activity = nil },
               "atividade sumindo não carimbou")
    }

    // MARK: - Espelho e mensagens

    static func testEspelhoSoCarimbaNaVirada() {
        let vm = NotchViewModel()
        assert(carimbou(vm, .espelho) { vm.mirrorOn = true }, "ligar o espelho não carimbou")
        assert(!carimbou(vm, .espelho) { vm.mirrorOn = true },
               "reescrever o mesmo valor carimbou o espelho")
    }

    static func testMensagemCarimba() {
        let vm = NotchViewModel()
        let bateu = carimbou(vm, .mensagens) {
            vm.showIncoming(.init(peerID: "p", name: "N", text: "oi", allowReply: false))
        }
        assert(bateu, "mensagem nova não carimbou")
    }

    // MARK: - Retrato das seções

    static func testEstadoDasSecoes() {
        let vm = NotchViewModel()
        vm.activity = atividade()
        vm.marcarEvento(.musica, at: Date(timeIntervalSince1970: 100))
        let estados = vm.estadoDasSecoes(hasMusic: true, hasShelf: false,
                                         hasHistory: true, hasMensagens: false,
                                         hasNota: false)
        assert(estados.count == NotchSection.allCases.count, "faltou seção no retrato")
        func e(_ s: NotchSection) -> NotchSectionState { estados.first { $0.section == s }! }
        assert(e(.musica).hasContent, "música deveria ter conteúdo")
        assert(e(.musica).lastEvent == Date(timeIntervalSince1970: 100), "carimbo perdido")
        assert(e(.atividade).hasContent, "atividade deveria ter conteúdo")
        assert(!e(.pomodoro).hasContent, "Pomodoro idle não tem conteúdo")
        assert(!e(.shelf).hasContent, "shelf vazio não tem conteúdo")
        assert(e(.historico).hasContent, "histórico deveria ter conteúdo")
        assert(e(.shelf).lastEvent == nil, "seção sem evento deveria vir com lastEvent nil")
    }

    // MARK: - Foco do card

    /// Retrato à mão: só as seções listadas têm conteúdo, nenhuma promovida
    /// (sem `lastEvent`), então a ordem cai na `NotchSectionOrder.padrao`.
    static func comConteudo(_ secoes: NotchSection...) -> [NotchSectionState] {
        NotchSection.allCases.map {
            NotchSectionState(section: $0, hasContent: secoes.contains($0), lastEvent: nil)
        }
    }

    static func testFocoInicialEhAPrimeira() {
        let vm = NotchViewModel()
        vm.recalcularSecoes(comConteudo(.pomodoro, .musica), travadaNaNota: false)
        assert(vm.secoes == [.musica, .pomodoro], "ordem inesperada: \(vm.secoes)")
        assert(vm.focus == .musica, "foco inicial deveria ser a primeira da lista")
        assert(!vm.focusLocked, "foco automático não pode nascer travado")
    }

    /// Fixada vazia entra na ordem, mas não rouba o foco: o card abre no
    /// primeiro conteúdo real.
    static func testFocoInicialPulaFixadaVazia() {
        UserDefaults.standard.set(["nota", "musica"], forKey: "notchSectionOrder")
        UserDefaults.standard.set(["nota"], forKey: "notchSectionsFixadas")
        AppSettings.shared.notchSectionOrder = NotchSectionOrder.sanear(salva: ["nota", "musica"])
        AppSettings.shared.notchSectionsFixadas = [.nota]
        let vm = NotchViewModel()
        vm.recalcularSecoes([
            NotchSectionState(section: .nota, hasContent: false, lastEvent: nil),
            NotchSectionState(section: .musica, hasContent: true, lastEvent: nil),
        ], travadaNaNota: false)
        assert(vm.secoes == [.nota, .musica], "ordem errada: \(vm.secoes)")
        assert(vm.focus == .musica, "foco caiu na fixada vazia: \(String(describing: vm.focus))")
        // restaura o estado de fábrica pros testes seguintes
        AppSettings.shared.notchSectionsFixadas = []
        AppSettings.shared.notchSectionOrder = NotchSectionOrder.padrao
    }

    /// Só fixadas vazias: o card ainda precisa focar alguma coisa.
    static func testFocoCaiNaPrimeiraQuandoNadaTemConteudo() {
        AppSettings.shared.notchSectionsFixadas = [.nota, .musica]
        let vm = NotchViewModel()
        vm.recalcularSecoes([
            NotchSectionState(section: .musica, hasContent: false, lastEvent: nil),
            NotchSectionState(section: .nota, hasContent: false, lastEvent: nil),
        ], travadaNaNota: false)
        assert(vm.focus == vm.secoes.first, "sem conteúdo o foco não é o primeiro")
        AppSettings.shared.notchSectionsFixadas = []
    }

    static func testFocarTravaESobreviveAoRecalculo() {
        let vm = NotchViewModel()
        vm.recalcularSecoes(comConteudo(.musica, .pomodoro), travadaNaNota: false)
        vm.focar(.pomodoro)
        assert(vm.focus == .pomodoro && vm.focusLocked, "clique não travou o foco")
        vm.recalcularSecoes(comConteudo(.musica, .pomodoro), travadaNaNota: false)
        assert(vm.focus == .pomodoro, "recalcular roubou o foco travado")
        // seção fora da lista não pode virar foco
        vm.focar(.shelf)
        assert(vm.focus == .pomodoro, "focou uma seção sem conteúdo")
    }

    static func testRecolherSoltaATrava() {
        let vm = NotchViewModel()
        vm.expanded = true
        vm.recalcularSecoes(comConteudo(.musica, .pomodoro), travadaNaNota: false)
        vm.focar(.pomodoro)
        vm.expanded = false
        assert(!vm.focusLocked, "recolher deveria soltar a trava")
        vm.recalcularSecoes(comConteudo(.musica, .pomodoro), travadaNaNota: false)
        assert(vm.focus == .musica, "próxima abertura deveria voltar ao automático")
    }

    static func testFocarVizinhoCirculaNasDuasDirecoes() {
        let vm = NotchViewModel()
        vm.recalcularSecoes(comConteudo(.musica, .pomodoro, .shelf), travadaNaNota: false)
        assert(vm.secoes == [.musica, .pomodoro, .shelf], "ordem inesperada: \(vm.secoes)")
        vm.focarVizinho(avancando: true)
        assert(vm.focus == .pomodoro, "avançar não andou")
        assert(vm.focusLocked, "swipe deveria travar igual ao clique")
        vm.focarVizinho(avancando: true)
        vm.focarVizinho(avancando: true)
        assert(vm.focus == .musica, "avançar não deu a volta")
        vm.focarVizinho(avancando: false)
        assert(vm.focus == .shelf, "voltar não deu a volta")
        vm.focarVizinho(avancando: false)
        assert(vm.focus == .pomodoro, "voltar não andou")
        // lista de uma seção só não circula
        vm.recalcularSecoes(comConteudo(.musica), travadaNaNota: false)
        vm.focarVizinho(avancando: true)
        assert(vm.focus == .musica, "lista de uma seção não deveria circular")
    }

    static func testFocoTravadoQuePerdeConteudo() {
        let vm = NotchViewModel()
        vm.recalcularSecoes(comConteudo(.musica, .pomodoro), travadaNaNota: false)
        vm.focar(.pomodoro)
        vm.recalcularSecoes(comConteudo(.musica), travadaNaNota: false)
        assert(vm.focus == .musica, "o card ficou sem foco quando a seção travada sumiu")
        assert(!vm.focusLocked, "a trava deveria cair junto com a seção")
    }

    static func testTravaDaNotaVenceAEscolhaManual() {
        let vm = NotchViewModel()
        vm.recalcularSecoes(comConteudo(.musica, .nota), travadaNaNota: false)
        vm.focar(.musica)
        vm.recalcularSecoes(comConteudo(.musica, .nota), travadaNaNota: true)
        assert(vm.secoes.first == .nota, "a nota deveria estar no topo")
        assert(vm.focus == .nota, "digitar na nota deveria vencer a escolha manual")
        // sem conteúdo na nota a trava não age
        vm.recalcularSecoes(comConteudo(.musica), travadaNaNota: true)
        assert(vm.focus == .musica, "trava da nota agiu sem a nota na lista")
    }

    /// O slot `focoPendente` é um pedido de foco feito de fora. Três regras:
    /// com o card já aberto o pedido é honrado na hora (não existe `onChange`
    /// de `expanded` pra consumir o slot); um pedido sem conteúdo na lista
    /// espera em vez de sumir em silêncio; e fechar o card apaga o slot, pra
    /// que nenhum pedido órfão vaze pra abertura seguinte.
    static func testPedidoDeFocoComOCardJaAberto() {
        let vm = NotchViewModel()
        vm.expanded = true
        vm.recalcularSecoes(comConteudo(.musica, .mensagens), travadaNaNota: false)
        assert(vm.focus == .musica, "pré-condição: o card abriu na música")
        vm.openThread(peerID: "p1")
        assert(vm.focus == .mensagens,
               "pedido de foco com o card aberto não foi honrado: \(String(describing: vm.focus))")
        assert(vm.focoPendente == nil, "o pedido honrado deveria ter esvaziado o slot")
    }

    static func testPedidoDeFocoSemConteudoEspera() {
        let vm = NotchViewModel()
        vm.focoPendente = .mensagens
        vm.recalcularSecoes(comConteudo(.musica), travadaNaNota: false)
        assert(vm.focus == .musica, "sem a seção pedida o foco cai no automático")
        assert(vm.focoPendente == .mensagens,
               "o pedido foi descartado antes de a seção existir")
        // a seção aparece: o pedido guardado é consumido
        vm.recalcularSecoes(comConteudo(.musica, .mensagens), travadaNaNota: false)
        assert(vm.focus == .mensagens, "o pedido guardado não foi honrado")
        assert(vm.focoPendente == nil, "o pedido honrado deveria ter esvaziado o slot")
    }

    static func testFecharOCardApagaOPedido() {
        let vm = NotchViewModel()
        vm.expanded = true
        vm.focoPendente = .mensagens
        vm.expanded = false
        assert(vm.focoPendente == nil, "pedido órfão sobreviveu ao fechar o card")
        vm.expanded = true
        vm.recalcularSecoes(comConteudo(.musica, .mensagens), travadaNaNota: false)
        assert(vm.focus == .musica, "o pedido velho roubou a abertura seguinte")
        assert(!vm.focusLocked, "o pedido velho travou o foco da sessão inteira")
    }

    static func testPublicarAltura() {
        let vm = NotchViewModel()
        vm.publicarAltura(120)
        assert(vm.alturaAtual == 120, "altura não publicada")
        vm.publicarAltura(120.2)
        assert(vm.alturaAtual == 120, "ruído sub-pixel republicou a altura")
        vm.publicarAltura(140)
        assert(vm.alturaAtual == 140, "altura nova não publicada")
    }

    // MARK: - ordem-base dos Ajustes

    /// Lixo salvo por uma versão antiga não pode virar base: `sanear` descarta
    /// o desconhecido e completa o que faltou.
    static func testOrdemSalvaPassaPorSanear() {
        let settings = AppSettings.shared
        settings.notchSectionOrder = [.shelf, .musica]
        assert(settings.notchSectionOrder.count == NotchSection.allCases.count,
               "ordem incompleta não foi completada: \(settings.notchSectionOrder)")
        assert(settings.notchSectionOrder.prefix(2) == [.shelf, .musica],
               "sanear não preservou o começo escolhido")
    }

    /// Escreve → lê do UserDefaults → mesma ordem (prova do `didSet`).
    static func testOrdemPersistidaSobreviveAoRoundTrip() {
        let settings = AppSettings.shared
        let escolhida = NotchSectionOrder.sanear(salva: ["nota", "espelho", "musica"])
        settings.notchSectionOrder = escolhida
        let lida = UserDefaults.standard.stringArray(forKey: "notchSectionOrder") ?? []
        // comparação crua: passar `lida` por `sanear` completaria qualquer
        // escrita truncada até 8 e esconderia exatamente o defeito procurado.
        assert(lida == escolhida.map(\.rawValue),
               "a ordem não sobreviveu ao round-trip: \(lida)")
    }

    /// `ordenar(base:)` assume base sem duplicata — inclusive depois de um
    /// reorder torto vindo da lista de Ajustes.
    static func testBaseQueChegaNoOrdenarNaoTemDuplicata() {
        let settings = AppSettings.shared
        settings.notchSectionOrder = [.musica, .musica, .shelf, .shelf, .nota]
        let base = settings.notchSectionOrder
        assert(Set(base).count == base.count, "base com duplicata: \(base)")
        assert(Set(base) == Set(NotchSection.allCases), "base perdeu seção: \(base)")
        // o ramo do saneamento também tem que chegar no disco: se ele corrigir
        // só a memória, o próximo launch restaura a ordem torta de antes.
        let lida = UserDefaults.standard.stringArray(forKey: "notchSectionOrder") ?? []
        assert(lida == base.map(\.rawValue),
               "atribuição não-sã corrigiu a memória mas não o disco: \(lida)")

        // e o VM usa essa base, não mais a de fábrica
        settings.notchSectionOrder = NotchSectionOrder.sanear(salva: ["shelf", "musica"])
        let vm = NotchViewModel()
        vm.recalcularSecoes(comConteudo(.musica, .shelf), travadaNaNota: false)
        assert(vm.secoes == [.shelf, .musica],
               "o VM ignorou a ordem dos Ajustes: \(vm.secoes)")
    }
}
