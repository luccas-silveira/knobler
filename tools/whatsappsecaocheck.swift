// Gate da etapa 9 do WhatsApp: a seção `.whatsapp` do card aberto — enum,
// ordem salva, atalhos do Ações rápidas, largura 780 e altura 360 (quadro
// "Lista e conversa individual" da variante A: 780 × 452 = 32 + 360 + 60).
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/NotchSectionOrder.swift Knobler/NotchPresentation.swift \
//     tools/whatsappsecaocheck.swift \
//     -o /tmp/whatsappsecaocheck && /tmp/whatsappsecaocheck
//
// Tudo puro: nenhuma janela, nenhum UserDefaults, nenhuma rede.

import Foundation
import CoreGraphics

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappsecaocheck.swift:\(linha))")
        exit(1)
    }
}

@main
enum WhatsAppSecaoCheck {
    static func main() {
        testEnum()
        testOrdem()
        testMedidas()
        testApresentacao()
        testAtalhos()
        print("whatsappsecaocheck ok")
    }

    // MARK: - enum

    static func testEnum() {
        exigir(NotchSection.whatsapp.rawValue == "whatsapp", "rawValue da seção (vai pro UserDefaults)")
        exigir(NotchSection(rawValue: "whatsapp") == .whatsapp, "ordem salva com \"whatsapp\" não volta pra seção")
        exigir(NotchSection.whatsapp.titulo == "WhatsApp", "título: \(NotchSection.whatsapp.titulo)")
        exigir(NotchSection.whatsapp.simbolo == "phone.bubble.fill", "símbolo: \(NotchSection.whatsapp.simbolo)")
        // A21: `.mensagens` é a LAN; nunca renomeada nem reaproveitada
        exigir(NotchSection.mensagens.rawValue == "mensagens", "mensagens mudou de rawValue")
        exigir(NotchSection.mensagens.titulo == "Mensagens", "mensagens mudou de título")
        exigir(NotchSection.mensagens.simbolo == "bubble.left.and.bubble.right.fill",
               "mensagens mudou de símbolo")
        exigir(NotchSection.whatsapp != .mensagens, "whatsapp reaproveitou mensagens")
        exigir(NotchSection.allCases.filter { $0 == .whatsapp }.count == 1, "whatsapp fora de allCases")
    }

    // MARK: - ordem

    /// Ordem salva por uma versão que não conhecia o WhatsApp: a de fábrica de
    /// antes, escrita à mão (não deriva do enum novo).
    static let ordemAntiga = [
        "musica", "atividade", "agentes", "pomodoro", "shelf", "espelho", "mensagens", "historico",
        "nota", "link", "anotacao", "agenda", "lembretesApple", "monitores", "acoesRapidas", "cor",
    ]

