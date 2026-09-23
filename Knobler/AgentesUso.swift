//
//  AgentesUso.swift
//  Knobler
//
//  Sessões e limites de plano de Claude Code e Codex, vindos do backend do
//  codenotch (`Vendor/Codenotch`). Um só pra todas as telas: é ele quem decide
//  quando uma sessão "terminou" ou "está esperando você", e isso não pode
//  acontecer uma vez por monitor.
//

import AppKit
import Combine

@MainActor
final class AgentesUso: ObservableObject {
    static let shared = AgentesUso()

    /// Todas as sessões vivas, por prioridade: esperando você, trabalhando,
    /// concluída, ociosa. Dentro do mesmo estado, a mais recente primeiro.
    @Published private(set) var sessoes: [AgentSession] = []
    /// Última leitura de cada provider ("claude", "codex").
    @Published private(set) var uso: [String: ProviderSnapshot] = [:]
    /// Quando cada leitura de `uso` chegou. Falha de rede mantém a leitura
    /// anterior, e é por aqui que a UI sabe que ela envelheceu.
    @Published private(set) var lidoEm: [String: Date] = [:]
    /// Uma vez por transição, independente de quantas telas existem.
    var onEvento: ((SessionCompletionWatcher.Event) -> Void)?

    private let claudeMonitor = ClaudeSessionMonitor(
        directory: ClaudeProfile.default().sessionsDirectory,
        projects: ClaudeProfile.default().projectsDirectory)
    private lazy var coordinator = ActivityCoordinator(monitors: [
        "claude": claudeMonitor,
        "codex": CodexActivityMonitor(),
    ]) { [weak self] id, sessoes in self?.receber(id, sessoes) }
    private let codex = CodexLocalProvider()
    /// Só nasce com o interruptor ligado: criar já não toca o Keychain, mas
    /// assim nem a tentação existe.
    private var claude: ClaudeOAuthProvider?
    private var refresher: ClaudeTokenRefresher?
    private var porFonte: [String: [AgentSession]] = [:]
    private var watcher = SessionCompletionWatcher()
    private var bag = Set<AnyCancellable>()
    private var timer: Timer?

    func iniciar() {
        guard timer == nil else { return }
        // A sondagem de `/usage` e a renovação do token rodam o próprio Claude
        // Code, que registra uma sessão por um segundo. Sem isso ela aparecia
        // como trabalho e era anunciada como concluída.
        claudeMonitor.ignoredWorkingDirectories = [ClaudeUsageCLI.scratchLocation().path]
        claudeMonitor.ignoredPIDs = { [weak self] in
            var pids = ClaudeUsageCLI.runningPIDs
            if let pid = MainActor.assumeIsolated({ self?.refresher?.launchedPID }) { pids.insert(pid) }
            return pids
        }
        coordinator.setEnabled(["claude", "codex"])

        AppSettings.shared.$agentesClaudeUso
            .removeDuplicates()
            .sink { [weak self] ligado in self?.claudeUso(ligado) }
            .store(in: &bag)
        // ponytail: poll fixo de 60 s, como o UsageStore do codenotch; o backoff
        // de 429 fica por conta de cada provider.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.atualizarUso() }
        }
        Task { await atualizarUso() }
    }

    func focar(_ sessao: AgentSession) {
        guard let pid = sessao.processID else { return }
        Task { _ = await SessionFocus.focus(pid: pid) }
    }

    private func claudeUso(_ ligado: Bool) {
        if ligado {
            guard claude == nil else { return }
            let provider = ClaudeOAuthProvider()
            claude = provider
            let refresher = ClaudeTokenRefresher(
                expiry: { await provider.tokenExpiry },
                reload: { await provider.reloadTokenExpiry() })
            refresher.start()
            self.refresher = refresher
            Task { await atualizarUso() }
        } else {
            refresher?.stop()
            refresher = nil
            claude = nil
            uso["claude"] = nil
        }
    }

    private func receber(_ id: String, _ sessoes: [AgentSession]) {
        porFonte[id] = sessoes
        for evento in watcher.absorb(porFonte).prefix(1) { onEvento?(evento) }
        self.sessoes = Self.ordenar(porFonte.values.flatMap { $0 })
    }

    nonisolated static func ordenar(_ s: [AgentSession]) -> [AgentSession] {
        let ordem: [AgentSession.State] = [.waiting, .busy, .success, .idle]
        return s.sorted {
            let a = ordem.firstIndex(of: $0.state)!, b = ordem.firstIndex(of: $1.state)!
            return a != b ? a < b : $0.since > $1.since
        }
    }

    private func atualizarUso() async {
        if let s = try? await codex.fetchSnapshot() { uso["codex"] = s; lidoEm["codex"] = Date() }
        guard let claude, AppSettings.shared.agentesClaudeUso else { return }
        if let s = try? await claude.fetchSnapshot(), self.claude === claude {
            uso["claude"] = s; lidoEm["claude"] = Date()
        }
    }

    /// Só pro harness de snapshot. Fora de `#if DEBUG` porque o `snapshot.sh`
    /// compila com `-O` sem a flag.
    func injetar(sessoes: [AgentSession], uso: [String: ProviderSnapshot],
                 lidoEm: [String: Date] = [:]) {
        self.sessoes = Self.ordenar(sessoes)
        self.uso = uso
        self.lidoEm = lidoEm
    }
}
