//
//  AgentesView.swift
//  Knobler
//
//  Seção "Agentes" do card: anéis de limite do plano (Claude, Codex) e as
//  sessões vivas com o estado de cada uma. Clique numa sessão leva à janela
//  onde ela roda.
//

import SwiftUI

struct AgentesView: View {
    @ObservedObject var agentes: AgentesUso

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !agentes.uso.isEmpty {
                HStack(spacing: 18) {
                    ForEach(["claude", "codex"], id: \.self) { id in
                        if let s = agentes.uso[id] { anel(id == "claude" ? "Claude" : "Codex", s) }
                    }
                    Spacer(minLength: 0)
                }
            }
            if agentes.sessoes.isEmpty {
                Text("Nenhuma sessão aberta")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(agentes.sessoes.prefix(4)) { s in
                Button { agentes.focar(s) } label: {
                    HStack(spacing: 8) {
                        Circle().fill(cor(s.state)).frame(width: 7, height: 7)
                        Text(s.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(s.detail).font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(rotulo(s)).font(.system(size: 11))
                            .foregroundStyle(s.state == .waiting ? .orange : .white.opacity(0.6))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(s.processID == nil)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func anel(_ nome: String, _ s: ProviderSnapshot) -> some View {
        // o provider diz qual janela o anel representa; sem isso, a primeira
        let w = s.windows.first { $0.id == s.headlineID } ?? s.windows.first
        let usado = w?.usedFraction
        return HStack(spacing: 7) {
            ActivityRingView(progress: usado.map { min($0, 1) }, color: corDoUso(usado), lineWidth: 3)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(nome).font(.system(size: 11, weight: .medium))
                HStack(spacing: 4) {
                    Text(usado.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    if let reset = w?.resetsAt, reset > Date() {
                        Text("· volta \(reset, style: .relative)")
                    }
                }
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func corDoUso(_ f: Double?) -> Color {
        guard let f else { return .white }
        return f >= 0.9 ? .red : f >= 0.7 ? .orange : .green
    }

    private func cor(_ e: AgentSession.State) -> Color {
        switch e {
        case .waiting: return .orange
        case .busy: return .blue
        case .success: return .green
        case .idle: return .gray
        }
    }

    private func rotulo(_ s: AgentSession) -> String {
        switch s.state {
        // `waitingFor` vem cru do Claude Code, em inglês; fica fora da UI.
        case .waiting: return "Esperando você"
        case .busy: return "Trabalhando"
        case .success: return "Concluída"
        case .idle: return "Ociosa"
        }
    }
}
