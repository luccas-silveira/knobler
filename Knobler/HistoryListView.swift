//
//  HistoryListView.swift
//  Knobler
//
//  A seção de histórico do card: o que virou card nas últimas 24 h.
//

import SwiftUI

struct HistoryListView: View {
    /// Altura da seção de histórico. É a MESMA constante que a `NotchView`
    /// soma pra dimensionar o card — mudar aqui muda o card junto. Se ela virar
    /// duas, o card fica menor que a lista e as linhas de cima somem pra fora
    /// da tela (a `.frame` centraliza o que não cabe).
    static let listHeight = NotchMetrics.historyHeight

    @ObservedObject var history: NotificationHistory
    /// Chamado depois de abrir a origem: o card ao vivo se recolhe no clique e
    /// a linha do histórico faz o mesmo — senão o card fica aberto atrás do
    /// app que acabou de vir pra frente.
    var onOpen: () -> Void = {}

    /// Linha sob o ponteiro — só ela mostra o X, senão a lista vira um mural
    /// de botões de apagar.
    @State private var hovered: UUID?

    var body: some View {
        Group {
            if history.items.isEmpty {
                Text("Nada nas últimas 24 h")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Spacer(minLength: 0)
                        Button { history.limpar() } label: {
                            Label("Limpar", systemImage: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(history.items) { item in
                                linha(item)
                            }
                        }
                    }
                }
                // o ponteiro pode sair da lista por um canto sem que o
                // `onHover(false)` da linha chegue — e aí o X ficaria aceso
                .onHover { if !$0 { hovered = nil } }
            }
        }
        .frame(height: Self.listHeight)
    }

    private func linha(_ item: NotchNotification) -> some View {
        HistoryRow(item: item, mostraX: hovered == item.id) { history.remover(item.id) }
            .contentShape(Rectangle())
            .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
            .onTapGesture {
                NotchView.openSourceApp(item)
                onOpen()
            }
    }
}

/// Uma linha do histórico. Separada da lista pra renderizar sozinha no
/// harness: a lista vive num ScrollView, que sai preto offscreen.
struct HistoryRow: View {
    let item: NotchNotification
    /// O X só aparece na linha sob o ponteiro.
    let mostraX: Bool
    let onRemove: () -> Void

    private static let hora: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.hora.string(from: item.date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 38, alignment: .leading)
            RemoteAvatarView(iconURL: item.iconURL, iconEmoji: item.iconEmoji,
                             iconColor: item.iconColor,
                             fallbackPath: NotchView.appPath(bundleID: item.bundleID,
                                                             named: item.appName),
                             escala: 0.5)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if let app = item.appName {
                        Text(app)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
                let resto = [item.subtitle, item.body].compactMap { $0 }
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                if !resto.isEmpty {
                    Text(resto)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // o `frame` fixo segura o lugar do X pra linha não dançar no hover
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .opacity(mostraX ? 1 : 0)
            .frame(width: 12)
            .help("Remover")
            .accessibilityLabel("Remover")
        }
    }
}
