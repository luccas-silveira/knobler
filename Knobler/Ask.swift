//
//  Ask.swift
//  Knobler
//
//  Pergunta interativa do Claude Code (AskUserQuestion) exibida como card
//  no notch. O hook PreToolUse publica via POST /ask; o card responde e o
//  hook devolve a resposta ao Claude. Modelo espelha o payload da tool.
//

import SwiftUI

// MARK: - Card no notch

/// Card interativo: botões de opção (toggles no multi-select), paginação
/// 1/N, preview ASCII em split e texto livre (teclado ou ditado).
struct AskCardView: View {
    @ObservedObject var vm: NotchViewModel
    let askStore: AskStore

    @State private var hovered: String?
    @FocusState private var textFocused: Bool

    private var ask: AskRequest? { askStore.state.active }
    private var page: Int {
        guard let ask else { return 0 }
        return min(askStore.state.page, ask.questions.count - 1)
    }
    private var question: AskQuestion? {
        guard let ask, ask.questions.indices.contains(page) else { return nil }
        return ask.questions[page]
    }
    private var hasPreview: Bool { question?.options.contains { $0.preview != nil } == true }

    /// Preview exibido: opção sob o mouse; sem hover, a primeira com preview.
    private var previewText: String? {
        question?.options.first { $0.label == hovered }?.preview
            ?? question?.options.compactMap(\.preview).first
    }

    var body: some View {
        Group {
            if let question {
                VStack(alignment: .leading, spacing: 8) {
                    header(question: question)
                    if hasPreview {
                        HStack(alignment: .top, spacing: 10) {
                            optionList(question: question).frame(width: 250)
                            preview
                        }
                    } else {
                        optionList(question: question)
                    }
                    footer(question: question)
                }
            }
        }
        .foregroundStyle(.white)
        // Esc (com o campo focado) = mesmo intent do ✕: pergunta vai pro terminal
        .onExitCommand { askStore.send(.cancelActive) }
    }

    private func header(question: AskQuestion) -> some View {
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
            if let source = ask?.source, !source.isEmpty {
                // quem pergunta: pasta do projeto da sessão do Claude Code
                Text("◐ \(source)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            if let ask, ask.questions.count > 1 {
                Text("\(page + 1)/\(ask.questions.count)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Button { askStore.send(.cancelActive) } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Responder no terminal")
        }
    }

    private func optionList(question: AskQuestion) -> some View {
        VStack(spacing: 4) {
            ForEach(question.options, id: \.label) { option in
                optionRow(option, question: question)
            }
            if question.multiSelect {
                Button { submitPage(labels: Array(askStore.state.selected)) } label: {
                    Text("Confirmar")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(askStore.state.selected.isEmpty ? 0.08 : 0.25)))
                }
                .buttonStyle(.plain)
                .disabled(askStore.state.selected.isEmpty)
            }
        }
    }

    private func optionRow(_ option: AskOption, question: AskQuestion) -> some View {
        Button {
            if question.multiSelect {
                askStore.send(.toggle(label: option.label))
            } else {
                submitPage(labels: [option.label])
            }
        } label: {
            HStack(spacing: 8) {
                if question.multiSelect {
                    Image(systemName: askStore.state.selected.contains(option.label)
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

    private func footer(question: AskQuestion) -> some View {
        HStack(spacing: 8) {
            if case .recording(let level) = vm.dictation {
                // ditado ativo alimenta este campo: nível DENTRO do card
                Circle().fill(.red).frame(width: 6, height: 6)
                Capsule().fill(.white)
                    .frame(width: max(4, 40 * CGFloat(level)), height: 4)
            }
            TextField("Outra resposta… (Enter envia; ⌥ direita dita)", text: textBinding)
                .textFieldStyle(.plain)
                .font(.footnote)
                .focused($textFocused)
                .onSubmit {
                    let text = askStore.state.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    submitPage(labels: question.multiSelect ? Array(askStore.state.selected) : [],
                               text: text)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { askStore.state.text },
            set: { askStore.send(.setText($0)) }
        )
    }

    /// A transição de página e a resposta final são responsabilidade do reducer.
    private func submitPage(labels: [String], text: String? = nil) {
        askStore.send(.submit(labels: labels, text: text))
        hovered = nil
    }
}
