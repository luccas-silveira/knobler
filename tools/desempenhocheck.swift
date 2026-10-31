// Gate do registro de desempenho (Knobler/Desempenho.swift).
//
// Trava o formato da linha, a conta do cpu_pct, a poda com folga de 10% (que
// é o que mantém a gravação comum um append, sem reescrever o arquivo) e uma
// leitura real do próprio processo.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/Desempenho.swift tools/desempenhocheck.swift \
//     -o /tmp/desempenhocheck && /tmp/desempenhocheck

import Foundation

private func exigir(_ cond: Bool, _ msg: String) {
    if !cond {
        print("FALHOU: \(msg)")
        exit(1)
    }
}

private func linhas(_ url: URL) -> [String] {
    ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        .split(separator: "\n").map(String.init)
}

private func inode(_ url: URL) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? Int
}

private func amostra(_ n: Int) -> AmostraDeDesempenho {
    AmostraDeDesempenho(data: "2026-10-30T21:00:00-03:00", versao: "0.36.0", pid: 123,
                        uptimeS: n, footprintMB: 48.3, residenteMB: 60.1, cpuS: 12.5,
                        cpuPct: 1.25, threads: 17, notches: 2, displays: 2, janelas: 3)
}

@main
enum Gate {
    @MainActor
    static func main() {
        // 1. Formato da linha: chaves fixas, em ordem, números sem ruído de float.
        let esperada = #"{"cpu_pct":1.25,"cpu_s":12.5,"data":"2026-10-30T21:00:00-03:00","displays":2,"footprint_mb":48.3,"janelas":3,"notches":2,"pid":123,"residente_mb":60.1,"threads":17,"uptime_s":300,"versao":"0.36.0"}"#
        exigir(amostra(300).linha == esperada, "linha fora do formato: \(amostra(300).linha)")
        let json = amostra(300).json
        exigir(Set(json.keys) == ["data", "versao", "pid", "uptime_s", "footprint_mb", "residente_mb",
                                  "cpu_s", "cpu_pct", "threads", "notches", "displays", "janelas"],
               "o /status não recebe as 12 chaves: \(json.keys.sorted())")
        exigir((json["footprint_mb"] as? Double) == 48.3, "footprint_mb não volta como número")
        let decodificada = try? JSONDecoder().decode(AmostraDeDesempenho.self, from: Data(esperada.utf8))
        exigir(decodificada == amostra(300), "a linha não volta pra mesma amostra")

        // 2. cpu_pct: % de um núcleo no intervalo.
        exigir(Desempenho.cpuPct(cpuAtual: 30, cpuAnterior: 0, segundos: 300) == 10,
               "30 s de CPU em 300 s não deu 10%")
        exigir(Desempenho.cpuPct(cpuAtual: 600, cpuAnterior: 0, segundos: 300) == 200,
               "dois núcleos cheios não deram 200%")
        exigir(Desempenho.cpuPct(cpuAtual: 10.9, cpuAnterior: 10, segundos: 300) == 0.3,
               "0,9 s em 300 s não arredondou pra 0,3%")
        exigir(Desempenho.cpuPct(cpuAtual: 5, cpuAnterior: 1, segundos: 0) == 0,
               "intervalo nulo não deu 0")
        exigir(Desempenho.cpuPct(cpuAtual: 1, cpuAnterior: 5, segundos: 300) == 0,
               "contador pra trás não deu 0")
        exigir(Desempenho.megabytes(50_646_221) == 48.3, "bytes → MB com uma casa")

        // 3. Teto: 7 dias a cada 5 min, poda só ao passar 10%.
        exigir(Desempenho.teto == 2016, "teto não é 7 dias de amostras de 5 min")
        exigir(Desempenho.limiteDePoda(teto: 2016) == 2217, "folga de 10% errada")
        exigir(Desempenho.limiteDePoda(teto: 5) == 6, "teto pequeno ficou sem folga")
        exigir(Desempenho.podar(["a", "b", "c"], teto: 2) == ["b", "c"], "poda não guardou as últimas")

        // 4. O arquivo: append comum, poda ao passar do limite.
        let pasta = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("desempenhocheck-\(getpid())", isDirectory: true)
        try? FileManager.default.removeItem(at: pasta)
        defer { try? FileManager.default.removeItem(at: pasta) }

        let registro = RegistroDeDesempenho(pasta: pasta, teto: 20)
        exigir(registro.arquivo.lastPathComponent == "desempenho.jsonl", "nome do arquivo")
        registro.gravar(amostra(1))
        registro.esperar()
        let inodeInicial = inode(registro.arquivo)
        exigir(inodeInicial != nil, "a primeira amostra não criou o arquivo")
        for n in 2...22 { registro.gravar(amostra(n)) }
        registro.esperar()
        exigir(linhas(registro.arquivo).count == 22, "22 linhas (no limite) não ficaram todas")
        exigir(registro.podas == 0, "podou antes de passar do limite")
        exigir(inode(registro.arquivo) == inodeInicial,
               "o arquivo foi reescrito sem poda (append virou reescrita)")

        registro.gravar(amostra(23))
        registro.esperar()
        var atuais = linhas(registro.arquivo)
        exigir(registro.podas == 1, "passou do limite e não podou")
        exigir(atuais.count == 20, "a poda não voltou ao teto: \(atuais.count)")
        exigir(atuais.first == amostra(4).linha, "a poda não descartou as mais antigas")
        exigir(atuais.last == amostra(23).linha, "a poda perdeu a mais nova")

        for n in 24...25 { registro.gravar(amostra(n)) }
        registro.esperar()
        exigir(linhas(registro.arquivo).count == 22 && registro.podas == 1,
               "depois da poda a gravação voltou a reescrever")

        // Um processo novo herda o arquivo: conta as linhas uma vez e segue.
        let reaberto = RegistroDeDesempenho(pasta: pasta, teto: 20)
        reaberto.gravar(amostra(26))
        reaberto.esperar()
        atuais = linhas(reaberto.arquivo)
        exigir(reaberto.podas == 1 && atuais.count == 20, "não contou as linhas herdadas")
        exigir(atuais.last == amostra(26).linha, "a herança perdeu a amostra nova")

        // Apagado com o app aberto: recria em vez de falhar.
        try? FileManager.default.removeItem(at: reaberto.arquivo)
        reaberto.gravar(amostra(27))
        reaberto.esperar()
        exigir(linhas(reaberto.arquivo) == [amostra(27).linha], "não recriou o arquivo apagado")

        // Sem bundle id (este harness) o padrão não é o Application Support do usuário.
        let padrao = RegistroDeDesempenho()
        exigir(!padrao.arquivo.path.contains("Application Support"),
               "o harness apontou pro arquivo do usuário: \(padrao.arquivo.path)")

        // 5. Leitura real do processo.
        guard let leitura = LeituraDoProcesso.agora() else {
            exigir(false, "task_info falhou")
            return
        }
        exigir(leitura.footprint > 1_000_000, "footprint implausível: \(leitura.footprint)")
        exigir(leitura.residente > 1_000_000, "residente implausível: \(leitura.residente)")
        exigir(leitura.threads >= 1, "nenhuma thread")
        exigir(leitura.cpuS > 0, "CPU acumulada zerada")
        exigir(leitura.inicio.map { $0 <= Date() && Date().timeIntervalSince($0) < 3600 } == true,
               "início do processo implausível: \(String(describing: leitura.inicio))")

        // 6. O monitor ponta a ponta: contexto entra na linha, cpu_pct mede o intervalo.
        let pastaMonitor = pasta.appendingPathComponent("monitor", isDirectory: true)
        let registroMonitor = RegistroDeDesempenho(pasta: pastaMonitor)
        let monitor = MonitorDeDesempenho(registro: registroMonitor)
        monitor.contexto = { .init(notches: 2, displays: 3, janelas: 4) }
        exigir(monitor.amostrar() != nil, "primeira amostra falhou")
        let fim = Date().addingTimeInterval(0.3)
        var lixo = 0.0
        while Date() < fim { lixo += sin(lixo + 1) }   // queima CPU pro intervalo
        guard let segunda = monitor.amostrar() else {
            exigir(false, "segunda amostra falhou")
            return
        }
        exigir(lixo.isFinite, "a queima de CPU virou NaN")
        exigir(monitor.ultima == segunda, "última amostra não ficou guardada")
        exigir(segunda.notches == 2 && segunda.displays == 3 && segunda.janelas == 4,
               "o contexto do app não entrou na amostra")
        exigir(segunda.cpuPct > 30, "0,3 s queimando CPU deu só \(segunda.cpuPct)%")
        exigir(segunda.versao == "dev", "sem Info.plist a versão devia ser dev")
        exigir(segunda.pid == getpid(), "pid errado")
        exigir(ISO8601DateFormatter().date(from: segunda.data) != nil, "data não é ISO 8601: \(segunda.data)")
        registroMonitor.esperar()
        let gravadas = linhas(registroMonitor.arquivo)
        exigir(gravadas.count == 2, "o monitor não gravou as duas amostras: \(gravadas.count)")

        print("desempenhocheck: ok")
    }
}
