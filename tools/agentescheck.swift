// Self-check do backend vendorizado do codenotch (seção Agentes).
// Compila e roda (da raiz do repo) com a linha do `tools/check.sh`.
import Foundation

@main
enum AgentesCheck {
    static func json(_ n: String) -> [String: Any] {
        let d = try! Data(contentsOf: URL(fileURLWithPath: "tools/fixtures/agentes/\(n)"))
        return try! JSONSerialization.jsonObject(with: d) as! [String: Any]
    }

    static func check(_ ok: Bool, _ msg: String) {
        if !ok { print("FALHOU: \(msg)"); exit(1) }
    }

    /// O leitor de transcript guardava caminho, cauda, instante e varredura de
    /// toda sessão que já rodou desde que o app abriu. A leitura do monitor
    /// agora o poda pras sessões ainda registradas — sem mudar o estado das
    /// vivas.
    @MainActor
    static func verificaPodaDosTranscripts() {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agentescheck-\(getpid())")
        defer { try? fm.removeItem(at: base) }
        let sessoes = base.appendingPathComponent("sessions")
        let projetos = base.appendingPathComponent("projects")
        let cwd = "/tmp/agentescheck-proj"
        let pasta = projetos.appendingPathComponent(ClaudeTranscript.projectSlug(forCWD: cwd))
        try! fm.createDirectory(at: sessoes, withIntermediateDirectories: true)
        try! fm.createDirectory(at: pasta, withIntermediateDirectories: true)
        let emCurso = #"{"type":"assistant","message":{"stop_reason":"tool_use"}}"# + "\n"
        for id in ["s-viva", "s-encerrada"] {
            try! Data(emCurso.utf8).write(to: pasta.appendingPathComponent("\(id).jsonl"))
        }
        // só a viva tem registro (pid deste processo, status vazio → transcript)
        let registro = #"{"pid":\#(getpid()),"sessionId":"s-viva","cwd":"\#(cwd)","entrypoint":"cli","status":""}"#
        try! Data(registro.utf8).write(to: sessoes.appendingPathComponent("\(getpid()).json"))

        let leitor = ClaudeTranscriptReader(projects: projetos)
        check(leitor.activity(sessionID: "s-encerrada", cwd: cwd) != nil, "preparo: a encerrada não foi lida")
        _ = leitor.activity(sessionID: "s-sem-transcript", cwd: cwd)  // entra em `scanned`
        check(leitor.sessoesGuardadas == ["s-encerrada", "s-sem-transcript"], "preparo: \(leitor.sessoesGuardadas)")

        let lidas = ClaudeSessionMonitor.read(directory: sessoes, transcripts: leitor)
        check(lidas.count == 1 && lidas.first?.state == .busy, "a sessão viva perdeu o estado do transcript: \(lidas)")
        check(leitor.sessoesGuardadas == ["s-viva"],
              "o leitor guarda sessões que não existem mais: \(leitor.sessoesGuardadas)")
        // o instante da viva sobrevive à poda: a segunda leitura não o reinicia
        let desde = lidas.first?.since
        check(ClaudeSessionMonitor.read(directory: sessoes, transcripts: leitor).first?.since == desde,
              "a poda reiniciou o instante da sessão viva")
    }

    static func main() {
        // Estados do registro do Claude Code.
        check(ClaudeSessionRecord(json: json("claude-busy.json"))?.session.state == .busy, "busy")
        check(ClaudeSessionRecord(json: json("claude-waiting.json"))?.session.state == .waiting, "waiting")
        check(ClaudeSessionRecord(json: json("claude-idle.json"))?.session.state == .idle, "idle")
        let vazio = ClaudeSessionRecord(json: json("claude-empty.json"))
        check(vazio?.session.state == .idle && vazio?.reportsStatus == false, "status vazio vai pro transcript")
        check(ClaudeSessionRecord(json: ["lixo": 1]) == nil, "registro sem pid/cwd")

        // Pid morto some (Review Focus 2).
        check(!ProcessLiveness.isAlive(pid: 999_999, startedAt: nil), "pid morto")
        check(ProcessLiveness.isAlive(pid: getpid(), startedAt: nil), "pid vivo")

        // Codex com plan_type desconhecido e janela nula (Review Focus 3).
        let d = try! Data(contentsOf: URL(fileURLWithPath: "tools/fixtures/agentes/codex-usage.json"))
        let janelas = (try? CodexUsage.windows(from: d)) ?? []
        check(janelas.count == 1, "janela nula descartada sem derrubar a outra")
        check(janelas.first?.usedFraction == 0.42, "42% vira 0.42")
        check((try? CodexUsage.windows(from: Data("lixo".utf8))) == nil, "resposta inválida lança")

        // `/usage` sem hooks: a cada 5 min o app sobe a CLI, e cada subida rodava
        // os hooks globais e de plugin do usuário (escrita em disco na conta do
        // Knobler). O JSON de `--settings` é o valor seguinte à flag, e o
        // `/usage` tem que continuar sendo o último argumento.
        let args = ClaudeUsageCLI.arguments
        check(args.last == "/usage", "/usage é o último argumento")
        for flag in ["--print", "--no-session-persistence", "--strict-mcp-config"] {
            check(args.contains(flag), "\(flag) continua nos argumentos")
        }
        let iSettings = args.firstIndex(of: "--settings")
        check(iSettings.map { $0 + 1 < args.count - 1 } == true, "--settings tem valor antes do /usage")
        let settings = iSettings.flatMap {
            try? JSONSerialization.jsonObject(with: Data(args[$0 + 1].utf8)) as? [String: Any]
        }
        check(settings?["disableAllHooks"] as? Bool == true, "--settings desliga os hooks")
        // Saída real do Claude Code 2.1.314 com esses argumentos (rodapé encurtado).
        let usage = try! String(contentsOf: URL(fileURLWithPath: "tools/fixtures/agentes/claude-usage.txt"),
                                encoding: .utf8)
        let lidas = (try? ClaudeUsageCLI.parse(usage)) ?? []
        check(lidas.map(\.id) == ["session", "weekly_all", "weekly_fable"], "janelas do /usage: \(lidas.map(\.id))")
        check(lidas.first?.usedFraction == 0.06, "sessão 6% vira 0.06")
        check(lidas.allSatisfy { $0.resetsAt != nil }, "horário de reset lido nas três janelas")

        // busy -> waiting dispara um evento; repetir o estado não dispara.
        var w = SessionCompletionWatcher()
        let s = { (st: AgentSession.State) in
            AgentSession(id: "a", name: "p", detail: "", state: st, waitingFor: nil, since: Date())
        }
        _ = w.absorb(["claude": [s(.busy)]])
        check(w.absorb(["claude": [s(.waiting)]]).count == 1, "busy -> waiting avisa")
        check(w.absorb(["claude": [s(.waiting)]]).isEmpty, "waiting repetido não avisa")
        verificaPodaDosTranscripts()
        print("agentescheck OK")
    }
}
