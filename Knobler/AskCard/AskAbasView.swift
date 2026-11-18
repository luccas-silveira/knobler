//
//  AskAbasView.swift
//  Knobler
//
//  Abas do card de pergunta: uma por pergunta da rodada, cada uma com o seu
//  estado (respondida, atual, pendente).
//

import SwiftUI

struct AskAbasView: View {
    let perguntas: [AskQuestion]
    let respostas: [String: AskAnswer]
    let pagina: Int
    let ir: (Int) -> Void

    @State private var sobre: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(perguntas.enumerated()), id: \.offset) { indice, pergunta in
                aba(indice, pergunta)
            }
        }
    }

    private func aba(_ indice: Int, _ pergunta: AskQuestion) -> some View {
        let atual = indice == pagina
        let resposta = respostas[pergunta.question]
        let pairando = sobre == indice && !atual
        let tinta = atual ? 1 : pairando ? AskEstilo.tintaForte
            : resposta != nil ? AskEstilo.tintaSecundaria : AskEstilo.tintaApagada
        let fundo = atual ? AskEstilo.fundoEmDestaque : pairando ? AskEstilo.fundoDoCampo : 0

        return Button { ir(indice) } label: {
            HStack(spacing: 4) {
                if resposta != nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                } else if atual {
                    Circle().frame(width: 5, height: 5)
                } else {
                    Circle().strokeBorder(lineWidth: 1).frame(width: 5, height: 5)
                }
                Text(pergunta.header.isEmpty ? "\(indice + 1)" : pergunta.header)
                    .fixedSize()
                if resposta != nil, !atual {
                    Text(AskResumo.texto(resposta))
                        .fontWeight(.regular)
                        .truncationMode(.tail)
                        .frame(maxWidth: 92, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .font(AskEstilo.miudo.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.white.opacity(tinta))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(.white.opacity(fundo)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { dentro in
            if dentro { sobre = indice } else if sobre == indice { sobre = nil }
        }
        .accessibilityAddTraits(atual ? .isSelected : [])
    }
}
