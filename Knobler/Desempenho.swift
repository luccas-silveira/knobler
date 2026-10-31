//
//  Desempenho.swift
//  Knobler
//
//  Registro de desempenho: uma amostra no lançamento e outra a cada 5 min,
//  uma linha JSON por amostra em Application Support. Nasceu porque a memória
//  dobrou em 36 h (48 → 102 MB) e, sem histórico, não dava pra dizer se era
//  vazamento ou cache. A curva responde: cache sobe e estabiliza, vazamento
//  sobe em rampa — e `notches`/`displays`/`janelas` ao lado mostram se a rampa
//  acompanha troca de monitor.
//
//  Custo: três syscalls e um `write` de ~250 bytes a cada 5 min. O arquivo
//  guarda 7 dias (2016 amostras) e só é reescrito pra podar quando passa 10%
//  do teto — uma vez a cada ~17 h, não a cada amostra.
//

import Foundation
import Darwin
import os

/// Constantes e contas puras do registro. Tudo aqui é coberto pelo
/// `tools/desempenhocheck.swift`.
enum Desempenho {
    /// Entre uma amostra e outra.
    static let intervalo: TimeInterval = 5 * 60
    /// 7 dias de amostras a cada 5 min.
    static let teto = 7 * 24 * 60 * 60 / Int(intervalo)

    /// A partir de quantas linhas o arquivo é podado de volta ao `teto`. A
    /// folga de 10% é o que deixa a gravação comum ser só um append.
    static func limiteDePoda(teto: Int) -> Int { teto + max(1, teto / 10) }

    /// As últimas `teto` linhas — o que sobrevive à poda.
    static func podar<S: StringProtocol>(_ linhas: [S], teto: Int) -> [S] {
        Array(linhas.suffix(max(0, teto)))
    }

    /// CPU no intervalo, em % de um núcleo (o mesmo do `top`: 100 = um núcleo
    /// cheio o intervalo inteiro; passa de 100 com mais de um núcleo). Intervalo
    /// nulo ou contador que andou pra trás dão 0 em vez de lixo.
    static func cpuPct(cpuAtual: Double, cpuAnterior: Double, segundos: Double) -> Double {
        guard segundos > 0, cpuAtual >= cpuAnterior else { return 0 }
        return arredondar((cpuAtual - cpuAnterior) / segundos * 100, casas: 2)
    }

    static func megabytes(_ bytes: UInt64) -> Double {
        arredondar(Double(bytes) / 1_048_576, casas: 1)
    }

    static func arredondar(_ valor: Double, casas: Int) -> Double {
        let fator = pow(10, Double(casas))
        return (valor * fator).rounded() / fator
    }
}

/// Uma amostra. Os nomes das chaves são o formato do arquivo e do `/status`:
/// mudar um deles quebra quem já lê o histórico.
struct AmostraDeDesempenho: Codable, Equatable {
    /// ISO 8601, com fuso.
    var data: String
    var versao: String
    var pid: Int32
    /// Tempo de relógio desde que o processo nasceu (inclui o Mac dormindo).
    var uptimeS: Int
    /// `phys_footprint` — o número do Monitor de Atividade e do `footprint`.
    var footprintMB: Double
    var residenteMB: Double
    /// CPU acumulada (usuário + sistema) desde o lançamento.
    var cpuS: Double
    /// CPU desde a amostra anterior (na primeira, desde o lançamento).
    var cpuPct: Double
    var threads: Int
    /// Notches vivos (um por monitor) no instante da amostra.
    var notches: Int
    /// Monitores que o macOS reporta. Divergir de `notches` é sintoma.
    var displays: Int
    /// Janelas do app (`NSApp.windows`) — sobe se alguma não for liberada.
    var janelas: Int

    enum CodingKeys: String, CodingKey {
        case data, versao, pid, threads, notches, displays, janelas
        case uptimeS = "uptime_s"
        case footprintMB = "footprint_mb"
        case residenteMB = "residente_mb"
        case cpuS = "cpu_s"
        case cpuPct = "cpu_pct"
    }

