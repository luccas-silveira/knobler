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

        // busy -> waiting dispara um evento; repetir o estado não dispara.
        var w = SessionCompletionWatcher()
        let s = { (st: AgentSession.State) in
            AgentSession(id: "a", name: "p", detail: "", state: st, waitingFor: nil, since: Date())
        }
        _ = w.absorb(["claude": [s(.busy)]])
        check(w.absorb(["claude": [s(.waiting)]]).count == 1, "busy -> waiting avisa")
        check(w.absorb(["claude": [s(.waiting)]]).isEmpty, "waiting repetido não avisa")
        print("agentescheck OK")
    }
}
