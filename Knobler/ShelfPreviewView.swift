//
//  ShelfPreviewView.swift
//  Knobler
//
//  O card que a seção Prateleira mostra enquanto uma conversão espera
//  confirmação: miniatura, tamanho antes/depois, presets e os dois desfechos.
//

import SwiftUI

struct ShelfPreviewView: View {
    @ObservedObject var preview: ShelfPreview
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            miniatura
            VStack(alignment: .leading, spacing: 6) {
                cabecalho
                if preview.target.usaQualidade {
                    presets("Qualidade", ConversionOptions.Quality.allCases,
                            atual: preview.options.quality) { preview.options.quality = $0 }
                }
                if preview.target.usaEscala {
                    presets("Tamanho", ConversionOptions.Scale.allCases,
                            atual: preview.options.scale) { preview.options.scale = $0 }
                }
                botoes
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    // MARK: - Miniatura

    private var miniatura: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08))
            if let output = preview.output, let image = ShelfPreview.thumbnail(of: output) {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: preview.failed ? "exclamationmark.triangle" : "arrow.2.squarepath")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: 62, height: 62)
        .overlay(alignment: .bottom) {
            if preview.extraPages > 0 {
                Text("+\(preview.extraPages) pág.")
                    .font(.system(size: 9))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.black.opacity(0.55), in: Capsule())
                    .offset(y: 6)
            }
        }
    }

    // MARK: - Cabeçalho

    private var cabecalho: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(preview.source.lastPathComponent) → \(preview.target.label)")
                .font(.footnote.weight(.semibold))
                .lineLimit(1).truncationMode(.middle)
            if preview.running, preview.target.isSlow {
                // vídeo é o único que demora a ponto de a barra valer a pena
                ProgressView(value: preview.progress)
                    .progressViewStyle(.linear)
                    .frame(height: 3)
                    .padding(.top, 3)
            } else {
                Text(resumo)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(preview.running ? 0.35 : 0.7))
            }
        }
    }

    private var resumo: String {
        if preview.failed { return "não deu pra converter" }
        var linha = "\(ShelfPreview.formatBytes(preview.sourceBytes)) → "
            + ShelfPreview.formatBytes(preview.outputBytes)
        if let size = preview.outputPixelSize {
            linha += "  ·  \(Int(size.width))×\(Int(size.height))"
        }
        return linha
    }

    // MARK: - Presets

    private func presets<T: Hashable & PresetLabel>(
        _ titulo: String, _ opcoes: [T], atual: T,
        escolher: @escaping (T) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text(titulo)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 58, alignment: .leading)
            ForEach(opcoes, id: \.self) { opcao in
                let ativo = opcao == atual
                Button(opcao.label) { escolher(opcao) }
                    .buttonStyle(.plain)
                    .font(.caption2.weight(ativo ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(ativo ? 1 : 0.6))
                    .padding(.vertical, 3).padding(.horizontal, 8)
                    .background(.white.opacity(ativo ? 0.20 : 0.07), in: Capsule())
            }
        }
    }

    // MARK: - Desfecho

    private var botoes: some View {
        HStack(spacing: 8) {
            Button("Salvar") { shelf.confirmPreview() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.vertical, 5).padding(.horizontal, 14)
                .background(.white.opacity(0.22), in: Capsule())
                .disabled(preview.running || preview.output == nil)
                .opacity(preview.running || preview.output == nil ? 0.4 : 1)
            Button("Descartar") { shelf.cancelPreview() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.vertical, 5).padding(.horizontal, 12)
                .background(.white.opacity(0.10), in: Capsule())
        }
        .padding(.top, 2)
    }
}

/// Rótulo em pt-BR de um preset — os dois eixos respondem à mesma pergunta, e
/// isto deixa a linha de presets servir os dois sem duplicar a view.
protocol PresetLabel {
    var label: String { get }
}

extension ConversionOptions.Quality: PresetLabel {}
extension ConversionOptions.Scale: PresetLabel {}
