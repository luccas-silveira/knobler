import SwiftUI

/// Grade do Quick Actions: cada célula abre a seção, esteja ela na barra ou não.
struct AcoesRapidasView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        let atalhos = NotchSectionOrder.atalhosVisiveis(settings.acoesRapidas,
                                                        desinstaladas: NotchSection.desinstaladas())
        if atalhos.isEmpty {
            VStack(spacing: 8) {
                Text("Nenhum atalho ainda").foregroundStyle(.white.opacity(0.4))
                Button("Escolher nos Ajustes") { vm.onAbrirAjustesDoNotch?() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(atalhos, id: \.self) { s in
                    Button { vm.abrirAtalho(s) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: s.simbolo).font(.system(size: 18))
                            Text(s.titulo).font(.caption2).lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(s.titulo)
                }
            }
        }
    }
}
