//
//  PluginsSettingsPane.swift
//  Knobler
//
//  A vitrine de peças: o painel "Plugins" da barra lateral de Ajustes.
//  É a Fase 4 do mapa `.wayfinder/marketplace`, e o desenho é cópia do
//  protótipo `prototypes/006-tela-de-plugins.swift` — o ticket manda copiar,
//  não redesenhar.
//
//  As três decisões que a tela encarna:
//  - Duas seções fixas: "Incluído no Knobler" (as 4 de fábrica, sem ação) e
//    "Plugins" (as 11). O card NÃO muda de lugar ao instalar — só o botão muda.
//  - Capa = o símbolo SF da própria ficha sobre o degradê da cor dela. Zero arte
//    nova; é a mesma linguagem dos ícones da barra lateral.
//  - Desinstalar não pergunta nada (007): não há perda, e reinstalar é o
//    desfazer. O aviso mora no próprio item do menu.
//

import SwiftUI

// MARK: - A cor da capa

/// A cor de cada peça. Mora aqui, e não na ficha, porque `Plugin.swift` é
/// Foundation puro de propósito (é o que deixa o `plugincheck` compilar a
/// máquina de peças sem arrastar SwiftUI).
private func corDaPeca(_ id: PluginID) -> Color {
    switch id {
    case .pomodoro: return .red
    case .lembretes: return .orange
    case .descanso: return .indigo
    case .mensagens: return .green
    case .webhooks: return .purple
    case .ditado: return .blue
    case .espelho: return .teal
    case .anotacao: return .yellow
    case .notaRapida: return .orange
    case .previewLink: return .blue
    case .conversao: return .mint
    }
}

/// As quatro de fábrica não têm `PluginID`; a cor vem por posição na lista do
/// registro, que é literal e não muda sozinha.
private let coresDeFabrica: [Color] = [.pink, .red, .brown, .gray]

// MARK: - O card

private struct CardPeca<Botao: View>: View {
    let nome: String
    let descricao: String
    let simbolo: String
    let cor: Color
    @ViewBuilder var botao: () -> Botao

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cor.gradient)
                .frame(height: 84)
                .overlay(
                    Image(systemName: simbolo)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                )

            Text(nome)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Text(descricao)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                // reservesSpace: sem isso o card de frase curta encolhe e a
                // grade fica com os botões em alturas diferentes.
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                botao()
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background.secondary))
    }
}

/// A pílula. Só duas aparências: a cheia (INSTALAR, a ação que se quer) e a
/// apagada (ABRIR e "Incluído", que não disputam atenção).
private struct Pilula: View {
    let texto: String
    var cheia = false

    var body: some View {
        Text(texto)
            .font(.system(size: 11, weight: cheia ? .bold : .semibold))
            .foregroundStyle(cheia ? Color.white : .secondary)
            .padding(.horizontal, cheia ? 14 : 12)
            .frame(height: 22)
            .background(
                Capsule().fill(cheia ? AnyShapeStyle(Color.accentColor)
                                     : AnyShapeStyle(.quaternary)))
    }
}

// MARK: - O painel

struct PluginsSettingsPane: View {
    @ObservedObject var router: SettingsRouter
    @ObservedObject private var host = PluginHost.shared

    private let colunas = [GridItem(.adaptive(minimum: 190), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                secao("Incluído no Knobler") {
                    ForEach(Array(PluginRegistry.deFabrica.enumerated()), id: \.offset) { i, peca in
                        CardPeca(nome: peca.nome, descricao: peca.descricao,
                                 simbolo: peca.simbolo,
                                 cor: coresDeFabrica[i % coresDeFabrica.count]) {
                            // De fábrica não instala nem desinstala: substitui
                            // algo que o macOS já fazia (002).
                            Pilula(texto: "Incluído")
                        }
                    }
                }

                secao("Plugins") {
                    ForEach(PluginRegistry.todos, id: \.id) { peca in
                        CardPeca(nome: peca.nome, descricao: peca.descricao,
                                 simbolo: peca.simbolo, cor: corDaPeca(peca.id)) {
                            acao(peca)
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    private func secao<Conteudo: View>(_ titulo: String,
                                       @ViewBuilder _ cards: () -> Conteudo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titulo).font(.system(size: 15, weight: .bold))
            LazyVGrid(columns: colunas, alignment: .leading, spacing: 12, content: cards)
        }
    }

    @ViewBuilder private func acao(_ peca: Plugin) -> some View {
        switch host.estadoDoCard(peca.id) {
        case .emBreve:
            // Card mudo (009): sem botão e sem "⋯". Instalar o que ainda não
            // nasce por aqui seria mentira.
            Text("Em breve")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(height: 22)

        case .instalar:
            Button { host.instalar(peca.id) } label: {
                Pilula(texto: "INSTALAR", cheia: true)
            }
            .buttonStyle(.plain)

        case .abrir:
            Button { abrir(peca) } label: { Pilula(texto: "ABRIR") }
                .buttonStyle(.plain)

            Menu {
                // Sem "tem certeza?" (007): não há perda a proteger, e perguntar
                // ensinaria um medo falso. O aviso é o próprio rótulo.
                Button("Desinstalar (seus dados ficam salvos)") {
                    host.desinstalar(peca.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
                    .background(Capsule().fill(.quaternary))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
    }

    /// ABRIR é sempre vivo (convenção da App Store: peça instalada nunca vira
    /// rótulo cinza morto). Peça com painel navega pra ele; sem painel, o
    /// `switch` abaixo decide a ação — a decisão mora na view (não na ficha,
    /// que é Foundation puro) porque toda ação passa por AppKit/SwiftUI (ver
    /// "O ABRIR das peças sem painel" no plano desta etapa).
    private func abrir(_ peca: Plugin) {
        guard let painel = peca.painel.flatMap(SettingsPane.init(rawValue:)) else {
            switch peca.id {
            case .espelho:
                // Acende a câmera no notch da tela principal — a mesma
                // chamada que a rota `POST /mirror` usa.
                if let vm = KnoblerMain.delegate.viewModelPrincipal() {
                    MirrorController.activate(on: vm, expand: true)
                }
            case .notaRapida:
                // Mesmo interruptor do item de menu, mas na tela principal:
                // aqui o mouse está sobre a janela de Ajustes, não sobre um
                // notch, então "tela sob o mouse" não faria sentido (mesmo
                // precedente do Espelho acima).
                KnoblerMain.delegate.ligarDesligarNota(em: NSScreen.main)
            default:
                break
            }
            return
        }
        router.pane = painel
    }
}