    static func testOrdem() {
        let p = NotchSectionOrder.padrao
        guard let iM = p.firstIndex(of: .mensagens), let iW = p.firstIndex(of: .whatsapp),
              let iH = p.firstIndex(of: .historico) else {
            exigir(false, "padrão sem mensagens/whatsapp/histórico: \(p)"); return
        }
        exigir(iW == iM + 1, "whatsapp não vem logo depois de mensagens: \(p)")
        exigir(iH == iW + 1, "histórico não vem logo depois de whatsapp: \(p)")
        exigir(p.count == NotchSection.allCases.count && Set(p) == Set(NotchSection.allCases),
               "padrão com seção faltando ou repetida: \(p)")

        // A25: a ordem antiga continua valendo; a seção nova entra no fim
        let saneada = NotchSectionOrder.sanear(salva: ordemAntiga)
        exigir(saneada.count == NotchSection.allCases.count, "sanear perdeu seção: \(saneada)")
        exigir(Set(saneada) == Set(NotchSection.allCases), "sanear não completou: \(saneada)")
        exigir(saneada.last == .whatsapp, "whatsapp não entrou no fim da ordem antiga: \(saneada)")
        exigir(saneada.dropLast().map(\.rawValue) == ordemAntiga,
               "sanear mexeu na ordem que o usuário salvou: \(saneada)")

        // peça desinstalada: some da faixa e do editor de ordem
        let editor = NotchSectionOrder.visiveis(base: saneada, desinstaladas: [.whatsapp])
        exigir(!editor.contains(.whatsapp), "editor de ordem mostra whatsapp desinstalado")
        exigir(editor.map(\.rawValue) == ordemAntiga, "esconder whatsapp mexeu nas outras: \(editor)")
        exigir(NotchSectionOrder.visiveis(base: saneada, desinstaladas: []).contains(.whatsapp),
               "whatsapp instalado sumiu do editor")

        // a faixa do card: nem fixada nem com conteúdo a seção desinstalada aparece
        let agora = Date(timeIntervalSince1970: 1_000_000)
        let estados = NotchSection.allCases.map {
            NotchSectionState(section: $0, hasContent: $0 == .whatsapp, lastEvent: $0 == .whatsapp ? agora : nil)
        }
        let escondida = NotchSectionOrder.ordenar(base: saneada, estados: estados, fixadas: [.whatsapp],
                                                  agora: agora, travadaNaNota: false,
                                                  desinstaladas: [.whatsapp])
        exigir(!escondida.contains(.whatsapp), "faixa mostra whatsapp desinstalado: \(escondida)")
        let instalada = NotchSectionOrder.ordenar(base: saneada, estados: estados, fixadas: [.whatsapp],
                                                  agora: agora, travadaNaNota: false)
        exigir(instalada.contains(.whatsapp), "faixa não mostra whatsapp instalado: \(instalada)")
    }

    // MARK: - medidas

    static func testMedidas() {
        exigir(NotchMetrics.alturaDaSecao(.whatsapp) == 360,
               "altura da seção: \(NotchMetrics.alturaDaSecao(.whatsapp))")
        exigir(NotchMetrics.larguraDoCard(.whatsapp, padrao: 430) == 780,
               "largura do card: \(NotchMetrics.larguraDoCard(.whatsapp, padrao: 430))")
        // a regra do link (só com página aberta) não vale pro WhatsApp
        exigir(NotchMetrics.larguraDoCard(.whatsapp, padrao: 430, linkAberto: false) == 780,
               "largura do whatsapp dependeu do link aberto")
        exigir(NotchMetrics.larguraDoCard(.mensagens, padrao: 430) == 430, "mensagens mudou de largura")
        exigir(NotchMetrics.alturaDaSecao(.mensagens) == 272, "mensagens mudou de altura")
        exigir(NotchMetrics.larguraDoCard(.link, padrao: 430, linkAberto: false) == 430,
               "link sem página mudou de largura")
        exigir(NotchMetrics.larguraDoCard(.link, padrao: 430) == NotchMetrics.linkCardWidth,
               "link com página mudou de largura")
        exigir(NotchMetrics.larguraDoCard(nil, padrao: 430) == 430, "sem foco mudou de largura")

        // medidas do mockup (relatorio.md, "Medidas"), lidas pelas telas das próximas etapas
        exigir(NotchMetrics.whatsappLargura == 780, "whatsappLargura")
        exigir(NotchMetrics.whatsappAltura == 360, "whatsappAltura")
        exigir(NotchMetrics.whatsappListaLargura == 260, "whatsappListaLargura")
        exigir(NotchMetrics.whatsappCartaoLargura == 360, "whatsappCartaoLargura")
        exigir(NotchMetrics.whatsappCartaoAltura == 96, "whatsappCartaoAltura")
        exigir(NotchMetrics.whatsappCartaoMiniatura == 126, "whatsappCartaoMiniatura")
    }

    // MARK: - moldura

