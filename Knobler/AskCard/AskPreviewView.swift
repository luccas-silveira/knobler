//
//  AskPreviewView.swift
//  Knobler
//
//  Quadro do preview de uma opção do card de pergunta: texto monoespaçado
//  sempre inteiro, no tamanho que o `AskPreviewLayout` calculou para o maior
//  preview da pergunta. O quadro não muda de tamanho quando o destaque muda.
//

import SwiftUI

struct AskPreviewView: View {
    /// Vazio quando a opção em destaque não tem preview: o quadro fica no lugar.
    let texto: String
    let layout: AskPreviewLayout
    /// Altura de cada linha (`AskPreviewLayout.passo`), a mesma do cálculo.
    let passo: CGFloat

    var body: some View {
        Group {
            // Só rola quando nem a letra no piso fez o preview caber.
            if layout.rola {
                ScrollView([.vertical, .horizontal]) { linhas }
            } else {
                linhas
            }
        }
        .padding(.horizontal, AskPreviewLayout.dentro / 2)
        .padding(.vertical, AskPreviewLayout.vertical / 2)
        // Largura: a que o card dá (nunca menor que `layout.quadro.width`, que é
        // de onde sai a largura do card). Altura: a do maior preview da pergunta.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: layout.quadro.height, alignment: .top)
        .background(RoundedRectangle(cornerRadius: AskEstilo.raio).fill(.white.opacity(AskEstilo.fundoDaLinha)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview da opção")
        .accessibilityValue(texto)
    }

    /// Uma `Text` por linha, cada uma na altura do cálculo. Num `Text` só, a
    /// altura de linha é a que o SwiftUI arredonda (14 pt a 11 pt, contra os
    /// 12,96 da fonte), e o texto passava do fundo do quadro a cada linha a mais.
    private var linhas: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(texto.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated()),
                    id: \.offset) { _, linha in
                Text(linha)
                    .font(.system(size: layout.fonte, design: .monospaced))
                    .fixedSize()
                    .frame(height: passo)
            }
        }
        .foregroundStyle(.white.opacity(AskEstilo.tintaForte))
    }
}
