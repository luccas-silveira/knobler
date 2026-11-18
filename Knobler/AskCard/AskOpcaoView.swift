//
//  AskOpcaoView.swift
//  Knobler
//
//  Uma linha de opção do card de pergunta: selo do número, rótulo com o selo
//  "Recomendada", descrição inteira e, na ponta direita, o visto ou a caixa.
//

import SwiftUI

struct AskOpcaoView: View {
    let indice: Int
    let rotulo: String
    let descricao: String
    let multipla: Bool
    /// Múltipla: caixa marcada. Simples: a resposta já dada a esta pergunta.
    let marcada: Bool
    let destaque: Bool
    /// O card está com o teclado: o destaque ganha contorno e os selos acendem.
    let teclado: Bool
    let pairar: (Bool) -> Void
    let clicar: () -> Void

    var body: some View {
        let partes = AskRotulo.separar(rotulo)
        Button(action: clicar) {
            HStack(alignment: .top, spacing: 8) {
                // de 9 em diante não há tecla de número: sem selo, com o espaço reservado
                if indice < 9 {
                    AskSeloView(texto: "\(indice + 1)",
                                tinta: teclado || marcada ? 1 : AskEstilo.tintaSecundaria,
                                fundo: teclado ? AskEstilo.fundoEmDestaque : AskEstilo.fundoDoCampo)
                } else {
                    Color.clear.frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(partes.texto)
                            .font(AskEstilo.rotulo)
                            .fixedSize(horizontal: false, vertical: true)
                        if partes.recomendada {
                            Text("Recomendada")
                                .font(AskEstilo.miudo.weight(.semibold))
                                .foregroundStyle(.white.opacity(AskEstilo.tintaForte))
                                .padding(.horizontal, 6)
                                .frame(height: 15)
                                .overlay(Capsule().strokeBorder(.white.opacity(AskEstilo.anel), lineWidth: 1))
                                .fixedSize()
                        }
                    }
                    if !descricao.isEmpty {
                        Text(descricao)
                            .font(AskEstilo.descricao)
                            .lineSpacing(1)
                            .foregroundStyle(.white.opacity(marcada ? AskEstilo.tintaForte : AskEstilo.tintaSecundaria))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // ZStack: sem ele a ponta vazia não reserva a coluna e o texto invade
                ZStack { ponta }.frame(width: 16, height: 16)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: AskEstilo.raio))
        }
        .buttonStyle(AskLinhaStyle(marcada: marcada, destaque: destaque, teclado: teclado))
        .onHover(perform: pairar)
        .accessibilityAddTraits(marcada ? .isSelected : [])
    }

    /// Ponta direita: visto na simples respondida; caixa de marcação na múltipla.
    @ViewBuilder
    private var ponta: some View {
        if multipla {
            ZStack {
                if marcada {
                    RoundedRectangle(cornerRadius: AskEstilo.raioDoSelo).fill(.white)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black)
                } else {
                    RoundedRectangle(cornerRadius: AskEstilo.raioDoSelo)
                        .strokeBorder(.white.opacity(AskEstilo.anel), lineWidth: 1.5)
                }
            }
            .frame(width: 13, height: 13)
        } else if marcada {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
        }
    }
}

/// Fundo da linha por estado: marcada vence o destaque, que vence o repouso;
/// o clique pressionado sobe para o fundo de marcada.
private struct AskLinhaStyle: ButtonStyle {
    let marcada: Bool
    let destaque: Bool
    let teclado: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fundo = marcada || configuration.isPressed ? AskEstilo.fundoMarcada
            : destaque ? AskEstilo.fundoEmDestaque : AskEstilo.fundoDaLinha
        configuration.label
            .background(RoundedRectangle(cornerRadius: AskEstilo.raio).fill(.white.opacity(fundo)))
            .overlay(RoundedRectangle(cornerRadius: AskEstilo.raio)
                .strokeBorder(.white.opacity(destaque && teclado ? AskEstilo.anel : 0), lineWidth: 1))
    }
}