    /// A linha do `desempenho.jsonl`: JSON compacto, chaves em ordem.
    var linha: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let dados = try? encoder.encode(self),
              let texto = String(data: dados, encoding: .utf8) else { return "{}" }
        return texto
    }

    /// Pro `GET /status`, que monta a resposta com `JSONSerialization`.
    var json: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(linha.utf8))) as? [String: Any] ?? [:]
    }
}

/// O que o kernel diz do próprio processo agora.
struct LeituraDoProcesso {
    var footprint: UInt64
    var residente: UInt64
    var cpuS: Double
    var threads: Int
    /// Quando o processo nasceu, pelo kernel. `nil` se a consulta falhar.
    var inicio: Date?

    static func agora() -> LeituraDoProcesso? {
        var vm = task_vm_info_data_t()
        var tamanho = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(tamanho)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &tamanho)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        // `getrusage` soma todas as threads, vivas e mortas — o `task_info`
        // básico só conta as que já terminaram.
        var uso = rusage()
        getrusage(RUSAGE_SELF, &uso)
        func segundos(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }

        // `proc_pidinfo` em vez de `task_threads`: este devolve um direito de
        // porta por thread, que teria de ser liberado um a um.
        let pid = getpid()
        var tarefa = proc_taskinfo()
        let tamanhoTarefa = Int32(MemoryLayout<proc_taskinfo>.size)
        let threads = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &tarefa, tamanhoTarefa) == tamanhoTarefa
            ? Int(tarefa.pti_threadnum) : 0

        var bsd = proc_bsdinfo()
        let tamanhoBSD = Int32(MemoryLayout<proc_bsdinfo>.size)
        let inicio: Date? = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, tamanhoBSD) == tamanhoBSD
            ? Date(timeIntervalSince1970: Double(bsd.pbi_start_tvsec) + Double(bsd.pbi_start_tvusec) / 1_000_000)
            : nil

        return LeituraDoProcesso(footprint: vm.phys_footprint, residente: vm.resident_size,
                                 cpuS: segundos(uso.ru_utime) + segundos(uso.ru_stime),
                                 threads: threads, inicio: inicio)
    }
}

/// O arquivo. Append comum; poda (reescrita atômica) só ao passar do
/// `limiteDePoda`. Tudo numa fila serial própria — a main nunca toca o disco.
final class RegistroDeDesempenho: @unchecked Sendable {
    static let shared = RegistroDeDesempenho()

    let arquivo: URL
    let teto: Int
    private let fila = DispatchQueue(label: "com.zoi.knobler.desempenho", qos: .utility)
    private let log = Logger(subsystem: "com.zoi.knobler", category: "desempenho")
    /// Linhas no arquivo. `nil` = ainda não contou (só a primeira gravação lê
    /// o arquivo inteiro; as seguintes só somam).
    private var linhas: Int?
    private var podasFeitas = 0

    /// `pasta` existe pro gate escrever em `/tmp`. Sem bundle id não é o app —
    /// é um harness, e ele não pode sujar o arquivo do usuário (mesma regra do
    /// `RegistroDeProvas`, CorteDoKnob.swift).
    init(pasta: URL? = nil, teto: Int = Desempenho.teto) {
        let base: URL
        if let pasta {
            base = pasta
        } else if Bundle.main.bundleIdentifier == nil {
            base = URL(fileURLWithPath: NSTemporaryDirectory())
        } else {
            base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Knobler", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        arquivo = base.appendingPathComponent("desempenho.jsonl")
        self.teto = teto
    }

    func gravar(_ amostra: AmostraDeDesempenho) {
        let linha = amostra.linha
        fila.async { [self] in anexar(linha) }
    }

    /// Quantas vezes o arquivo foi reescrito pela poda. Espera a fila — é pro gate.
    var podas: Int { fila.sync { podasFeitas } }

    /// Bloqueia até as gravações pendentes terminarem. Só pro gate.
    func esperar() { fila.sync {} }

    private func anexar(_ linha: String) {
        let dados = Data((linha + "\n").utf8)
        var total: Int
        if let handle = try? FileHandle(forWritingTo: arquivo) {
            total = (linhas ?? contarLinhas()) + 1
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: dados)
            } catch {
                log.error("desempenho: falha ao anexar: \(error.localizedDescription, privacy: .public)")
            }
            try? handle.close()
        } else {
            // primeiro uso, ou alguém apagou o arquivo com o app aberto
            do {
                try dados.write(to: arquivo, options: .atomic)
            } catch {
                log.error("desempenho: falha ao criar o arquivo: \(error.localizedDescription, privacy: .public)")
            }
            total = 1
        }
        if total > Desempenho.limiteDePoda(teto: teto) { total = podar() }
        linhas = total
    }

    private func contarLinhas() -> Int {
        guard let dados = try? Data(contentsOf: arquivo) else { return 0 }
        return dados.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    /// Reescreve com as últimas `teto` linhas. Devolve quantas ficaram.
    private func podar() -> Int {
        guard let texto = try? String(contentsOf: arquivo, encoding: .utf8) else { return 0 }
        let mantidas = Desempenho.podar(texto.split(separator: "\n"), teto: teto)
        do {
            try (mantidas.joined(separator: "\n") + "\n")
                .write(to: arquivo, atomically: true, encoding: .utf8)
        } catch {
            log.error("desempenho: falha ao podar: \(error.localizedDescription, privacy: .public)")
            return mantidas.count
        }
        podasFeitas += 1
        return mantidas.count
    }
}

