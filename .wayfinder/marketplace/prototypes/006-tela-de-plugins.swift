//
//  006-tela-de-plugins.swift
//  Protótipo do ticket "A tela mínima de instalar e desinstalar".
//
//  Não é código do app. É a vitrine menor que responde ao ticket: compila,
//  roda asserções sobre o comportamento dos botões e RENDERIZA um PNG pra
//  olhar (é um ticket de vitrine — sem imagem não dá pra reagir).
//
//      xcrun swiftc -parse-as-library -swift-version 5 \
//        .wayfinder/marketplace/prototypes/006-tela-de-plugins.swift \
//        -o /tmp/telaplugins && /tmp/telaplugins
//
//  Decisões do dono que a tela encarna:
//  1. Painel próprio "Plugins" na barra lateral de Ajustes (não seção do Geral).
//  2. Vitrine em GRADE de cards, não lista de linhas.
//  3. Capa = o símbolo SF da própria ficha da peça sobre degradê da cor dela.
//     Zero arte nova; é a mesma linguagem dos ícones da barra lateral.
//  4. As 4 de fábrica aparecem, marcadas "Incluído", sem botão.
//  5. Duas seções fixas: "Incluído no Knobler" e "Plugins". O card NÃO muda de
//     lugar ao instalar — só o botão muda.
//
//  ponytail: o grid do snapshot é um VStack/HStack manual em vez de
//  LazyVGrid+ScrollView — ScrollView não renderiza no ImageRenderer offscreen
//  (ver CLAUDE.md). No app real a tela usa LazyVGrid dentro de ScrollView.
//

import SwiftUI

// MARK: - O catálogo

enum PluginID: String, CaseIterable {
    case pomodoro, lembretes, descanso, mensagens, webhooks, ditado
    case espelho, anotacao, notaRapida, previewLink, conversao
}

/// A ficha da peça (forma travada no ticket 003). A vitrine só lê daqui.
struct ItemVitrine {
    let nome: String
    let descricao: String
    let simbolo: String
    let cor: Color
    /// nil = de fábrica: não instala, não desinstala, some da vitrine nunca.
    let id: PluginID?
}

enum Catalogo {
    /// De fábrica (002): substituem algo que o macOS já fazia. Sem `nascer`,
    /// sem id — a ficha existe só pra vitrine.
    static let fabrica: [ItemVitrine] = [
        .init(nome: "Música", descricao: "Faixa tocando e volume/brilho no notch.",
              simbolo: "music.note", cor: .pink, id: nil),
        .init(nome: "Notificações", descricao: "Avisos do Mac aparecem no notch.",
              simbolo: "bell.fill", cor: .red, id: nil),
        .init(nome: "Prateleira", descricao: "Arraste arquivos pro notch e leve com você.",
              simbolo: "tray.full.fill", cor: .brown, id: nil),
        .init(nome: "AirPods", descricao: "Bateria e conexão dos seus fones.",
              simbolo: "airpodspro", cor: .gray, id: nil),
    ]

    static let plugins: [ItemVitrine] = [
        .init(nome: "Pomodoro", descricao: "Ciclos de foco com pausa contada.",
              simbolo: "timer", cor: .red, id: .pomodoro),
        .init(nome: "Lembretes", descricao: "Avisos na hora certa, direto no notch.",
              simbolo: "bell.badge.fill", cor: .orange, id: .lembretes),
        .init(nome: "Descanso", descricao: "Trava a tela e obriga a levantar.",
              simbolo: "moon.zzz.fill", cor: .indigo, id: .descanso),
        .init(nome: "Mensagens", descricao: "Recados entre Macs na mesma rede.",
              simbolo: "bubble.left.and.bubble.right.fill", cor: .green, id: .mensagens),
        .init(nome: "Notificações externas", descricao: "Seus sistemas avisam pelo notch.",
              simbolo: "bell.and.waves.left.and.right.fill", cor: .purple, id: .webhooks),
        .init(nome: "Ditado", descricao: "Fale e o texto aparece onde o cursor está.",
              simbolo: "mic.fill", cor: .blue, id: .ditado),
        .init(nome: "Espelho", descricao: "Sua câmera no notch antes da reunião.",
              simbolo: "person.crop.square", cor: .teal, id: .espelho),
        .init(nome: "Anotação", descricao: "Desenhe por cima da tela.",
              simbolo: "pencil.tip.crop.circle", cor: .yellow, id: .anotacao),
        .init(nome: "Nota rápida", descricao: "Um rascunho sempre à mão no notch.",
              simbolo: "note.text", cor: .orange, id: .notaRapida),
        .init(nome: "Preview de Link", descricao: "Espia o site do link antes de abrir.",
              simbolo: "safari.fill", cor: .blue, id: .previewLink),
        .init(nome: "Conversão de arquivo", descricao: "Solte na prateleira e troque o formato.",
              simbolo: "arrow.2.squarepath", cor: .mint, id: .conversao),
    ]
}

