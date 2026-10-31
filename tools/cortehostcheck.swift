// Gate do detector de corte no host AppKit real (`NotchHostingView` dentro de
// `NotchWindow`), dirigido pela mesma sequência que o `placeWindows` faz:
// painel nascendo com `.zero`, host pendurado, `setFrame` pro tamanho da tela,
// e depois troca de resolução. Era essa sequência que gravava 48 de 48 linhas
// falsas no `corte-do-knob.jsonl` até 30/10 — o `setFrame` roda uma passada de
// layout com a janela no tamanho novo e o host no velho (0×0 ao nascer).
//
// Um controle (`Replica`, a medida antiga, sem filtro) prova que a sequência
// ainda produz o desvio de passagem: sem ele, um zero aqui poderia ser só um
// AppKit que deixou de reproduzir o cenário. O painel aparece com alpha 0 e
// fora de qualquer tela — nada é desenhado à vista.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/CorteDoKnob.swift Knobler/NotchWindow.swift tools/cortehostcheck.swift \
//     -o /tmp/cortehostcheck && /tmp/cortehostcheck

import AppKit
import SwiftUI

private func exigir(_ cond: Bool, _ msg: String) {
    if !cond {
        print("FALHOU: \(msg)")
        exit(1)
    }
}

/// O "onde deveria estar" do app: conteúdo ancorado ao topo.
private struct Raiz: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.black.frame(width: 200, height: 32)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A medida do host como era antes do filtro: anota tudo o que o layout vê.
private final class Replica: NSHostingView<Raiz> {
    var medidas: [CGRect] = []
    override func layout() {
        super.layout()
        guard let window else { return }
        let gap = window.contentLayoutRect.maxY - convert(bounds, to: nil).maxY
        medidas.append(CGRect(x: frame.minX, y: gap, width: bounds.width, height: bounds.height))
    }
}

private func painel() -> NotchWindow {
    let p = NotchWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
    p.alphaValue = 0
    p.ignoresMouseEvents = true
    return p
}

/// Bem longe de qualquer tela, com a altura da tela simulada.
private func quadro(altura: CGFloat) -> CGRect {
    CGRect(x: -30_000, y: -30_000, width: 900, height: altura)
}

@main
enum Gate {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let pasta = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cortehostcheck-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: pasta) }

        // Controle: a sequência do app ainda produz os dois desvios de passagem.
        let pc = painel()
        let replica = Replica(rootView: Raiz())
        pc.contentView = replica
        pc.setFrame(quadro(altura: 1329), display: true)
        replica.layoutSubtreeIfNeeded()
        exigir(replica.medidas.contains { $0.width == 0 && $0.height == 0 && $0.minY == 1329 },
               "controle: o nascimento não mediu o host 0×0 (\(replica.medidas)) — o AppKit "
               + "deixou de reproduzir o alarme falso e o resto do gate não prova nada")
        replica.medidas.removeAll()
        pc.setFrame(quadro(altura: 1117), display: true)
        replica.layoutSubtreeIfNeeded()
        exigir(replica.medidas.contains { $0.minY == -212 && $0.height == 1329 },
               "controle: a troca de resolução não mediu o host velho (\(replica.medidas))")
        exigir(replica.medidas.last?.minY == 0, "controle: o host não assentou (\(replica.medidas))")

        // O host real, na mesma sequência.
        var contextos = 0
        let p = painel()
        let host = NotchHostingView(rootView: Raiz())
        host.hostMonitor = VigiaDoCorte(registro: RegistroDeProvas(pasta: pasta), automatico: false)
        host.diagnosticContext = {
            contextos += 1
            return ContextoDoCorte(mode: "host:closed", foco: nil, alturaEsperada: 32,
                                   ultimoEvento: nil, animando: false, displayID: 1, notchReal: true)
        }
        let vigia = host.hostMonitor

        // (a) nascer: host 0×0 e painel ainda escondido
        p.contentView = host
        p.setFrame(quadro(altura: 1329), display: true)
        host.layoutSubtreeIfNeeded()
        vigia.revisar(agora: Date().addingTimeInterval(60))
        exigir(vigia.violacoes == 0 && vigia.prazo == nil && vigia.ultimaProva == nil && contextos == 0,
               "o nascimento do painel virou violação (\(vigia.violacoes))")

        // (b) troca de resolução com o painel à vista: o desvio é visto e descartado
        p.orderFrontRegardless()
        exigir(p.isVisible, "o painel não ficou visível")
        p.setFrame(quadro(altura: 1117), display: true)
        host.layoutSubtreeIfNeeded()
        vigia.revisar(agora: Date().addingTimeInterval(60))
        exigir(vigia.violacoes >= 1 && vigia.transitorios >= 1,
               "a troca de resolução à vista não passou pelo vigia (violações \(vigia.violacoes), "
               + "transitórios \(vigia.transitorios))")
        exigir(vigia.ultimaProva == nil && vigia.prazo == nil,
               "a troca de resolução virou prova: \(vigia.ultimaProva?.linha ?? "pendente")")

        // Corte real: o host desce 60 pt dentro do painel e fica.
        host.setFrameOrigin(NSPoint(x: 0, y: -60))
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        exigir(vigia.prazo != nil, "o host deslocado não ficou pendente (\(host.frame))")
        vigia.revisar(agora: Date().addingTimeInterval(CorteDoKnob.espera + 0.01))
        guard let corte = vigia.ultimaProva else { exigir(false, "o corte real não virou prova"); return }
        exigir(!corte.curou && corte.lacunaPt == 60 && corte.contexto.mode == "host:closed",
               "prova do corte real errada: \(corte.linha)")

        // (c) cura: o host volta ao topo
        host.setFrameOrigin(.zero)
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        exigir(vigia.ultimaProva?.curou == true && !vigia.cortado,
               "a cura do host não foi detectada: \(vigia.ultimaProva?.linha ?? "—")")

        // Escondido (tela cheia): o desvio não conta; ao reaparecer, o host
        // mede de novo sem esperar layout — e o corte que ficou é julgado.
        p.orderOut(nil)
        host.setFrameOrigin(NSPoint(x: 0, y: -60))
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        exigir(vigia.prazo == nil && !vigia.cortado, "o desvio no painel escondido ficou pendente")
        p.orderFrontRegardless()
        exigir(vigia.prazo != nil, "o painel reapareceu com o host deslocado e ninguém mediu")

        // Pendente à vista e o painel some (tela cheia) antes do prazo: o
        // `orderOut` não passa por layout, e o relógio acordava e gravava
        // `curou:false` com o painel já escondido.
        let antes = vigia.ultimaProva
        p.orderOut(nil)
        exigir(vigia.prazo == nil, "o orderOut não descartou o desvio pendente")
        p.orderFrontRegardless()
        exigir(vigia.prazo != nil, "o painel voltou com o host deslocado e ninguém mediu")
        // sem o gancho do orderOut: só a pergunta do relógio segura
        p.aoMudarVisibilidade = nil
        p.orderOut(nil)
        exigir(vigia.prazo != nil, "preparo: o desvio devia seguir pendente sem o gancho")
        vigia.revisar(agora: Date().addingTimeInterval(CorteDoKnob.espera + 1))
        exigir(vigia.ultimaProva?.data == antes?.data && !vigia.cortado,
               "o relógio gravou o corte com o painel escondido: \(vigia.ultimaProva?.linha ?? "—")")

        pc.orderOut(nil)
        print("cortehostcheck ok — nascimento e troca de resolução não gravam; corte e cura gravam; escondido não grava")
    }
}