/// Quem amostra: no lançamento e a cada `Desempenho.intervalo`. Guarda a
/// última amostra pro `GET /status`.
@MainActor
final class MonitorDeDesempenho {
    struct Contexto {
        var notches = 0
        var displays = 0
        var janelas = 0
    }

    private(set) var ultima: AmostraDeDesempenho?
    /// O que o app sabe e o processo não: notches, monitores, janelas. Lido
    /// na main a cada amostra.
    var contexto: () -> Contexto = { Contexto() }

    private let registro: RegistroDeDesempenho
    private let log = Logger(subsystem: "com.zoi.knobler", category: "desempenho")
    private var timer: Timer?
    /// CPU e tempo acordado da amostra anterior. O intervalo do `cpu_pct` é
    /// medido em `systemUptime`, que para com o Mac dormindo — senão uma
    /// noite de sono diluiria o pico da manhã num 0,0%.
    private var anterior: (cpuS: Double, acordado: TimeInterval)?
    /// Fallback se o kernel não disser quando o processo nasceu.
    private let criadoEm = Date()
    private static let formatoData: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    init(registro: RegistroDeDesempenho = .shared) { self.registro = registro }

    func iniciar() {
        guard timer == nil else { return }
        amostrar()
        let t = Timer(timeInterval: Desempenho.intervalo, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.amostrar() }
        }
        // ninguém precisa da amostra no segundo exato; deixa o sistema agrupar
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func parar() {
        timer?.invalidate()
        timer = nil
    }

    @discardableResult
    func amostrar(agora: Date = Date()) -> AmostraDeDesempenho? {
        guard let leitura = LeituraDoProcesso.agora() else {
            log.error("desempenho: task_info falhou; amostra pulada")
            return nil
        }
        let acordado = ProcessInfo.processInfo.systemUptime
        let uptime = max(0, agora.timeIntervalSince(leitura.inicio ?? criadoEm))
        // primeira amostra: desde o lançamento, quando ainda não houve sono
        let base = anterior ?? (cpuS: 0, acordado: acordado - uptime)
        let ctx = contexto()
        let amostra = AmostraDeDesempenho(
            data: Self.formatoData.string(from: agora),
            versao: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            pid: getpid(),
            uptimeS: Int(uptime.rounded()),
            footprintMB: Desempenho.megabytes(leitura.footprint),
            residenteMB: Desempenho.megabytes(leitura.residente),
            cpuS: Desempenho.arredondar(leitura.cpuS, casas: 2),
            cpuPct: Desempenho.cpuPct(cpuAtual: leitura.cpuS, cpuAnterior: base.cpuS,
                                      segundos: acordado - base.acordado),
            threads: leitura.threads,
            notches: ctx.notches, displays: ctx.displays, janelas: ctx.janelas)
        anterior = (leitura.cpuS, acordado)
        ultima = amostra
        registro.gravar(amostra)
        log.info("\(amostra.linha, privacy: .public)")
        return amostra
    }
}
