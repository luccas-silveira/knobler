//
//  Ask.swift
//  Knobler
//
//  Pergunta interativa do Claude Code (AskUserQuestion) exibida como card
//  no notch. O hook PreToolUse publica via POST /ask; o card responde e o
//  hook devolve a resposta ao Claude. Modelo espelha o payload da tool.
//

import Foundation
import SwiftUI

struct AskOption: Equatable {
    var label: String
    var description: String
    /// Mockup ASCII exibido no painel direito do card (layout split).
    var preview: String?
}

struct AskQuestion: Equatable {
    var question: String
    /// Chip curto ("Abordagem", "Layout"…) mostrado antes do título.
    var header: String
    var multiSelect: Bool
    var options: [AskOption]
}

struct AskRequest: Equatable {
    var id: String
    /// Uma chamada da tool traz 1–4 perguntas; o card pagina entre elas.
    var questions: [AskQuestion]
    var receivedAt: Date
}

/// Resposta de UMA pergunta: labels clicados e/ou texto livre digitado/ditado.
struct AskAnswer: Equatable {
    var labels: [String]
    var text: String?
}

// MARK: - Card no notch

/// Card interativo: botões de opção (toggles no multi-select), paginação
/// 1/N, preview ASCII em split e texto livre (teclado ou ditado).
struct AskCardView: View {
    @ObservedObject var vm: NotchViewModel
    let ask: AskRequest

    /// Labels marcados na página corrente (multi-select).
    @State private var selected: Set<String> = []
    /// Respostas acumuladas das páginas anteriores (pergunta → resposta).
    @State private var answers: [String: AskAnswer] = [:]
    @State private var hovered: String?
    @FocusState private var textFocused: Bool

    private var page: Int { min(vm.askPage, ask.questions.count - 1) }
    private var question: AskQuestion { ask.questions[page] }
    private var hasPreview: Bool { question.options.contains { $0.preview != nil } }
    /// Preview exibido: opção sob o mouse; sem hover, a primeira com preview.
    private var previewText: String? {
        question.options.first { $0.label == hovered }?.preview
            ?? question.options.compactMap(\.preview).first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if hasPreview {
                HStack(alignment: .top, spacing: 10) {
                    optionList.frame(width: 250)
                    preview
                }
            } else {
                optionList
            }
            footer
        }
        .foregroundStyle(.white)
        // Esc (com o campo focado) = mesmo intent do ✕: pergunta vai pro terminal
        .onExitCommand { vm.cancelActiveAsk() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !question.header.isEmpty {
                Text(question.header)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.15)))
            }
            Text(question.question)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
            if ask.questions.count > 1 {
                Text("\(page + 1)/\(ask.questions.count)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Button { vm.cancelActiveAsk() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Responder no terminal")
        }
    }

    private var optionList: some View {
        VStack(spacing: 4) {
            ForEach(question.options, id: \.label) { option in
                optionRow(option)
            }
            if question.multiSelect {
                Button { submitPage(labels: Array(selected)) } label: {
                    Text("Confirmar")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(selected.isEmpty ? 0.08 : 0.25)))
                }
                .buttonStyle(.plain)
                .disabled(selected.isEmpty)
            }
        }
    }

    private func optionRow(_ option: AskOption) -> some View {
        Button {
            if question.multiSelect {
                if selected.contains(option.label) {
                    selected.remove(option.label)
                } else {
                    selected.insert(option.label)
                }
            } else {
                submitPage(labels: [option.label])
            }
        } label: {
            HStack(spacing: 8) {
                if question.multiSelect {
                    Image(systemName: selected.contains(option.label)
                        ? "checkmark.square.fill" : "square")
                        .font(.footnote)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.footnote.weight(.semibold))
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(hovered == option.label ? 0.18 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hovered = option.label
            } else if hovered == option.label {
                hovered = nil
            }
        }
    }

    private var preview: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(previewText ?? "")
                .font(.system(size: 9, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if case .recording(let level) = vm.dictation {
                // ditado ativo alimenta este campo: nível DENTRO do card
                Circle().fill(.red).frame(width: 6, height: 6)
                Capsule().fill(.white)
                    .frame(width: max(4, 40 * CGFloat(level)), height: 4)
            }
            TextField("Outra resposta… (Enter envia; ⌥ direita dita)", text: $vm.askText)
                .textFieldStyle(.plain)
                .font(.footnote)
                .focused($textFocused)
                .onSubmit {
                    let text = vm.askText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    submitPage(labels: question.multiSelect ? Array(selected) : [],
                               text: text)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
        }
    }

    /// Grava a resposta da página; última página envia tudo de uma vez.
    private func submitPage(labels: [String], text: String? = nil) {
        answers[question.question] = AskAnswer(labels: labels, text: text)
        vm.askText = ""
        selected = []
        hovered = nil
        if page + 1 < ask.questions.count {
            vm.askPage += 1
        } else {
            vm.answerAsk(answers)
        }
    }
}
