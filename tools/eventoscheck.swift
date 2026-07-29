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
        testPomodoroTiqueNaoCarimba()
        testPomodoroFaseECorridaCarimbam()
        testAtividadeProgressoNaoCarimba()
        testAtividadeTituloEDetalheCarimbam()
        testEspelhoSoCarimbaNaVirada()
        testMensagemCarimba()
        testEstadoDasSecoes()
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
}