    static func testApresentacao() {
        let foco = NotchContentState(expanded: true, focus: .whatsapp)
        exigir(foco.mode == .music, "card aberto no whatsapp não é .music")
        exigir(foco.keyboard, "seção whatsapp aberta não pede teclado (campo de resposta)")
        exigir(!NotchContentState(expanded: false, focus: .whatsapp).keyboard,
               "card fechado com foco whatsapp pediu teclado")
        exigir(NotchContentState(expanded: true, focus: .mensagens).keyboard, "mensagens perdeu o teclado")
        exigir(!NotchContentState(expanded: true, focus: .historico).keyboard, "histórico ganhou teclado")

        var layout = NotchPresentation.Layout()
        layout.realNotch = true
        layout.notch = CGSize(width: 200, height: 32)
        layout.sectionWidth = NotchMetrics.larguraDoCard(.whatsapp, padrao: 430)
        layout.sectionHeight = NotchMetrics.alturaDaSecao(.whatsapp)
        let p = NotchPresentation(content: foco, layout: layout)
        exigir(p.topInset == 32, "topo: \(p.topInset)")
        exigir(p.size == CGSize(width: 780, height: 452), "moldura do quadro A: \(p.size)")
        exigir(p.keyboard, "apresentação do whatsapp sem teclado")
        exigir(p.focus == .whatsapp, "foco perdido: \(String(describing: p.focus))")

        // mesmos números escritos à mão, como o plano pede
        var literal = NotchPresentation.Layout()
        literal.sectionWidth = 780
        literal.sectionHeight = 360
        exigir(NotchPresentation(content: foco, layout: literal).size == CGSize(width: 780, height: 452),
               "moldura literal 780 × 452")

        // tela estreita: o teto é available.width - 64
        layout.available = CGSize(width: 700, height: 900)
        let estreita = NotchPresentation(content: foco, layout: layout)
        exigir(estreita.size.width == 636, "teto de largura em tela de 700: \(estreita.size.width)")
        exigir(estreita.size.height == 452, "tela estreita mexeu na altura: \(estreita.size.height)")
    }

    // MARK: - atalhos do Ações rápidas

    static func testAtalhos() {
        let a = NotchSectionOrder.atalhosOferecidos(marcados: [.cor], desinstaladas: [.monitores],
                                                    escondidas: [.whatsapp])
        exigir(a.first == .cor, "marcado não vem primeiro: \(a)")
        exigir(!a.contains(.acoesRapidas), "Ações rápidas oferecido como atalho de si mesmo")
        exigir(!a.contains(.monitores), "seção desinstalada oferecida como atalho: \(a)")
        exigir(!a.contains(.whatsapp), "whatsapp escondido oferecido como atalho: \(a)")
        exigir(a.filter { $0 == .cor }.count == 1, "marcado repetido: \(a)")
        exigir(a == [.cor] + NotchSection.allCases.filter {
            ![.acoesRapidas, .cor, .monitores, .whatsapp].contains($0)
        }, "lista de atalhos fora da ordem: \(a)")

        // A26: marcado que está desinstalado também some (valia pra Monitores)
        let b = NotchSectionOrder.atalhosOferecidos(marcados: [.monitores, .cor], desinstaladas: [.monitores],
                                                    escondidas: [])
        exigir(!b.contains(.monitores), "marcado desinstalado continuou oferecido: \(b)")
        exigir(b.first == .cor, "marcado instalado perdeu o topo: \(b)")

        // marcado escondido some igual
        let c = NotchSectionOrder.atalhosOferecidos(marcados: [.whatsapp, .agenda], desinstaladas: [],
                                                    escondidas: [.whatsapp])
        exigir(!c.contains(.whatsapp), "marcado escondido continuou oferecido: \(c)")
        exigir(c.first == .agenda, "marcado visível perdeu o topo: \(c)")

        // com a ponte identificada e a peça instalada, o WhatsApp é oferecido
        let d = NotchSectionOrder.atalhosOferecidos(marcados: [], desinstaladas: [], escondidas: [])
        exigir(d.contains(.whatsapp), "whatsapp não oferecido com a ponte identificada: \(d)")
        exigir(!d.contains(.acoesRapidas), "Ações rápidas oferecido sem filtro")
        exigir(d == NotchSection.allCases.filter { $0 != .acoesRapidas }, "lista cheia fora da ordem: \(d)")
        let e = NotchSectionOrder.atalhosOferecidos(marcados: [.whatsapp], desinstaladas: [], escondidas: [])
        exigir(e.first == .whatsapp && e.filter { $0 == .whatsapp }.count == 1,
               "whatsapp marcado não vem primeiro ou repetiu: \(e)")
    }
}
