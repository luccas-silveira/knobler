//
//  CorteDoKnob.swift
//  Knobler
//
//  Registro passivo de desvios da moldura e do host em relação ao topo.
//  A apresentação tem identidade estável: nenhuma prova reconstrói views.
//  Altura animada entra apenas como contexto, nunca como violação.
//
//  Só vira prova o desvio que alguém poderia ver: moldura com área, janela
//  visível e desvio que sobrevive à `CorteDoKnob.espera`, contada também a
//  partir da última reconfiguração de tela. O `setFrame` do AppKit roda uma
//  passada de layout com a janela já no tamanho novo e o host ainda no velho
//  (0×0 quando o host acabou de ser pendurado); a passada seguinte, no mesmo
//  giro, acerta. Eram 48 de 48 linhas do `corte-do-knob.jsonl` até 30/10.
//  Quando um corte gravado some, a cura vira linha também (`curou: true`).

import AppKit
import Combine
import SwiftUI
import os

enum CorteDoKnob {
    /// Espaço de coordenadas plantado na raiz da `NotchView`. O topo dele é o
    /// "onde deveria estar" do invariante.
    static let espacoRaiz = "corte-do-knob-raiz"

    /// Tolerância da lacuna, em pontos. Vem do harness: lá são 4 px de bitmap
    /// a escala 2 (`tools/cortecheck/main.swift`, `toleranciaPx`), e o menor
    /// salto de altura real da Lista 3 da medição 002 é 22 pt — folga de
    /// ordem de grandeza entre o ruído absorvido e o defeito procurado.
    static let toleranciaPt: CGFloat = 2

    /// A métrica. Positiva = falta o topo (o corte); negativa = a moldura
    /// subiu acima da raiz.
    static func lacunaDeTopo(molduraMinY: CGFloat) -> CGFloat { molduraMinY }

    static func viola(lacuna: CGFloat) -> Bool {
        !lacuna.isFinite || abs(lacuna) > toleranciaPt
    }

    /// Moldura sem área não foi medida: é o host recém-pendurado na janela
    /// (0×0, com a janela já do tamanho da tela — a lacuna sai igual à altura
    /// dela) ou nada desenhado. Não há o que cortar.
    static func medida(_ moldura: CGRect) -> Bool {
        !moldura.isNull && moldura.width > 0 && moldura.height > 0
    }

    /// Quanto um desvio precisa durar pra virar prova, em segundos — contado
    /// do instante em que apareceu ou da última reconfiguração de tela, o que
    /// vier depois. O defeito procurado persiste até um expandir/recolher;
    /// o desvio de passagem do `setFrame` some na passada seguinte.
    static let espera: TimeInterval = 1
}

/// O retrato do instante em que o invariante quebrou (ou voltou a valer, na
/// cura). Montado só quando um desvio aparece ou cura — no caminho normal nada
/// disto é construído (ver o `@autoclosure` do `VigiaDoCorte.avaliar`).
struct ContextoDoCorte {
    var mode: String
    var foco: String?
    /// Altura que o layout pediu (`currentSize.height`).
    var alturaEsperada: Double
    /// Última transição de seção registrada no VM, e há quantos segundos.
    var ultimoEvento: String?
    /// Alguma coisa estava animando? Aproximação medida: a altura desenhada
    /// diverge da pedida, que é o que a mola do morph faz enquanto corre.
    var animando: Bool
    var displayID: UInt32
    var notchReal: Bool
}

struct ProvaDoCorte {
    var data: Date
    var lacunaPt: Double
    var moldura: CGRect
    var contexto: ContextoDoCorte
    /// Quantas violações já tinham acontecido nesta sessão, contando esta.
    var violacao: Int
    /// `false`: o corte acabou de assentar. `true`: um corte gravado sumiu —
    /// a moldura e o contexto são os do instante em que voltou ao lugar.
    var curou: Bool
    /// Medidas com desvio desde a linha anterior que não viraram linha.
    var suprimidas: Int = 0
    /// Há quanto tempo o desvio existia quando esta linha foi escrita.
    var duracao: TimeInterval = 0
    /// Desvios desta sessão que sararam antes da `CorteDoKnob.espera`.
    var transitorios: Int = 0

