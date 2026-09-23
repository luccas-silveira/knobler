//
//  AirPodsViews.swift
//  Knobler
//
//  Ilha compacta (conexão) e card grande (hover / bateria baixa) dos AirPods,
//  no ritmo do iPhone: fone quica, anéis de bateria enchem.
//

import SwiftUI

/// Anel de bateria: verde normal, vermelho ≤ 10 %, trilho vazio sem leitura.
/// Enche de 0 até o nível ao aparecer, depois de `delay` (cascata do card).
struct BatteryRingView: View {
    let level: Int?
    var delay: Double = 0
    var lineWidth: CGFloat = 3
    /// ponytail: chave global pro harness de snapshot desenhar o nível final
    /// (o ImageRenderer não roda o onAppear animado). Trocar por injeção se
    /// outra view precisar do mesmo.
    static var animaEntrada = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cheio = !BatteryRingView.animaEntrada

    var body: some View {
        Group {
            if let level {
                ActivityRingView(progress: cheio || reduceMotion ? Double(level) / 100 : 0,
                                 color: AirPodsBattery.isLow(level) ? .red : .green,
                                 lineWidth: lineWidth)
            } else {
                Circle().stroke(.white.opacity(0.25), lineWidth: lineWidth)
            }
        }
        .onAppear {
            guard !cheio else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { cheio = true }
        }
    }
}

/// Ilha de conexão: fone do modelo à esquerda, anel + número à direita.
struct AirPodsIslandView: View {
    let battery: AirPodsBattery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulos = 0

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: battery.model.pairSymbol)
                .font(.subheadline)
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: pulos)
                .padding(.leading, 16)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let level = battery.islandLevel {
                    Text("\(level)%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AirPodsBattery.isLow(level) ? .red : .white)
                }
                BatteryRingView(level: battery.islandLevel, lineWidth: 2.5)
                    .frame(width: 16, height: 16)
            }
            .padding(.trailing, 16)
        }
        .onAppear { if !reduceMotion { pulos += 1 } }
    }
}

/// Fotos reais dos AirPods que o próprio macOS usa no aviso de conexão, lidas
/// do sistema em runtime (nunca copiadas pro app). 44 pt de origem.
enum AirPodsFotos {
    // ponytail: bundle privado do sistema; se a Apple mover ou renomear, a
    // foto vem nil e o card cai nos SF Symbols.
    private static let bundle = Bundle(path: "/System/Library/CoreServices/BluetoothUIService.app")
    private static var cache: [String: NSImage] = [:]

    static func foto(_ ids: [Int], estojo: Bool) -> NSImage? {
        for id in ids {
            let nome = "Banner-PID-\(id)" + (estojo ? "-Case" : "")
            if let img = cache[nome] ?? bundle?.image(forResource: nome) {
                cache[nome] = img
                return img
            }
        }
        return nil
    }
}

/// Card grande, no desenho do popup do iPhone: nome no topo; fones e estojo
/// lado a lado, cada um com foto, anel e porcentagem embaixo.
struct AirPodsCardView: View {
    let battery: AirPodsBattery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entrou = !BatteryRingView.animaEntrada

    var body: some View {
        let ids = battery.model.photoIDs(productID: battery.productID)
        VStack(spacing: 12) {
            Text(battery.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            HStack(spacing: 48) {
                peca(AirPodsFotos.foto(ids, estojo: false), battery.model.pairSymbol,
                     battery.islandLevel, "Fones", delay: 0)
                if let estojo = battery.model.caseSymbol {
                    peca(AirPodsFotos.foto(ids, estojo: true), estojo,
                         battery.case_, "Estojo", delay: 0.12)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !entrou else { return }
            if reduceMotion { entrou = true } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { entrou = true }
            }
        }
    }

    private func peca(_ foto: NSImage?, _ simbolo: String, _ level: Int?, _ rotulo: String,
                      delay: Double) -> some View {
        VStack(spacing: 8) {
            Group {
                if let foto {
                    Image(nsImage: foto).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: simbolo).font(.system(size: 34)).foregroundStyle(.white)
                }
            }
            .frame(width: 72, height: 72)
            // entra "quicando", como o popup do iPhone
            .scaleEffect(entrou ? 1 : 0.7)
            .opacity(entrou ? 1 : 0)
            BatteryRingView(level: level, delay: delay)
                .frame(width: 26, height: 26)
            Text(level.map { "\($0)%" } ?? "—")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(level.map(AirPodsBattery.isLow) == true ? .red : .white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rotulo): \(level.map { "\($0)%" } ?? "sem leitura")")
    }
}
