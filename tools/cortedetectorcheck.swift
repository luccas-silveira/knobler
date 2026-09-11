// Gate do "knob cortado ao meio" (mapa docs/wayfinder/map-corte-do-knob.md).
//
// Trava o invariante, as provas e a limitação de frequência do diagnóstico
// passivo. tools/check.sh também impede a volta da reconstrução por `.id`.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/CorteDoKnob.swift tools/cortedetectorcheck.swift \
//     -o /tmp/cortedetectorcheck && /tmp/cortedetectorcheck

import Foundation
import CoreGraphics

private func exigir(_ cond: Bool, _ msg: String) {
    if !cond {
        print("FALHOU: \(msg)")
        exit(1)
    }
}

private func moldura(topo: CGFloat, altura: CGFloat = 32) -> CGRect {
    CGRect(x: 0, y: topo, width: 200, height: altura)
}

@main
enum Gate {
    @MainActor
    static func main() {
        let pasta = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cortedetectorcheck-\(getpid())", isDirectory: true)
        let registro = RegistroDeProvas(pasta: pasta)
        try? FileManager.default.removeItem(at: registro.arquivo)
        let vigia = VigiaDoCorte(registro: registro)

        var contextosMontados = 0
        func contexto() -> ContextoDoCorte {
            contextosMontados += 1
            return ContextoDoCorte(mode: "music", foco: "musica", alturaEsperada: 300,
                                   ultimoEvento: "musica há 0,4 s", animando: true,
                                   displayID: 1, notchReal: true)
        }

        // 1. O invariante: topo no lugar não é violação.
        exigir(!CorteDoKnob.viola(lacuna: 0), "lacuna 0 acusou violação")
        exigir(!CorteDoKnob.viola(lacuna: CorteDoKnob.toleranciaPt),
               "lacuna na tolerância acusou violação")
        exigir(CorteDoKnob.viola(lacuna: CorteDoKnob.toleranciaPt + 0.01),
               "lacuna acima da tolerância passou")
        exigir(CorteDoKnob.viola(lacuna: .nan), "lacuna NaN passou")

        let agora = Date()
        exigir(vigia.avaliar(moldura: moldura(topo: 0), contexto: contexto(), agora: agora) == false,
               "moldura no topo disparou o vigia")
        exigir(vigia.avaliar(moldura: moldura(topo: 1.5), contexto: contexto(), agora: agora) == false,
               "desvio dentro da tolerância disparou o vigia")
        exigir(vigia.violacoes == 0, "o caminho normal contou violação")
        exigir(contextosMontados == 0,
               "o contexto foi montado sem violação (o @autoclosure não segurou)")

        // Violações só registram evidência; nenhum efeito reconstrói o card.
        let cortado = moldura(topo: 60, altura: 240)
        exigir(vigia.avaliar(moldura: cortado, contexto: contexto(), agora: agora), "não detectou")
        guard let prova = vigia.ultimaProva else { exigir(false, "sem prova"); return }
        exigir(!prova.curou && vigia.violacoes == 1, "diagnóstico não é passivo")
        vigia.avaliar(moldura: cortado, contexto: contexto(), agora: agora.addingTimeInterval(0.1))
        exigir(vigia.ultimaProva?.violacao == 1, "registro sem limitação de frequência")
        vigia.avaliar(moldura: cortado, contexto: contexto(), agora: agora.addingTimeInterval(3))
        exigir(vigia.ultimaProva?.suprimidas == 1 && vigia.ultimaProva?.curou == false, "perdeu evidência")

        // 5. A prova persiste, e o arquivo não cresce sem fim.
        for i in 0..<60 {
            registro.gravar(ProvaDoCorte(data: agora, lacunaPt: Double(i), moldura: cortado,
                                         contexto: contexto(), violacao: i, curou: false))
        }
        var linhas: [String] = []
        for _ in 0..<50 {
            linhas = (try? String(contentsOf: registro.arquivo, encoding: .utf8))?
                .split(separator: "\n").map(String.init) ?? []
            if linhas.count == 50 { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        exigir(linhas.count == 50, "o arquivo de provas tem \(linhas.count) linhas, esperado 50 (poda)")
        exigir(linhas.last?.contains("\"lacuna_pt\":59") == true,
               "a última linha não é a última prova: \(linhas.last ?? "—")")
        exigir(JSONSerialization.isValidJSONObject(prova.json), "a prova não serializa")
        try? FileManager.default.removeItem(at: pasta)

        // 6. O CUSTO do caminho normal — o que a detecção acrescenta ao ciclo
        //    de desenho por medida. Teto da 006: os ~21 ms da varredura
        //    síncrona da 004 são o que NÃO fazer. Asserção folgada de propósito
        //    (1 ms): número apertado vira gate instável em máquina carregada.
        let violacoesAntesDoCusto = vigia.violacoes
        let n = 100_000
        let t0 = DispatchTime.now().uptimeNanoseconds
        for i in 0..<n {
            vigia.avaliar(moldura: moldura(topo: CGFloat(i % 2)), contexto: contexto(), agora: agora)
        }
        let ns = Double(DispatchTime.now().uptimeNanoseconds - t0) / Double(n)
        // build sem -O: o número anda entre corridas (~130-290 ns medidos). O
        // que o gate trava é a ordem de grandeza, não o valor.
        print(String(format: "custo do invariante: %.0f ns por medida (%d medidas, sem -O)", ns, n))
        exigir(vigia.violacoes == violacoesAntesDoCusto,
               "o caminho normal contou violação no laço de custo")
        exigir(ns < 1_000_000, "o invariante custa \(ns) ns por medida — mais de 1 ms")

        print("cortedetectorcheck ok — invariante e diagnóstico passivo")
    }
}
