//
//  AnnotationDeckView.swift
//  Knobler
//
//  A seção Anotação do card: um "streamdeck" de 2×4 botões iguais. A raiz tem
//  ação e submenus; cada submenu é a MESMA grade, com "Voltar" ocupando uma
//  célula. Nada de controle fora do padrão — inclusive as cores e o fundo.
//

import SwiftUI

/// Um botão da grade. Tudo que a seção oferece é um destes.
private struct DeckItem: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    /// Amostra de cor no lugar do símbolo (os botões de cor).
    var swatch: AnnotationColor?
    var ativo = false
    let acao: () -> Void
}

/// Página aberta da seção.
private enum DeckPage: Equatable {
    case raiz, ferramentas, cores, fundo
}

struct AnnotationDeckView: View {
    @ObservedObject var annotation: AnnotationController
    @State private var page: DeckPage = .raiz
    /// Página da paginação dentro de um submenu com mais de 8 itens.
    @State private var offset = 0

    /// Altura da seção: duas fileiras de botão + o respiro entre elas.
    static let alturaDoBotao: CGFloat = 50
    static let alturaDaGrade: CGFloat = alturaDoBotao * 2 + 6
    private static let colunas = 4
    private static let porPagina = 8

    /// Paleta fixa. Vira preferência quando alguém pedir.
    private static let cores: [(AnnotationColor, String)] = [
        (.yellow, "Amarelo"),
        (.init(red: 1, green: 0.23, blue: 0.19, alpha: 1), "Vermelho"),
        (.init(red: 0.2, green: 0.78, blue: 0.35, alpha: 1), "Verde"),
        (.init(red: 0.25, green: 0.55, blue: 1, alpha: 1), "Azul"),
        (.init(red: 1, green: 1, blue: 1, alpha: 1), "Branco"),
        (.init(red: 0.1, green: 0.1, blue: 0.1, alpha: 1), "Preto"),
    ]

    var body: some View {
        // grade fixa 2×4 em HStacks: o LazyVGrid mede maior do que desenha e
        // empurrava a primeira fileira pra fora do card.
        VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { linha in
                HStack(spacing: 6) {
                    ForEach(0..<Self.colunas, id: \.self) { coluna in
                        let i = linha * Self.colunas + coluna
                        if i < pagina.count { botao(pagina[i]) } else { celulaVazia }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        // trocar de página zera a paginação: sem isto, entrar num submenu curto
        // depois de paginar num longo mostraria uma grade vazia.
        .onChange(of: page) { _, _ in offset = 0 }
    }

    // MARK: - Conteúdo de cada página

    private var itens: [DeckItem] {
        switch page {
        case .raiz: return raiz
        case .ferramentas: return ferramentas
        case .cores: return cores
        case .fundo: return fundo
        }
    }

    /// A fatia visível, com a última célula reservada pra navegação quando a
    /// lista não cabe nas oito.
    private var pagina: [DeckItem] {
        let todos = itens
        guard todos.count > Self.porPagina else { return todos }
        let inicio = offset * (Self.porPagina - 1)
        let fim = min(inicio + Self.porPagina - 1, todos.count)
        let fatia = Array(todos[inicio..<fim])
        // "Mais" só na página que ainda tem sobra; a última já traz o "Voltar"
        // que veio da própria lista.
        guard fim < todos.count else { return fatia }
        return fatia + [DeckItem(symbol: "ellipsis", title: "Mais") { offset += 1 }]
    }

    private var raiz: [DeckItem] {
        [
            DeckItem(symbol: annotation.isActive ? "pencil.tip.crop.circle.fill"
                                                 : "pencil.tip.crop.circle",
                     title: annotation.isActive ? "Desenhando" : "Desenhar",
                     ativo: annotation.isActive) { annotation.toggle() },
            DeckItem(symbol: annotation.selectedTool.symbol,
                     title: "Ferramenta") { page = .ferramentas },
            DeckItem(symbol: "paintpalette", title: "Cor",
                     swatch: annotation.selectedColor) { page = .cores },
            DeckItem(symbol: fundoSymbol, title: "Fundo",
                     ativo: annotation.background != .transparent) { page = .fundo },
            DeckItem(symbol: "arrow.uturn.backward", title: "Desfazer") { annotation.undo() },
            DeckItem(symbol: "arrow.uturn.forward", title: "Refazer") { annotation.redo() },
            DeckItem(symbol: "trash", title: "Apagar") { annotation.clear() },
            DeckItem(symbol: "eraser", title: "Borracha",
                     ativo: annotation.selectedTool == .eraser) { annotation.select(tool: .eraser) },
        ]
    }

    private var ferramentas: [DeckItem] {
        AnnotationTool.allCases.map { tool in
            DeckItem(symbol: tool.symbol, title: tool.title,
                     ativo: annotation.selectedTool == tool) {
                annotation.select(tool: tool)
                page = .raiz
            }
        } + [voltar]
    }

    private var cores: [DeckItem] {
        Self.cores.map { cor, nome in
            DeckItem(symbol: "circle.fill", title: nome, swatch: cor,
                     ativo: annotation.selectedColor == cor) {
                annotation.setColor(cor)
                page = .raiz
            }
        } + [
            DeckItem(symbol: "eyedropper", title: "Outra…") {
                ColorPicker.pick(format: .hex) { escolhida in
                    if let escolhida { annotation.setColor(escolhida) }
                }
                page = .raiz
            },
            voltar,
        ]
    }

    private var fundo: [DeckItem] {
        AnnotationBackground.allCases.map { fundo in
            DeckItem(symbol: Self.symbol(fundo), title: fundo.title,
                     ativo: annotation.background == fundo) {
                annotation.setBackground(fundo)
                page = .raiz
            }
        } + [voltar]
    }

    private var voltar: DeckItem {
        DeckItem(symbol: "chevron.backward", title: "Voltar") { page = .raiz }
    }

    private var fundoSymbol: String { Self.symbol(annotation.background) }

    private static func symbol(_ fundo: AnnotationBackground) -> String {
        switch fundo {
        case .transparent: return "square.dashed"
        case .white: return "square.fill"
        case .black: return "square"
        }
    }

    // MARK: - O botão (o único desenho da seção)

    /// Buraco da grade: mesma caixa, sem conteúdo — a fileira não pode encolher.
    private var celulaVazia: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(.white.opacity(0.03))
            .frame(maxWidth: .infinity)
            .frame(height: Self.alturaDoBotao)
    }

    private func botao(_ item: DeckItem) -> some View {
        Button(action: item.acao) {
            VStack(spacing: 3) {
                if let swatch = item.swatch, item.symbol != "paintpalette" {
                    Circle()
                        .fill(Color(.sRGB, red: swatch.red, green: swatch.green, blue: swatch.blue))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                } else if let swatch = item.swatch {
                    Image(systemName: item.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(.sRGB, red: swatch.red,
                                               green: swatch.green, blue: swatch.blue))
                } else {
                    Image(systemName: item.symbol)
                        .font(.system(size: 15, weight: .medium))
                }
                Text(item.title)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white.opacity(item.ativo ? 1 : 0.7))
            .frame(maxWidth: .infinity)
            .frame(height: Self.alturaDoBotao)
            .background(RoundedRectangle(cornerRadius: 9)
                .fill(.white.opacity(item.ativo ? 0.24 : 0.09)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }
}
