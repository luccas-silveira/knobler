//
//  AskRodapeView.swift
//  Knobler
//
//  Rodapé do card de pergunta: o campo de texto livre (teclado ou ditado) e a
//  legenda de teclas.
//

import SwiftUI

struct AskRodapeView: View {
    @Binding var texto: String
    var foco: FocusState<Bool>.Binding
    /// Nível do microfone quando o ditado está gravando; `nil` fora dele.
    let nivelDoDitado: CGFloat?
    let itens: [AskLegendaItem]
    let enviar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            campo
            legenda
        }
    }

    private var campo: some View {
        HStack(spacing: 8) {
            if let nivelDoDitado {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Capsule().fill(.white)
                        .frame(width: max(4, 40 * nivelDoDitado), height: 4)
                }
                .accessibilityLabel("Ditado gravando")
            }
            TextField("", text: $texto)
                .textFieldStyle(.plain)
                .focused(foco)
                .onSubmit(enviar)
                .accessibilityLabel("Outra resposta")
                // placeholder desenhado: o `prompt` do TextField ignora a cor no macOS
                .background(alignment: .leading) {
                    if texto.isEmpty {
                        Text("Outra resposta…")
                            .foregroundStyle(.white.opacity(AskEstilo.tintaApagada))
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                }
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: AskEstilo.raio).fill(.white.opacity(AskEstilo.fundoDoCampo)))
        .overlay(RoundedRectangle(cornerRadius: AskEstilo.raio)
            .strokeBorder(.white.opacity(foco.wrappedValue ? AskEstilo.anel : 0), lineWidth: 1))
    }

    private var legenda: some View {
        HStack(spacing: 8) {
            ForEach(Array(itens.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    ForEach(item.teclas, id: \.self) { tecla in
                        AskSeloView(texto: tecla)
                    }
                    Text(item.texto)
                }
            }
        }
        .font(AskEstilo.miudo)
        .foregroundStyle(.white.opacity(AskEstilo.tintaSecundaria))
        .lineLimit(1)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
    }
}
