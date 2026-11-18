//
//  AskSeloView.swift
//  Knobler
//
//  Selo "Claude perguntou": a pergunta do Claude que chega enquanto o usuário
//  digita no notch espera atrás dele, no topo da seção em uso. Clicar abre a
//  pergunta; sair do campo (Esc, clique fora) também, sem o selo.
//

import SwiftUI

/// Cápsula com `◐ Claude perguntou` e a origem. Não é o `AskSeloView` (o selo
/// de tecla do card).
struct AskSeloDaEspera: View {
    @ObservedObject var vm: NotchViewModel
    /// Id da pergunta que o clique libera.
    let id: String
    let origem: String?
    @State private var sobOCursor = false

    var body: some View {
        Button {
            vm.perguntaLiberada = id
        } label: {
            HStack(spacing: 4) {
                Text("◐ Claude perguntou")
                    .font(AskEstilo.miudo.weight(.semibold))
                    .foregroundStyle(.white)
                if let origem, !origem.isEmpty {
                    Text(origem)
                        .font(AskEstilo.miudo)
                        .foregroundStyle(.white.opacity(AskEstilo.tintaSecundaria))
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(.white.opacity(sobOCursor ? AskEstilo.fundoMarcada
                                                                 : AskEstilo.fundoEmDestaque)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { sobOCursor = $0 }
        .help("Abrir a pergunta")
    }
}