    var json: [String: Any] {
        [
            "data": ISO8601DateFormatter().string(from: data),
            "lacuna_pt": lacunaPt,
            "moldura": ["x": moldura.origin.x, "y": moldura.origin.y,
                        "largura": moldura.width, "altura": moldura.height],
            "altura_esperada": contexto.alturaEsperada,
            "mode": contexto.mode,
            "foco": contexto.foco ?? "",
            "ultimo_evento": contexto.ultimoEvento ?? "",
            "animando": contexto.animando,
            "display": Int(contexto.displayID),
            "notch_real": contexto.notchReal,
            "violacao": violacao,
            "violacoes_suprimidas": suprimidas,
            "curou": curou,
            "duracao_s": (duracao * 100).rounded() / 100,
            "transitorios": transitorios,
        ]
    }

    var linha: String {
        guard let d = try? JSONSerialization.data(withJSONObject: json,
                                                  options: [.sortedKeys]),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
}

/// Onde a prova persiste: uma linha JSON por violação em Application Support,
/// junto do histórico de notificações e das mensagens, que já moram lá. Por que
/// arquivo e não só `os_log`: o log unificado expira e exige `log show` com
/// predicado pra sair da máquina; o arquivo o usuário anexa. Os dois são
/// escritos — o `os_log` é o que aparece no Console no instante do defeito.
///
/// ponytail: reescreve o arquivo inteiro a cada violação pra podar em `maximo`
/// linhas. Teto: violação é rara e o arquivo tem 50 linhas. Se um dia ele
/// virar fluxo, troque por append + poda periódica.
final class RegistroDeProvas: @unchecked Sendable {
    static let shared = RegistroDeProvas()

    private let fila = DispatchQueue(label: "com.zoi.knobler.corte-do-knob")
    private let log = Logger(subsystem: "com.zoi.knobler", category: "corte-do-knob")
    private let maximo = 50
    let arquivo: URL

    /// `pasta` existe pro gate escrever em `/tmp`. Sem bundle id não é o app —
    /// é o harness do `cortecheck`, e ele não pode sujar o arquivo do usuário.
    init(pasta: URL? = nil) {
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
        arquivo = base.appendingPathComponent("corte-do-knob.jsonl")
    }

    func gravar(_ prova: ProvaDoCorte) {
        let linha = prova.linha
        if prova.curou {
            log.notice("knob curado: lacuna \(prova.lacunaPt, format: .fixed(precision: 1)) pt — \(linha, privacy: .public)")
        } else {
            log.error("knob cortado: lacuna \(prova.lacunaPt, format: .fixed(precision: 1)) pt — \(linha, privacy: .public)")
        }
        fila.async { [arquivo, maximo] in
            var linhas = (try? String(contentsOf: arquivo, encoding: .utf8))?
                .split(separator: "\n").map(String.init) ?? []
            linhas.append(linha)
            if linhas.count > maximo { linhas.removeFirst(linhas.count - maximo) }
            try? (linhas.joined(separator: "\n") + "\n")
                .write(to: arquivo, atomically: true, encoding: .utf8)
        }
    }
}

/// Diagnóstico passivo por monitor. Nunca altera identidade, foco ou conteúdo.
///
/// Um desvio passa por três estados: pendente (apareceu, ainda não assentou),
/// cortado (durou a `espera` e virou linha) e curado (voltou ao lugar depois
/// de gravado, e virou a segunda linha). Pendente que sara antes do prazo é
/// transitório: conta, mas não grava.
@MainActor
final class VigiaDoCorte: ObservableObject {
    private struct Pendente {
        let desde: Date
        /// O retrato do instante em que o desvio apareceu.
        let contexto: ContextoDoCorte
        /// A última medida com desvio — é a que a linha mostra.
        var moldura: CGRect
        var lacuna: CGFloat
    }

    /// Medidas julgáveis com desvio nesta sessão.
    private(set) var violacoes = 0
    /// Desvios que sararam antes da `espera`; nunca viraram linha.
    private(set) var transitorios = 0
    private(set) var ultimaProva: ProvaDoCorte?
    /// Há corte gravado esperando a cura.
    var cortado: Bool { cortadoDesde != nil }
    /// Quando o desvio pendente vai ser julgado; `nil` sem pendência.
    var prazo: Date? {
        guard let pendente else { return nil }
        return max(pendente.desde, ultimaReconfiguracao ?? .distantPast)
            .addingTimeInterval(espera)
    }

    private let registro: RegistroDeProvas
    private let espera: TimeInterval
    private let automatico: Bool
    private var pendente: Pendente?
    private var cortadoDesde: Date?
    private var ultimaReconfiguracao: Date?
    /// Medidas com desvio desde a última linha.
    private var desvios = 0
    private var relogioArmado = false
    private var escutaDeTela: AnyCancellable?

