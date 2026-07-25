//
//  AgentRequestCard.swift
//  Knobler
//

import SwiftUI

/// Espelho visual de uma solicitação do agente. Todo texto recebido permanece
/// texto: a única ação possível é devolver uma opção já oferecida ao agente.
struct AgentRequestCard: View {
    let request: AgentRequest
    let store: AgentRequestStore
    @Binding var expanded: Bool
    var detailsSelectable = true

    private var summary: String {
        let limit = 160
        guard request.summary.count > limit else { return request.summary }
        return String(request.summary.prefix(limit - 1)) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(expanded ? 4 : 2)
            if expanded, let details = request.details, !details.isEmpty {
                Group {
                    if detailsSelectable {
                        ScrollView {
                            detailsText(details).textSelection(.enabled)
                        }
                    } else {
                        detailsText(details).lineLimit(8)
                    }
                }
                .frame(maxHeight: 128, alignment: .topLeading)
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.07)))
            }
            HStack(spacing: 6) {
                if request.details?.isEmpty == false {
                    Button(expanded ? "Ocultar detalhes" : "Ver detalhes") {
                        expanded.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                ForEach(request.actions.indices, id: \.self) { index in
                    let action = request.actions[index]
                    Button(actionLabel(action)) {
                        store.resolve(id: request.id, action: action)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(actionTint(action)))
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: request.agent == .claude ? "sparkles" : "chevron.left.forwardslash.chevron.right")
                .font(.caption.weight(.semibold))
            Text(request.agent == .claude ? "Claude" : "Codex")
                .font(.caption.weight(.semibold))
            Text(request.kind == .permission ? "Permissão" : "Pergunta")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.15)))
            Text(request.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(sourceLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
            Button {
                store.dismiss(id: request.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Manter no agente")
        }
    }

    private var sourceLabel: String {
        switch request.source {
        case .terminal: return "Terminal"
        case .cli: return "CLI"
        case .ide: return "IDE"
        }
    }

    private func detailsText(_ details: String) -> some View {
        Text(details)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.82))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func actionLabel(_ action: AgentRequestAction) -> String {
        switch action {
        case .allow: return "Permitir"
        case .allowForSession: return "Permitir na sessão"
        case .deny: return "Negar"
        case .cancel: return "Cancelar"
        case .option(let value), .text(let value): return value
        }
    }

    private func actionTint(_ action: AgentRequestAction) -> Color {
        switch action {
        case .allow, .allowForSession: return .green.opacity(0.72)
        case .deny, .cancel: return .red.opacity(0.72)
        case .option, .text: return .white.opacity(0.16)
        }
    }
}
