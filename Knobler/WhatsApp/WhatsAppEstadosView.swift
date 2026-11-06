import AppKit
import CoreImage
import SwiftUI

// Coluna direita da seção do WhatsApp fora da conversa: ponte fora, chave que
// não confere (ou ausente), versão incompatível, QR para parear (e expirado),
// e vazio. O carregando mora na coluna esquerda (`WAListaCarregando`, no lugar
// da lista); a direita fica em branco. Medidas do mockup (`.state`, `.cmd`, `.pair`, `.qr`,
// `.sk`, `.chip-btn` em docs/vesta/mockups/2026-11-04-whatsapp/index.html);
// textos de `WATextos`.

struct WhatsAppEstadosView: View {
    let tela: WATelaDireita
    /// A conta selecionada (a deslogada, no QR).
    let conta: WAConta?
    /// Rótulo de outra conta que segue conectada, para o apoio do QR.
    let outra: String?
    @ObservedObject var store: WhatsAppStore

    /// Quando muda, a tela do QR confere de novo se precisa pedir um pareamento.
    private struct PedidoDoQR: Equatable {
        let conta: String?
        let pareamento: WAPareamento?
    }

    var body: some View {
        switch tela {
        case .ponteFora: ponteFora
        case .chave(let ausente):
            mensagem(icone: "key", titulo: WATextos.chaveTitulo,
                     apoio: WATextos.apoioDaChave(ausente: ausente)) { botaoTentarDeNovo }
        case .incompativel:
            mensagem(icone: "exclamationmark.triangle", titulo: WATextos.incompativelTitulo,
                     apoio: WATextos.incompativelApoio) { botaoTentarDeNovo }
        case .qr, .qrExpirado: pareamento(expirado: tela == .qrExpirado)
        // as linhas de espera ficam no lugar da lista, na coluna esquerda
        case .carregando: Color.clear
        case .vazio:
            mensagem(icone: "phone.bubble.fill", titulo: WATextos.vazioTitulo,
                     apoio: WATextos.vazioApoio) { EmptyView() }
        case .conversa: EmptyView()
        }
    }

    // MARK: - Mensagem centrada (.state)