// MARK: - O estado do botão

/// Pra onde o ABRIR leva. A convenção da App Store é que item instalado tem
/// botão VIVO ("ABRIR"), nunca um rótulo cinza morto tipo "INSTALADO" — então
/// toda peça instalada abre alguma coisa: o painel dela, se tiver, ou a
/// própria feature (o Espelho acende a câmera, a Nota rápida abre a nota).
enum AlvoDoAbrir: Equatable { case painelDeAjustes, aPropriaFeature }

/// O card não pergunta "instalado?"; ele pede o estado e desenha. Três casos —
/// e nenhum deles move o card de seção.
enum EstadoDoBotao: Equatable {
    case incluido            // de fábrica: rótulo cinza, sem ação
    case instalar            // plugin desligado
    case abrir(AlvoDoAbrir)  // plugin ligado — ABRIR é sempre vivo

    var rotulo: String {
        switch self {
        case .incluido: return "Incluído"
        case .instalar: return "INSTALAR"
        case .abrir: return "ABRIR"
        }
    }

    /// O "⋯" com Desinstalar só existe em peça instalada.
    var temMenuDeDesinstalar: Bool {
        if case .abrir = self { return true }
        return false
    }
}

/// A vitrine inteira: lê a lista de ids instalados (decisão do 005) e devolve
/// o estado de cada card. É a única regra da tela.
struct Vitrine {
    var instalados: Set<PluginID>
    /// Quais peças têm painel próprio em Ajustes (vem da ficha da peça).
    var comPainel: Set<PluginID>

    func estado(de item: ItemVitrine) -> EstadoDoBotao {
        guard let id = item.id else { return .incluido }
        guard instalados.contains(id) else { return .instalar }
        return .abrir(comPainel.contains(id) ? .painelDeAjustes : .aPropriaFeature)
    }

    mutating func alternar(_ id: PluginID) {
        if instalados.contains(id) { instalados.remove(id) } else { instalados.insert(id) }
    }
}

// MARK: - A tela

struct CardPeca: View {
    let item: ItemVitrine
    let estado: EstadoDoBotao

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A capa: o símbolo da ficha sobre o degradê da cor da ficha.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(item.cor.gradient)
                .frame(height: 84)
                .overlay(
                    Image(systemName: item.simbolo)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                )

            Text(item.nome)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Text(item.descricao)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                botao
                if estado.temMenuDeDesinstalar {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 22)
                        .background(Capsule().fill(.quaternary))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(width: 208, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background.secondary))
    }

    @ViewBuilder private var botao: some View {
        if estado == .incluido {
            Text(estado.rotulo)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).frame(height: 22)
                .background(Capsule().stroke(.quaternary, lineWidth: 1))
        } else {
            Text(estado.rotulo)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(estado == .instalar ? Color.white : .accentColor)
                .padding(.horizontal, 14).frame(height: 22)
                .background(
                    Capsule().fill(estado == .instalar
                                   ? AnyShapeStyle(Color.accentColor)
                                   : AnyShapeStyle(.quaternary)))
        }
    }
}

