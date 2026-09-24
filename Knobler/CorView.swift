import SwiftUI
import AppKit

/// Conta-gotas + últimas cores. Tocar numa cor recopia o HEX.
struct CorView: View {
    @ObservedObject var cores = CoresRecentes.shared

    var body: some View {
        HStack(spacing: 12) {
            // o pick registra no CoresRecentes sozinho: ponto único de entrada
            Button { ColorPicker.pick(format: .hex) { _ in } } label: {
                Image(systemName: "eyedropper").font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Selecionar cor")
            if cores.lista.isEmpty {
                Text("As cores escolhidas aparecem aqui").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 4), spacing: 8) {
                    ForEach(cores.lista, id: \.self) { hex in
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(hex, forType: .string)
                        } label: {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(cor: AnnotationColor(hex: hex) ?? .yellow))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .help("Copiar \(hex)")
                        .accessibilityLabel("Copiar \(hex)")
                    }
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
    }
}

extension Color {
    init(cor: AnnotationColor) {
        self.init(red: cor.red, green: cor.green, blue: cor.blue, opacity: cor.alpha)
    }
}
