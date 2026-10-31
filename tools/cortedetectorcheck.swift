// Gate do "knob cortado ao meio" (mapa docs/wayfinder/map-corte-do-knob.md).
//
// Trava o invariante, as provas e o que NÃO vira prova: medida vazia, janela
// escondida, desvio de passagem e reconfiguração de tela (os 48 alarmes falsos
// do `corte-do-knob.jsonl` até 30/10). E trava o outro lado: corte real
// continua virando linha, e a cura dele também. tools/check.sh também impede
// a volta da reconstrução por `.id`. O host AppKit real fica no
// tools/cortehostcheck.swift.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/CorteDoKnob.swift tools/cortedetectorcheck.swift \
//     -o /tmp/cortedetectorcheck && /tmp/cortedetectorcheck

import AppKit
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

/// Lê o arquivo de provas esperando a fila do registro escrever `n` linhas.
private func linhas(de registro: RegistroDeProvas, esperando n: Int) -> [String] {
    var linhas: [String] = []
    for _ in 0..<50 {
        linhas = (try? String(contentsOf: registro.arquivo, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
        if linhas.count >= n { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return linhas
}

@main
enum Gate {
    @MainActor
    static func main() {
        let pasta = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cortedetectorcheck-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        // um arquivo por seção: a fila do registro escreve depois, e apagar o
        // arquivo de uma seção pra outra corre contra ela
        func registroNovo(_ secao: String) -> RegistroDeProvas {
            RegistroDeProvas(pasta: pasta.appendingPathComponent(secao, isDirectory: true))
        }
        let registro = registroNovo("filtros")
        func vigiaManual() -> VigiaDoCorte { VigiaDoCorte(registro: registro, automatico: false) }

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
        let normal = vigiaManual()
        exigir(normal.avaliar(moldura: moldura(topo: 0), contexto: contexto(), agora: agora) == false,
               "moldura no topo disparou o vigia")
        exigir(normal.avaliar(moldura: moldura(topo: 1.5), contexto: contexto(), agora: agora) == false,
               "desvio dentro da tolerância disparou o vigia")
        exigir(normal.violacoes == 0 && normal.prazo == nil, "o caminho normal contou violação")
        exigir(contextosMontados == 0,
               "o contexto foi montado sem violação (o @autoclosure não segurou)")

        // 2. (a) Medida que não é medida. As linhas reais: host recém-pendurado,
        //    0×0, com a janela já do tamanho da tela — a lacuna sai igual à
        //    altura dela, no display com notch (1117, 1329) e nos sem (1080, 1920).
        let vazio = vigiaManual()
        for altura: CGFloat in [1117, 1329, 1080, 1920] {
            exigir(!vazio.avaliar(moldura: CGRect(x: 0, y: altura, width: 0, height: 0),
                                  contexto: contexto(), agora: agora),
                   "moldura 0×0 em y=\(altura) virou violação")
        }
        exigir(!vazio.avaliar(moldura: .null, contexto: contexto(), agora: agora),
               "moldura nula virou violação")
        // janela escondida: desvio medido, mas ninguém vê
        exigir(!vazio.avaliar(moldura: moldura(topo: 60, altura: 240), visivel: false,
                              contexto: contexto(), agora: agora),
               "desvio em janela escondida virou violação")
        vazio.revisar(agora: agora.addingTimeInterval(60))
        exigir(vazio.violacoes == 0 && vazio.prazo == nil && vazio.ultimaProva == nil,
               "medida vazia ou escondida deixou rastro (violações \(vazio.violacoes))")
        exigir(contextosMontados == 0, "medida vazia montou contexto")
        // desvio que some de vista antes de assentar perde a testemunha
        exigir(vazio.avaliar(moldura: moldura(topo: 60), contexto: contexto(), agora: agora),
               "desvio visível não foi visto")
        exigir(vazio.prazo != nil, "desvio visível não ficou pendente")
        vazio.avaliar(moldura: moldura(topo: 60), visivel: false, contexto: contexto(),
                      agora: agora.addingTimeInterval(0.2))
        exigir(vazio.prazo == nil, "a janela escondeu e o desvio continuou pendente")
        vazio.revisar(agora: agora.addingTimeInterval(60))
        exigir(vazio.ultimaProva == nil, "desvio escondido antes do prazo virou prova")

        // 3. (b) Reconfiguração de tela. A sequência é a que o AppKit produz no
        //    `setFrame` (reproduzida em tools/cortehostcheck.swift): uma passada
        //    com a janela no tamanho novo e o host no velho, e a seguinte certa.
        //    Molduras das 10 linhas reais com a altura de outra tela.
        let reais: [(CGFloat, CGFloat, CGFloat)] = [  // (lacuna, altura do host, altura certa)
            (-212, 1329, 1117), (212, 1117, 1329), (-64, 1117, 1053),
            (212, 1053, 1265), (-840, 1920, 1080), (840, 1080, 1920),
        ]
        for (lacuna, alturaVelha, alturaNova) in reais {
            let vigia = vigiaManual()
            let t0 = agora
            vigia.telaMudou(agora: t0)
            let velha = CGRect(x: 0, y: lacuna, width: 900, height: alturaVelha)
            exigir(vigia.avaliar(moldura: velha, contexto: contexto(), agora: t0),
                   "o desvio de passagem (\(lacuna)) nem foi visto")
            exigir(vigia.prazo == t0.addingTimeInterval(CorteDoKnob.espera),
                   "o desvio de passagem não esperou a geometria assentar")
            vigia.revisar(agora: t0.addingTimeInterval(CorteDoKnob.espera / 2))
            exigir(vigia.ultimaProva == nil, "desvio de passagem gravado antes do prazo")
            vigia.avaliar(moldura: CGRect(x: 0, y: 0, width: 900, height: alturaNova),
                          contexto: contexto(), agora: t0.addingTimeInterval(0.001))
            vigia.revisar(agora: t0.addingTimeInterval(60))
            exigir(vigia.ultimaProva == nil && vigia.prazo == nil && vigia.transitorios == 1,
                   "desvio de passagem (\(lacuna) pt, host \(alturaVelha) numa tela de "
                   + "\(alturaNova)) virou prova")
        }
        // a reconfiguração empurra o prazo — mas não esconde o corte que fica
        let atravessa = vigiaManual()
        atravessa.avaliar(moldura: moldura(topo: -212, altura: 1329), contexto: contexto(), agora: agora)
        atravessa.telaMudou(agora: agora.addingTimeInterval(0.8))
        exigir(atravessa.prazo == agora.addingTimeInterval(0.8 + CorteDoKnob.espera),
               "a reconfiguração não empurrou o prazo")
        atravessa.revisar(agora: agora.addingTimeInterval(1.2))
        exigir(atravessa.ultimaProva == nil, "julgou no meio da reconfiguração")
        atravessa.avaliar(moldura: moldura(topo: -212, altura: 1329), contexto: contexto(),
                          agora: agora.addingTimeInterval(1.9))
        exigir(atravessa.ultimaProva?.lacunaPt == -212 && atravessa.cortado,
               "o corte que sobreviveu à reconfiguração não virou prova")

        // 4. (c) Corte real e cura. O detector antigo escrevia `curou: false`
        //    fixo (sobra da cura por `.id`, removida em f6dbff6): a cura nunca
        //    era observada. Agora ela vira a segunda linha do corte.
        let registroDaCura = registroNovo("cura")
        let vigia = VigiaDoCorte(registro: registroDaCura, automatico: false)
        contextosMontados = 0
        let cortado = moldura(topo: 60, altura: 240)
        exigir(vigia.avaliar(moldura: cortado, contexto: contexto(), agora: agora), "não detectou")
        vigia.avaliar(moldura: cortado, contexto: contexto(), agora: agora.addingTimeInterval(0.1))
        vigia.avaliar(moldura: cortado, contexto: contexto(), agora: agora.addingTimeInterval(0.5))
        exigir(vigia.ultimaProva == nil, "gravou antes de o corte assentar")
        vigia.revisar(agora: agora.addingTimeInterval(CorteDoKnob.espera))
        guard let prova = vigia.ultimaProva else { exigir(false, "o corte que durou não virou prova"); return }
        exigir(!prova.curou && prova.lacunaPt == 60 && prova.violacao == 3 && prova.suprimidas == 2
               && abs(prova.duracao - CorteDoKnob.espera) < 0.001 && vigia.cortado,
               "prova do corte errada: \(prova.linha)")
        exigir(contextosMontados == 1, "o contexto do corte foi montado \(contextosMontados) vezes")
        // o mesmo corte não vira linha nova enquanto não curar
        vigia.avaliar(moldura: cortado, contexto: contexto(), agora: agora.addingTimeInterval(2))
        vigia.avaliar(moldura: cortado, contexto: contexto(), agora: agora.addingTimeInterval(3))
        vigia.revisar(agora: agora.addingTimeInterval(30))
        exigir(vigia.ultimaProva?.data == prova.data && vigia.violacoes == 5,
               "o corte aberto gravou linha repetida")
        // escondido não é curado
        vigia.avaliar(moldura: moldura(topo: 0), visivel: false, contexto: contexto(),
                      agora: agora.addingTimeInterval(3.5))
        exigir(vigia.cortado, "janela escondida contou como cura")
        // a cura
        exigir(!vigia.avaliar(moldura: moldura(topo: 0, altura: 240), contexto: contexto(),
                              agora: agora.addingTimeInterval(4)),
               "a moldura de volta ao topo acusou desvio")
        guard let cura = vigia.ultimaProva, cura.curou else {
            exigir(false, "a cura não foi detectada: \(vigia.ultimaProva?.linha ?? "—")"); return
        }
        exigir(cura.lacunaPt == 0 && cura.suprimidas == 2 && abs(cura.duracao - 4) < 0.001
               && !vigia.cortado && contextosMontados == 2,
               "prova da cura errada: \(cura.linha)")
        // curado, o próximo corte recomeça do zero
        vigia.avaliar(moldura: cortado, contexto: contexto(), agora: agora.addingTimeInterval(10))
        exigir(vigia.prazo == agora.addingTimeInterval(10 + CorteDoKnob.espera),
               "depois da cura o corte novo não ficou pendente")
        let gravadas = linhas(de: registroDaCura, esperando: 2)
        exigir(gravadas.count == 2 && gravadas[0].contains("\"curou\":false")
               && gravadas[1].contains("\"curou\":true") && gravadas[1].contains("\"duracao_s\":4"),
               "o arquivo não tem corte e cura: \(gravadas)")

        // 5. O relógio de verdade: sem medida nova, o pendente é julgado sozinho
        //    no prazo — e a notificação de tela do AppKit empurra esse prazo.
        //    Margens largas de propósito (0,2 s): relógio real em CI anda.
        let espera: TimeInterval = 1
        let real = VigiaDoCorte(registro: registroNovo("relogio"), espera: espera)
        let inicio = Date()
        real.avaliar(moldura: cortado, contexto: contexto(), agora: inicio)
        RunLoop.main.run(until: inicio.addingTimeInterval(0.3))
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification,
                                        object: nil)
        RunLoop.main.run(until: inicio.addingTimeInterval(1.1))
        exigir(real.ultimaProva == nil,
               "a notificação de tela não empurrou o prazo (gravou em \(Date().timeIntervalSince(inicio)) s)")
        RunLoop.main.run(until: inicio.addingTimeInterval(2.5))
        exigir(real.ultimaProva?.curou == false && real.cortado,
               "o relógio não julgou o pendente sozinho")

        // 6. A prova persiste, e o arquivo não cresce sem fim.
        let registroDaPoda = registroNovo("poda")
        for i in 0..<60 {
            registroDaPoda.gravar(ProvaDoCorte(data: agora, lacunaPt: Double(i), moldura: cortado,
                                         contexto: contexto(), violacao: i, curou: false))
        }
        var todas: [String] = []
        for _ in 0..<50 {
            todas = linhas(de: registroDaPoda, esperando: 50)
            if todas.last?.contains("\"lacuna_pt\":59") == true { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        exigir(todas.count == 50, "o arquivo de provas tem \(todas.count) linhas, esperado 50 (poda)")
        exigir(todas.last?.contains("\"lacuna_pt\":59") == true,
               "a última linha não é a última prova: \(todas.last ?? "—")")
        exigir(JSONSerialization.isValidJSONObject(prova.json), "a prova não serializa")
        exigir(JSONSerialization.isValidJSONObject(cura.json), "a cura não serializa")

        // 7. O CUSTO do caminho normal — o que a detecção acrescenta ao ciclo
        //    de desenho por medida. Teto da 006: os ~21 ms da varredura
        //    síncrona da 004 são o que NÃO fazer. Asserção folgada de propósito
        //    (1 ms): número apertado vira gate instável em máquina carregada.
        let custo = vigiaManual()
        let n = 100_000
        let t0 = DispatchTime.now().uptimeNanoseconds
        for i in 0..<n {
            custo.avaliar(moldura: moldura(topo: CGFloat(i % 2)), contexto: contexto(), agora: agora)
        }
        let ns = Double(DispatchTime.now().uptimeNanoseconds - t0) / Double(n)
        // build sem -O: o número anda entre corridas (~130-290 ns medidos). O
        // que o gate trava é a ordem de grandeza, não o valor.
        print(String(format: "custo do invariante: %.0f ns por medida (%d medidas, sem -O)", ns, n))
        exigir(custo.violacoes == 0, "o caminho normal contou violação no laço de custo")
        exigir(ns < 1_000_000, "o invariante custa \(ns) ns por medida — mais de 1 ms")

        print("cortedetectorcheck ok — invariante, filtros, espera, reconfiguração e cura")
    }
}