    private func mensagem<Acao: View>(icone: String, titulo: String, apoio: String,
                                      @ViewBuilder acao: () -> Acao) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icone)
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.62))
            Text(titulo)
                .font(.system(size: 13, weight: .medium))
            apoioTexto(apoio)
            acao()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func apoioTexto(_ texto: String) -> some View {
        Text(texto)
            .font(.system(size: 11))
            .lineSpacing(2)
            .foregroundStyle(.white.opacity(0.62))
            .frame(maxWidth: 330)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var botaoTentarDeNovo: some View {
        WABotaoChip(titulo: WATextos.tentarDeNovo, icone: "arrow.clockwise") {
            Task { await store.tentarDeNovo() }
        }
    }

    // MARK: - Ponte fora (.cmd)

    private var ponteFora: some View {
        mensagem(icone: "powerplug", titulo: WATextos.ponteForaTitulo, apoio: WATextos.ponteForaApoio) {
            HStack(spacing: 6) {
                Text(WATextos.ponteForaComando)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                WABotaoIcone(icone: "doc.on.doc", rotulo: "Copiar comando") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(WATextos.ponteForaComando, forType: .string)
                }
            }
            .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 4))
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.08)))
            .padding(.top, 4)
            apoioTexto(WATextos.ponteForaRodape)
        }
    }

    // MARK: - QR (.pair)

    private func pareamento(expirado: Bool) -> some View {
        let rotulo = WACartao.rotuloDaConta(conta: conta, numero: conta?.conta ?? "")
        let titulo = WATextos.qrTitulo(rotulo: rotulo)
        // "<conta> desconectada" em destaque, o resto do título normal
        let partes = titulo.components(separatedBy: " — ")
        let destaque = partes.first ?? titulo
        let resto = partes.dropFirst().joined(separator: " — ")
        let apoio = expirado ? WATextos.qrExpiradoApoio : outra.map { WATextos.qrApoio(outra: $0) }
        return HStack(spacing: 16) {
            quadroDoQR(expirado: expirado)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Text(destaque).fontWeight(.semibold).foregroundColor(.white))\(resto.isEmpty ? "" : " — \(resto)")")
                    .foregroundStyle(.white.opacity(0.85))
                if let apoio {
                    Text(apoio).foregroundStyle(.white.opacity(0.62))
                }
            }
            .font(.system(size: 11))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .task(id: PedidoDoQR(conta: conta?.conta, pareamento: store.estado.pareamento)) {
            // conta deslogada sem pareamento em andamento: pede um, uma vez
            guard tela == .qr,
                  WhatsAppTela.precisaIniciarPareamento(conta: conta, pareamento: store.estado.pareamento)
            else { return }
            await store.iniciarPareamento()
        }
    }

    private func quadroDoQR(expirado: Bool) -> some View {
        // ponytail: expirado, a ponte não manda mais o `qr`; o código apagado
        // atrás do véu é decorativo, desenhado de um texto fixo.
        let imagem = expirado ? Self.qrApagado : WAQR.imagem(store.estado.pareamento?.qr ?? "", lado: 116)
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(expirado ? .white.opacity(0.06) : .white)
            if let imagem {
                Image(decorative: imagem, scale: 1)
                    .interpolation(.none)
                    .frame(width: 116, height: 116)
                    // apagado: só os módulos, em branco 15%
                    .opacity(expirado ? 0.15 : 1)
            }
            if expirado {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.55))
                VStack(spacing: 6) {
                    Text(WATextos.qrExpiradoTitulo)
                        .font(.system(size: 13, weight: .semibold))
                    WABotaoChip(titulo: WATextos.qrGerarOutro, icone: "arrow.clockwise") {
                        Task { await store.gerarOutroQR() }
                    }
                }
            }
        }
        .frame(width: 128, height: 128)
        .accessibilityElement(children: expirado ? .contain : .ignore)
        .accessibilityLabel(expirado ? WATextos.qrExpiradoTitulo
                                     : "QR para parear \(WACartao.rotuloDaConta(conta: conta, numero: conta?.conta ?? ""))")
    }

    /// Os módulos escuros de um QR fixo em branco opaco, o resto transparente:
    /// o código apagado atrás do véu do expirado.
    private static let qrApagado: CGImage? = {
        guard let qr = WAQR.imagem("2@qr-expirado", lado: 116) else { return nil }
        // invertido, o módulo escuro vira branco; o maskToAlpha faz do branco
        // opaco e do preto transparente
        let modulos = CIImage(cgImage: qr).applyingFilter("CIColorInvert").applyingFilter("CIMaskToAlpha")
        return CIContext(options: [.useSoftwareRenderer: true])
            .createCGImage(modulos, from: modulos.extent)
    }()
}

// MARK: - Carregando (.sk + .loadline)

/// Coluna esquerda enquanto a ponte não entrega as conversas: quatro linhas de
/// espera no lugar da lista e "Carregando conversas…" embaixo.
struct WAListaCarregando: View {
    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                ForEach(Array([0.70, 0.55, 0.85, 0.40].enumerated()), id: \.offset) { _, largura in
                    WALinhaEsqueleto(largura: largura)
                }
            }
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                WAGiro()
                Text(WATextos.carregando)
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Peças

/// `.chip-btn` do mockup: 22 pt, canto 8, branco 8% (hover 15%, apertado 25%), 11 pt.
struct WABotaoChip: View {
    let titulo: String
    let icone: String
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 4) {
                Image(systemName: icone)
                Text(titulo)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(WAEstiloChip(hover: hover))
        .onHover { hover = $0 }
    }
}

private struct WAEstiloChip: ButtonStyle {
    let hover: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(configuration.isPressed ? 0.25 : (hover ? 0.15 : 0.08))))
    }
}

/// `.ib` do mockup: ícone de 24 pt sem fundo (hover 8%).
private struct WABotaoIcone: View {
    let icone: String
    let rotulo: String
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(hover ? 1 : 0.85))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(hover ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Copiar")
        .accessibilityLabel(rotulo)
    }
}

/// Linha de espera: avatar de 28 e duas barras de 8 pt, pulsando.
private struct WALinhaEsqueleto: View {
    let largura: Double
    @State private var apagada = false

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.white.opacity(0.08)).frame(width: 28, height: 28)
            GeometryReader { g in
                VStack(alignment: .leading, spacing: 6) {
                    barra.frame(width: g.size.width * 0.40)
                    barra.frame(width: g.size.width * largura)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 28)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .opacity(apagada ? 0.5 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { apagada = true }
        }
    }

    private var barra: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.08)).frame(height: 8)
    }
}

/// Spinner desenhado à mão (o `ProgressView` não renderiza no ImageRenderer).
private struct WAGiro: View {
    @State private var girando = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(.white.opacity(0.62), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(girando ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { girando = true }
            }
    }
}
