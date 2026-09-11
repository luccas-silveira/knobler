//
//  CorteDoKnob.swift
//  Knobler
//
//  Registro passivo de desvios da moldura e do host em relação ao topo.
//  A apresentação tem identidade estável: nenhuma prova reconstrói views.
//  Altura animada entra apenas como contexto, nunca como violação.

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
}

/// O retrato do instante em que o invariante quebrou. Montado só na violação —
/// no caminho normal nada disto é construído (ver o `@autoclosure` do
/// `VigiaDoCorte.avaliar`).
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
    var curou: Bool
    /// Violações que caíram dentro da janela desta prova e não viraram linha.
    var suprimidas: Int = 0

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
        log.error("knob cortado: lacuna \(prova.lacunaPt, format: .fixed(precision: 1)) pt — \(linha, privacy: .public)")
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
@MainActor
final class VigiaDoCorte: ObservableObject {
    private(set) var violacoes = 0
    private(set) var ultimaProva: ProvaDoCorte?
    let intervaloDeRegistro: TimeInterval = 2
    private var ultimaGravacao: Date?
    private var suprimidas = 0
    private let registro: RegistroDeProvas

    init(registro: RegistroDeProvas = .shared) { self.registro = registro }

    @discardableResult
    func avaliar(moldura: CGRect,
                 contexto: @autoclosure () -> ContextoDoCorte,
                 agora: Date = Date()) -> Bool {
        let lacuna = CorteDoKnob.lacunaDeTopo(molduraMinY: moldura.minY)
        guard CorteDoKnob.viola(lacuna: lacuna) else { return false }
        violacoes += 1
        guard agora.timeIntervalSince(ultimaGravacao ?? .distantPast) >= intervaloDeRegistro else {
            suprimidas += 1
            return true
        }
        let prova = ProvaDoCorte(data: agora, lacunaPt: Double(lacuna),
                                 moldura: moldura, contexto: contexto(), violacao: violacoes,
                                 curou: false, suprimidas: suprimidas)
        ultimaProva = prova
        ultimaGravacao = agora
        suprimidas = 0
        registro.gravar(prova)
        return true
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