struct PainelPlugins: View {
    let vitrine: Vitrine
    /// 2 colunas: a área útil da janela de Ajustes é ~496pt (720 de janela
    /// menos 224 da barra lateral), e o card tem 208pt.
    let colunas = 2
    let largura: CGFloat = 496

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            secao("Incluído no Knobler", Catalogo.fabrica)
            secao("Plugins", Catalogo.plugins)
        }
        .padding(22)
        .frame(width: largura, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func secao(_ titulo: String, _ itens: [ItemVitrine]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titulo).font(.system(size: 15, weight: .bold))
            // ponytail: linhas na mão em vez de LazyVGrid — só pra o snapshot
            // offscreen funcionar; no app é LazyVGrid(columns: 3).
            ForEach(Array(stride(from: 0, to: itens.count, by: colunas)), id: \.self) { i in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(i..<min(i + colunas, itens.count), id: \.self) { j in
                        CardPeca(item: itens[j], estado: vitrine.estado(de: itens[j]))
                    }
                }
            }
        }
    }
}

// MARK: - Asserções + snapshot

@main
enum Demo {
    static func main() {
        // Fábrica e plugins batem com a decisão do 002: 4 + 11.
        assert(Catalogo.fabrica.count == 4)
        assert(Catalogo.plugins.count == 11)
        // Toda peça do enum tem card, e todo card tem peça.
        assert(Set(Catalogo.plugins.compactMap(\.id)) == Set(PluginID.allCases),
               "catálogo da vitrine não cobre o enum")

        var v = Vitrine(instalados: Set(PluginID.allCases),
                        comPainel: [.pomodoro, .lembretes, .descanso, .mensagens,
                                    .webhooks, .ditado])

        // 1. De fábrica nunca oferece desinstalar.
        for f in Catalogo.fabrica {
            assert(v.estado(de: f) == .incluido)
            assert(!v.estado(de: f).temMenuDeDesinstalar, "de fábrica ofereceu desinstalar")
        }

        // 2. Peça instalada SEMPRE diz ABRIR (convenção da App Store: nada de
        //    botão cinza morto). Muda só o alvo.
        let pomodoro = Catalogo.plugins[0]
        let notaRapida = Catalogo.plugins.first { $0.id == .notaRapida }!
        assert(v.estado(de: pomodoro) == .abrir(.painelDeAjustes))
        assert(v.estado(de: notaRapida) == .abrir(.aPropriaFeature))
        for p in Catalogo.plugins {
            assert(v.estado(de: p).rotulo == "ABRIR", "\(p.nome) não diz ABRIR")
        }

        // 3. Desinstalar troca o botão — e nada mais. O card fica na mesma
        //    seção, na mesma posição (é a razão de não separar por instalado).
        let posicaoAntes = Catalogo.plugins.firstIndex { $0.id == .pomodoro }
        v.alternar(.pomodoro)
        assert(v.estado(de: pomodoro) == .instalar)
        assert(!v.estado(de: pomodoro).temMenuDeDesinstalar)
        assert(Catalogo.plugins.firstIndex { $0.id == .pomodoro } == posicaoAntes,
               "o card mudou de lugar ao desinstalar")

        // 4. Reinstalar volta ao mesmo estado.
        v.alternar(.pomodoro)
        assert(v.estado(de: pomodoro) == .abrir(.painelDeAjustes))

        renderizar(Vitrine(instalados: Set(PluginID.allCases).subtracting([.espelho, .conversao]),
                           comPainel: [.pomodoro, .lembretes, .descanso, .mensagens,
                                       .webhooks, .ditado]))
        print("tela de plugins: ok")
    }

    @MainActor static func renderizar(_ v: Vitrine) {
        let r = ImageRenderer(content: PainelPlugins(vitrine: v))
        r.scale = 2
        guard let img = r.nsImage,
              let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { print("snapshot falhou"); return }
        let url = URL(fileURLWithPath: "/tmp/006-tela-de-plugins.png")
        try? png.write(to: url)
        print("snapshot: \(url.path)")
    }
}
