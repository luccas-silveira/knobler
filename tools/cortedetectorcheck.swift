// Gate do "knob cortado ao meio" (mapa docs/wayfinder/map-corte-do-knob.md).
//
// Trava as três metades da 006: o invariante da lacuna de topo, a prova gravada
// e a cura disparada SÓ pela violação medida. Falha contra o código de antes do
// conserto porque Knobler/CorteDoKnob.swift não existia lá — a compilação nem
// começa.
//
// A fiação na NotchView (a sonda e o `.id` da cura) é conferida por grep na
// linha do tools/check.sh: o detector sozinho compila e passa mesmo se alguém
// arrancar o `.background(SensorDeCorte(...))` num refactor.
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
        exigir(vigia.geracao == 0 && vigia.violacoes == 0 && vigia.curas == 0,
               "o caminho normal mexeu no estado do vigia")
        exigir(contextosMontados == 0,
               "o contexto foi montado sem violação (o @autoclosure não segurou)")

        // 2. A violação: mede, grava a prova e cura.
        let cortado = moldura(topo: 60, altura: 240)
        exigir(vigia.avaliar(moldura: cortado, contexto: contexto(), agora: agora),
               "lacuna de 60 pt não acusou")
        exigir(contextosMontados == 1, "o contexto não foi montado na violação")
        exigir(vigia.violacoes == 1 && vigia.curas == 1 && vigia.geracao == 1,
               "a violação não curou: violações=\(vigia.violacoes) curas=\(vigia.curas) geração=\(vigia.geracao)")
        guard let prova = vigia.ultimaProva else { exigir(false, "sem prova"); return }
        exigir(abs(prova.lacunaPt - 60) < 0.001, "lacuna gravada = \(prova.lacunaPt), esperado 60")
        exigir(prova.curou, "a prova não registrou que curou")

        // 3. A prova tem o que a 006 pediu: geometria, mode, foco, o que
        //    animava, o que acabou de acontecer — e onde.
        let json = prova.json
        for campo in ["data", "lacuna_pt", "moldura", "altura_esperada", "mode", "foco",
                      "ultimo_evento", "animando", "display", "notch_real", "violacao", "curou"] {
            exigir(json[campo] != nil, "a prova não tem o campo \(campo)")
        }
        let linha = prova.linha
        exigir(linha.hasPrefix("{") && linha.contains("\"mode\":\"music\"")
                && !linha.contains("\n"),
               "a linha da prova não é um JSON de uma linha: \(linha)")

        // 4. A espera entre curas: a segunda violação grava e NÃO cura.
        exigir(vigia.avaliar(moldura: cortado, contexto: contexto(), agora: agora.addingTimeInterval(0.5)),
               "a segunda violação não acusou")
        exigir(vigia.violacoes == 2 && vigia.curas == 1 && vigia.geracao == 1,
               "curou dentro da espera de \(vigia.esperaEntreCuras) s")
        exigir(vigia.ultimaProva?.curou == false, "a prova diz que curou dentro da espera")
        // passada a espera, cura de novo
        exigir(vigia.avaliar(moldura: cortado, contexto: contexto(),
                             agora: agora.addingTimeInterval(vigia.esperaEntreCuras + 0.1)),
               "a terceira violação não acusou")
        exigir(vigia.curas == 2 && vigia.geracao == 2, "não curou depois da espera")

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
        let n = 100_000
        let t0 = DispatchTime.now().uptimeNanoseconds
        for i in 0..<n {
            vigia.avaliar(moldura: moldura(topo: CGFloat(i % 2)), contexto: contexto(), agora: agora)
        }
        let ns = Double(DispatchTime.now().uptimeNanoseconds - t0) / Double(n)
        print(String(format: "custo do invariante: %.0f ns por medida (%d medidas)", ns, n))
        exigir(vigia.violacoes == 3, "o caminho normal contou violação no laço de custo")
        exigir(ns < 1_000_000, "o invariante custa \(ns) ns por medida — mais de 1 ms")

        print("cortedetectorcheck ok — invariante, prova e cura travados")
    }
}
