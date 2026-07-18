//
//  Pomodoro.swift
//  Knobler
//
//  Engine do timer Pomodoro: foco → pausa → …, para no fim de cada fase e
//  espera o usuário iniciar a próxima. Só Foundation (compila isolado pro
//  self-check e pro harness de snapshot). Tempo por relógio de parede.
//

import Foundation

enum PomodoroPhase: Equatable { case focus, shortBreak, longBreak }
enum PomodoroRunState: Equatable { case idle, running, paused, waiting }

/// Estado publicado pro ViewModel. nil = idle (sem pílula).
struct PomodoroState: Equatable {
    var phase: PomodoroPhase
    var runState: PomodoroRunState
    var remaining: TimeInterval
}

final class Pomodoro {
    struct Config: Equatable {
        var focus: TimeInterval
        var shortBreak: TimeInterval
        var longBreak: TimeInterval
        var cyclesUntilLong: Int
    }

    /// Config lida na hora de cada fase — mudar em Ajustes vale na próxima fase.
    var configProvider: () -> Config = {
        .init(focus: 25 * 60, shortBreak: 5 * 60, longBreak: 15 * 60, cyclesUntilLong: 4)
    }
    /// Publica o estado (nil = idle). O AppDelegate espelha em vm.pomodoro.
    var onState: ((PomodoroState?) -> Void)?
    /// Fim de fase (fase que acabou, próxima) — AppDelegate notifica + som.
    var onPhaseEnd: ((PomodoroPhase, PomodoroPhase) -> Void)?

    private(set) var phase: PomodoroPhase = .focus
    private(set) var runState: PomodoroRunState = .idle
    private(set) var completedFocusSessions = 0
    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var timer: Timer?

    // MARK: - Ações

    /// Começa um Pomodoro do zero: foco rodando, contador zerado.
    func start() {
        completedFocusSessions = 0
        beginRunning(phase: .focus)
    }

    /// Sai da espera e roda a fase corrente (que já aponta pra próxima).
    func startNext() {
        guard runState == .waiting else { return }
        beginRunning(phase: phase)
    }

    func pause() {
        guard runState == .running, let end = endDate else { return }
        pausedRemaining = max(0, end.timeIntervalSinceNow)
        endDate = nil
        runState = .paused
        stopTimer()
        publish()
    }

    func resume() {
        guard runState == .paused, let rem = pausedRemaining else { return }
        endDate = Date().addingTimeInterval(rem)
        pausedRemaining = nil
        runState = .running
        startTimer()
        publish()
    }

    /// Pular = próxima fase agora, já rodando. Não conta o foco corrente.
    func skip() {
        guard runState != .idle else { return }
        let (next, count) = Pomodoro.advance(
            from: phase, completedFocus: completedFocusSessions,
            cyclesUntilLong: configProvider().cyclesUntilLong, counts: false)
        completedFocusSessions = count
        beginRunning(phase: next)
    }

    func reset() {
        stopTimer()
        runState = .idle
        phase = .focus
        completedFocusSessions = 0
        endDate = nil
        pausedRemaining = nil
        onState?(nil)
    }

    // MARK: - Interno

    private func beginRunning(phase newPhase: PomodoroPhase) {
        phase = newPhase
        endDate = Date().addingTimeInterval(Pomodoro.duration(of: newPhase, config: configProvider()))
        pausedRemaining = nil
        runState = .running
        startTimer()
        publish()
    }

    private func currentRemaining() -> TimeInterval {
        if let end = endDate { return max(0, end.timeIntervalSinceNow) }
        return pausedRemaining ?? 0
    }

    private func startTimer() {
        stopTimer()
        // Timer(...) não auto-agenda; add só uma vez em .common pra tickar durante
        // tracking do menu / interação no notch. scheduledTimer duplicaria o tick.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard runState == .running, let end = endDate else { return }
        if Date() >= end {
            let ended = phase
            let (next, count) = Pomodoro.advance(
                from: ended, completedFocus: completedFocusSessions,
                cyclesUntilLong: configProvider().cyclesUntilLong, counts: true)
            completedFocusSessions = count
            phase = next
            runState = .waiting
            endDate = nil
            stopTimer()
            onPhaseEnd?(ended, next)
            publish()
        } else {
            publish()
        }
    }

    private func publish() {
        let rem: TimeInterval
        switch runState {
        case .idle: onState?(nil); return
        case .waiting: rem = Pomodoro.duration(of: phase, config: configProvider())
        case .paused: rem = pausedRemaining ?? 0
        case .running: rem = currentRemaining()
        }
        onState?(PomodoroState(phase: phase, runState: runState, remaining: rem))
    }
}

extension Pomodoro {
    /// Próxima fase + contador de focos, dado o que acabou. `counts` = true só na
    /// conclusão NATURAL de um foco; skip passa false (não conta, nunca dá pausa longa).
    static func advance(from ended: PomodoroPhase, completedFocus: Int,
                        cyclesUntilLong: Int, counts: Bool) -> (PomodoroPhase, Int) {
        switch ended {
        case .focus:
            let c = counts ? completedFocus + 1 : completedFocus
            let long = counts && c % max(1, cyclesUntilLong) == 0
            return (long ? .longBreak : .shortBreak, c)
        case .shortBreak, .longBreak:
            return (.focus, completedFocus)
        }
    }

    static func duration(of phase: PomodoroPhase, config: Config) -> TimeInterval {
        switch phase {
        case .focus: return config.focus
        case .shortBreak: return config.shortBreak
        case .longBreak: return config.longBreak
        }
    }

    static func selfCheck() {
        // foco natural 1..3 (cyclesUntilLong=4) → pausa curta, contador sobe
        assert(advance(from: .focus, completedFocus: 0, cyclesUntilLong: 4, counts: true) == (.shortBreak, 1))
        assert(advance(from: .focus, completedFocus: 2, cyclesUntilLong: 4, counts: true) == (.shortBreak, 3))
        // 4º foco natural → pausa longa
        assert(advance(from: .focus, completedFocus: 3, cyclesUntilLong: 4, counts: true) == (.longBreak, 4))
        // qualquer pausa → foco, contador intacto
        assert(advance(from: .shortBreak, completedFocus: 4, cyclesUntilLong: 4, counts: true) == (.focus, 4))
        assert(advance(from: .longBreak, completedFocus: 4, cyclesUntilLong: 4, counts: true) == (.focus, 4))
        // skip de um foco NÃO conta e nunca dá pausa longa
        assert(advance(from: .focus, completedFocus: 3, cyclesUntilLong: 4, counts: false) == (.shortBreak, 3))
    }
}

// Entrada do self-check standalone: `swiftc -D POMODORO_SELFCHECK Pomodoro.swift`.
// É uma DECLARAÇÃO (@main), não expressão top-level — assim o arquivo entra como
// biblioteca no build do app e no harness de snapshot (onde o bloco fica fora)
// sem esbarrar em "expressions are not allowed at the top level".
#if POMODORO_SELFCHECK
@main
enum PomodoroSelfCheck {
    static func main() {
        Pomodoro.selfCheck()
        print("pomodoro self-check ok")
    }
}
#endif