    /// `automatico` liga o relógio que julga o desvio pendente e a escuta de
    /// reconfiguração de tela. O gate desliga os dois e os dirige à mão, com
    /// o relógio dele (`revisar(agora:)`, `telaMudou(agora:)`).
    init(registro: RegistroDeProvas = .shared,
         espera: TimeInterval = CorteDoKnob.espera,
         automatico: Bool = true) {
        self.registro = registro
        self.espera = espera
        self.automatico = automatico
        guard automatico else { return }
        // resolução, Dock, monitor entrando ou saindo: a janela muda de
        // tamanho antes do host, e a geometria passa um tempo em trânsito
        escutaDeTela = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.telaMudou() } }
    }

    /// Chamada a cada medida. O caminho normal são umas comparações — o
    /// contexto só é montado quando um desvio aparece ou cura, por isso o
    /// `@autoclosure`. Devolve se esta medida desvia.
    @discardableResult
    func avaliar(moldura: CGRect,
                 visivel: Bool = true,
                 contexto: @autoclosure () -> ContextoDoCorte,
                 agora: Date = Date()) -> Bool {
        // fora de vista ou sem medida não há o que julgar, e o pendente perde
        // a testemunha: volta a contar se o desvio reaparecer à vista
        guard visivel, CorteDoKnob.medida(moldura) else {
            pendente = nil
            return false
        }
        let lacuna = CorteDoKnob.lacunaDeTopo(molduraMinY: moldura.minY)
        guard CorteDoKnob.viola(lacuna: lacuna) else {
            if pendente != nil {
                pendente = nil
                transitorios += 1
            }
            if let desde = cortadoDesde {
                cortadoDesde = nil
                gravar(ProvaDoCorte(data: agora, lacunaPt: Double(lacuna), moldura: moldura,
                                    contexto: contexto(), violacao: violacoes, curou: true,
                                    suprimidas: desvios, duracao: agora.timeIntervalSince(desde),
                                    transitorios: transitorios))
            }
            return false
        }
        violacoes += 1
        desvios += 1
        // o mesmo corte, já gravado: só conta até curar
        guard cortadoDesde == nil else { return true }
        if pendente == nil {
            pendente = Pendente(desde: agora, contexto: contexto(), moldura: moldura, lacuna: lacuna)
        } else {
            pendente?.moldura = moldura
            pendente?.lacuna = lacuna
        }
        revisar(agora: agora)
        return true
    }

    /// Julga o desvio pendente: grava se ele durou até o prazo; senão arma o
    /// relógio pro que falta. Chamada pelo relógio, por `avaliar` e pelo gate.
    func revisar(agora: Date = Date()) {
        guard let pendente, let prazo else { return }
        guard agora >= prazo else {
            armarRelogio(em: prazo.timeIntervalSince(agora))
            return
        }
        self.pendente = nil
        cortadoDesde = pendente.desde
        gravar(ProvaDoCorte(data: agora, lacunaPt: Double(pendente.lacuna),
                            moldura: pendente.moldura, contexto: pendente.contexto,
                            violacao: violacoes, curou: false, suprimidas: max(0, desvios - 1),
                            duracao: agora.timeIntervalSince(pendente.desde),
                            transitorios: transitorios))
    }

    /// A tela mudou: o prazo do desvio pendente recomeça daqui.
    func telaMudou(agora: Date = Date()) {
        ultimaReconfiguracao = agora
    }

    private func gravar(_ prova: ProvaDoCorte) {
        ultimaProva = prova
        desvios = 0
        registro.gravar(prova)
    }

    /// Um relógio por vez: o prazo só anda pra frente, então quem acordar
    /// cedo demais rearma pro que falta.
    private func armarRelogio(em segundos: TimeInterval) {
        guard automatico, !relogioArmado else { return }
        relogioArmado = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, segundos)))
            self?.relogioArmado = false
            self?.revisar()
        }
    }
}

/// A sonda. Mede a moldura no espaço da raiz e entrega ao vigia. Não desenha
/// nada: é um `Color.clear` de fundo, e o `onChange` só corre quando o
/// retângulo muda de verdade.
struct SensorDeCorte: View {
    @ObservedObject var vigia: VigiaDoCorte
    let contexto: (CGRect) -> ContextoDoCorte

    var body: some View {
        GeometryReader { geo in
            let moldura = geo.frame(in: .named(CorteDoKnob.espacoRaiz))
            Color.clear
                .onAppear { vigia.avaliar(moldura: moldura, contexto: contexto(moldura)) }
                .onChange(of: moldura) { _, novo in
                    vigia.avaliar(moldura: novo, contexto: contexto(novo))
                }
        }
    }
}
