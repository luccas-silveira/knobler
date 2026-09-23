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
                HStack(alignment: .top, spacing: 18) {
                    ForEach(["claude", "codex"], id: \.self) { id in
                        if let s = agentes.uso[id] {
                            UsoDoPlano(nome: id == "claude" ? "Claude" : "Codex", snapshot: s,
                                       lidoEm: agentes.lidoEm[id])
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 4)  // respiro: limites e sessões são dois grupos
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
                            .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
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

/// Limite do plano de um provider: dois anéis concêntricos, como os do Activity
/// do Apple Watch. Fora, a janela curta (5 h); dentro, a semana. Branco no uso
/// normal: a cor só entra perto do fim, pra não disputar com o laranja de
/// "esperando você" da lista.
private struct UsoDoPlano: View {
    let nome: String
    let snapshot: ProviderSnapshot
    let lidoEm: Date?

    /// A leitura roda a cada minuto; cinco sem resposta já é dado velho.
    private var velho: Bool { lidoEm.map { Date().timeIntervalSince($0) > 5 * 60 } ?? false }
    private var curta: LimitWindow? { snapshot.headline }
    private var semana: LimitWindow? { snapshot.weeklyWindow }
    /// A janela que decide a legenda: a esgotada, senão a mais cheia.
    private var critica: LimitWindow? {
        [curta, semana].compactMap { $0 }.max { ($0.usedFraction ?? 0) < ($1.usedFraction ?? 0) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                arco(curta, raio: 15, largura: 3.5)
                if semana != nil { arco(semana, raio: 9.5, largura: 3.5) }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(nome).font(.system(size: 11, weight: .semibold))
                HStack(spacing: 6) {
                    numero(curta, "5 h")
                    if semana != nil { numero(semana, "semana") }
                }
                legenda
            }
        }
        .opacity(velho ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }

    private func arco(_ w: LimitWindow?, raio: CGFloat, largura: CGFloat) -> some View {
        let f = w?.usedFraction.map { min(max($0, 0), 1) } ?? 0
        return ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: largura)
            Circle()
                .trim(from: 0, to: f)
                .stroke(Self.cor(w?.usedFraction), style: StrokeStyle(lineWidth: largura, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: raio * 2, height: raio * 2)
    }

    private func numero(_ w: LimitWindow?, _ rotulo: String) -> some View {
        HStack(spacing: 3) {
            Text(w?.usedFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                .foregroundStyle(w?.usedFraction ?? 0 >= 0.8 ? Self.cor(w?.usedFraction) : .white.opacity(0.9))
            Text(rotulo).foregroundStyle(.white.opacity(0.55))
        }
        .font(.system(size: 10.5).monospacedDigit())
    }

    @ViewBuilder private var legenda: some View {
        Group {
            if velho, let lidoEm {
                Text("lido \(lidoEm, style: .relative) atrás")
            } else if let c = critica, (c.usedFraction ?? 0) >= 1 {
                Text(c.resetsAt.map { "esgotado até \(Self.hora($0).replacingOccurrences(of: "às ", with: ""))" } ?? "esgotado")
                    .foregroundStyle(Self.cor(1))
            } else if let reset = ((critica?.usedFraction ?? 0) >= 0.8 ? critica : curta)?.resetsAt,
                      reset > Date() {
                Text("renova \(Self.hora(reset))")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.55))
        .lineLimit(1)
    }

    /// Branco até 80%; laranja do sistema até esgotar; vermelho esgotado.
    static func cor(_ f: Double?) -> Color {
        guard let f, f >= 0.8 else { return .white }
        return f >= 1 ? Color(red: 1, green: 0.231, blue: 0.188) : Color(red: 1, green: 0.584, blue: 0)
    }

    private static func hora(_ d: Date) -> String {
        // "às 14:30" hoje; "sáb 10:02" noutro dia — curto pra caber numa linha
        let h = d.formatted(date: .omitted, time: .shortened)
        guard !Calendar.current.isDateInToday(d) else { return "às \(h)" }
        let dia = d.formatted(.dateTime.weekday(.abbreviated)).replacingOccurrences(of: ".", with: "")
        return "\(dia) \(h)"
    }
}
