//
//  InstanciaUnicaPartida.swift
//  Knobler
//
//  Os efeitos da regra "a instância mais nova vence" (a decisão é pura, em
//  InstanciaUnica.swift). Roda no `KnoblerMain.main()` logo depois do
//  `NSApplication.shared` e ANTES de o `AppDelegate` nascer — ou seja, antes de
//  qualquer serviço, janela de notch, porta 4477 ou token de agente existir.
//
//  Casos pensados (não mude a ordem do `main()` sem relê-los):
//
//  • Modos headless (`--download-model` do postflight do cask, `--selfcheck`
//    do tools/check.sh, `--permissoes` do suporte) saem ANTES desta guarda: são
//    processos de linha de comando que convivem com o app aberto. Se a guarda
//    viesse antes, rodar o check.sh derrubaria o Knobler de quem roda. E como
//    não sobem `NSApplication`, não fazem check-in no LaunchServices: a lista
//    abaixo não os vê, e um app aberto durante o download do modelo não o mata
//    (tools/instancia-e2e.sh, passo 6).
//  • Sem bundle id (harness compilado com swiftc, binário solto): não há com
//    quem comparar — a guarda não faz nada.
//  • `Updater.relaunch()`: o shell espera o PID antigo MORRER (com `kill -9` em
//    ~10 s) e só então faz `open -a`. A instância nova sobe sozinha; esta guarda
//    só vê, no máximo, a antiga já marcada como encerrada.
//  • `brew upgrade` (pelo Updater ou no Terminal): troca o bundle sem fechar o
//    app; o postflight roda `--download-model` (headless, acima). Se alguém
//    abrir o app novo com o velho ainda vivo, o novo derruba o velho — é a
//    atualização terminando de acontecer.
//  • Login Item (`SMAppService.mainApp`): sobe uma vez no login. Se o usuário
//    abrir outra cópia depois (ex.: build de desenvolvimento), a nova vence.
//  • `applicationShouldTerminate` da instância antiga: com o Descanso em curso
//    ela RECUSA o quit (o quiosque não pode ser furado por ⌘Q); fora isso ela
//    sempre ADIA até o `Monitores` restaurar o gamma. Damos `esperaPeloQuit` pra ela
//    sair por conta própria; depois disso vem o `forceTerminate()`. O quiosque
//    some junto (abrir o app de novo é um pedido explícito do usuário), mas o
//    que só o quit normal faz fica pra trás: a restauração do gamma de monitor
//    escurecido (o mesmo risco do `kill -9` de segurança do `Updater.relaunch()`)
//    e o que o `applicationWillTerminate` gravaria (texto da nota rápida no
//    clipboard, debounce do histórico). Gravação de ditado em curso não veta o
//    quit: a antiga sai pelo caminho normal e o áudio dela se perde.
//  • Dois lançamentos quase simultâneos: cada um faz check-in no LaunchServices
//    (`NSApplication.shared`) ANTES de listar, então ao menos um vê o outro, e a
//    ordem de `InstanciaUnica.ehMaisNova` é a mesma dos dois lados.
//

import AppKit
import os

extension InstanciaUnica {
    private static let log = Logger(subsystem: "com.zoi.knobler", category: "instancia")

    /// Quanto a antiga tem pra sair pelo quit normal (inclui o adiamento do
    /// `applicationShouldTerminate`, que restaura os monitores).
    static let esperaPeloQuit: TimeInterval = 5
    /// Quanto o `forceTerminate()` tem pra fazer efeito antes de desistirmos.
    static let esperaPeloKill: TimeInterval = 2

    /// Garante que, ao voltar, esta é a única instância viva com este bundle id
    /// — ou não volta (`exit(0)`) quando existe uma mais nova.
    @MainActor
    static func garantir(bundleID: String? = Bundle.main.bundleIdentifier) {
        guard let bundleID else { return }
        let meuPID = ProcessInfo.processInfo.processIdentifier
        let eu = InstanciaVista(pid: meuPID, inicio: inicio(de: meuPID), encerrada: false)

        // ponytail: três rodadas cobrem a antiga que sumiu da lista atrasada e
        // uma terceira cópia que faz check-in enquanto esperamos; um processo
        // que nem o SIGKILL tira não tem o que fazer além de registrar e seguir.
        for _ in 0..<3 {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            let outras = apps.map { app in
                InstanciaVista(pid: app.processIdentifier,
                               inicio: inicio(de: app.processIdentifier) ?? app.launchDate,
                               encerrada: app.isTerminated || !estaVivo(app.processIdentifier))
            }
            switch decidir(eu: eu, outras: outras) {
            case .seguir:
                return
            case .sair(let maisNova):
                log.notice("instância mais nova (pid \(maisNova)) já está subindo; esta (pid \(meuPID)) sai sem montar nada")
                exit(0)
            case .encerrar(let pids):
                let alvos = apps.filter { pids.contains($0.processIdentifier) }
                log.notice("encerrando instância anterior (pid \(pids.map(String.init).joined(separator: ", "), privacy: .public))")
                // quit normal (Apple Event): passa pelo applicationShouldTerminate
                // e pelo applicationWillTerminate da antiga
                alvos.forEach { _ = $0.terminate() }
                let teimosas = esperar(pids, por: esperaPeloQuit)
                guard !teimosas.isEmpty else { continue }
                log.error("instância anterior não saiu em \(Int(esperaPeloQuit)) s (pid \(teimosas.map(String.init).joined(separator: ", "), privacy: .public)); forçando")
                for app in alvos where teimosas.contains(app.processIdentifier) {
                    if !app.forceTerminate() { kill(app.processIdentifier, SIGKILL) }
                }
                let sobreviventes = esperar(teimosas, por: esperaPeloKill)
                if !sobreviventes.isEmpty {
                    log.fault("instância anterior sobreviveu ao forceTerminate (pid \(sobreviventes.map(String.init).joined(separator: ", "), privacy: .public))")
                }
            }
        }
        log.error("três rodadas de encerramento sem a lista ficar limpa; seguindo a partida assim mesmo")
    }

    /// Os `pids` que ainda existem depois de até `limite` segundos.
    /// ponytail: polling de 50 ms com `kill(pid, 0)` em vez do KVO de
    /// `isTerminated` — o KVO só anda com o run loop principal girando, e aqui o
    /// `NSApp.run()` ainda nem começou.
    private static func esperar(_ pids: [pid_t], por limite: TimeInterval) -> [pid_t] {
        let prazo = Date().addingTimeInterval(limite)
        var vivos = pids.filter(estaVivo)
        while !vivos.isEmpty, Date() < prazo {
            usleep(50_000)
            vivos = vivos.filter(estaVivo)
        }
        return vivos
    }

    /// O processo existe? `EPERM` = existe, mas é de outro usuário.
    static func estaVivo(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Início do processo segundo o kernel. `nil` se o PID não existe mais.
    static func inicio(de pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var tamanho = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &tamanho, nil, 0) == 0, tamanho > 0 else {
            return nil
        }
        let t = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000)
    }
}
