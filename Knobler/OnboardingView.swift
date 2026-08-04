//
//  OnboardingView.swift
//  Knobler
//
//  A janela de boas-vindas: um passo por vez, com o conteúdo de cada um. Quais
//  passos entram é decisão do `Onboarding` (arquivo sem dependência) — aqui só
//  se desenha o que veio filtrado.
//

import SwiftUI

struct OnboardingView: View {
    let passos: [PassoVisivel]
    /// Se os selos "Novo"/"Atualizado" fazem sentido: numa instalação nova tudo
    /// é novo e o selo é ruído.
    let mostrarNovidade: Bool
    let aoConcluir: () -> Void
    let aoIgnorar: () -> Void

    @State private var indice = 0

    private var atual: PassoVisivel? {
        passos.indices.contains(indice) ? passos[indice] : nil
    }
    private var ultimo: Bool { indice >= passos.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let atual {
                cabecalho(atual)
                Divider()
                corpo(atual.passo.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(28)
            }
            Divider()
            rodape
        }
    }

    private func cabecalho(_ visivel: PassoVisivel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if mostrarNovidade {
                Text(visivel.novidade == .novo ? "NOVO" : "ATUALIZADO")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(visivel.passo.titulo).font(.largeTitle.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func corpo(_ id: String) -> some View {
        switch id {
        case "apresentacao":
            VStack(alignment: .leading, spacing: 22) {
                linha("cursorarrow.rays", "O notch responde ao mouse",
                      "Passe o cursor sobre o notch pra abrir o card: música, "
                      + "Pomodoro, notificações, prateleira de arquivos.")
                linha("menubar.arrow.up.rectangle", "Não há Dock nem janela",
                      "O Knobler roda em segundo plano. Ajustes, nota rápida e "
                      + "o resto ficam no ícone da barra de menus, no topo da tela.")
                linha("bubble.left.and.bubble.right.fill", "Você aparece na rede local",
                      "Mensagens anuncia este Mac pra quem está na mesma rede, com o "
                      + "nome do computador. Dá pra trocar em Ajustes → Mensagens.")
            }
        case "atalhos":
            VStack(alignment: .leading, spacing: 22) {
                linha("mic.fill", "⌥ direita — ditado",
                      "Segure a tecla Option do lado direito pra falar; solte pra "
                      + "transcrever no lugar onde o cursor está.")
                linha("pencil.tip.crop.circle", "Control esquerdo — anotação",
                      "Um toque na tecla Control do lado esquerdo desenha por cima "
                      + "da tela. Esc para de desenhar; o traço fica até apagar.")
            }
        default:
            EmptyView()
        }
    }

    private func linha(_ simbolo: String, _ titulo: String, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: simbolo)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo).font(.headline)
                Text(texto).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rodape: some View {
        HStack {
            // "Ignorar" em todos os passos: quem já entendeu não precisa clicar
            // até o fim pra sair.
            Button("Ignorar", action: aoIgnorar)
            Spacer()
            if indice > 0 {
                Button("Voltar") { indice -= 1 }
            }
            Button(ultimo ? "Começar" : "Continuar") {
                if ultimo { aoConcluir() } else { indice += 1 }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }
}
