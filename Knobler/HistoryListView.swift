//
//  HistoryListView.swift
//  Knobler
//
//  A cortina do histórico: o que virou card nas últimas 24 h.
//

import SwiftUI

struct HistoryListView: View {
    /// Altura da cortina. É a MESMA constante que o `currentSize` da `NotchView`
    /// soma pra dimensionar o card — mudar aqui muda o card junto. Se ela virar
    /// duas, o card fica menor que a lista e as linhas de cima somem pra fora
    /// da tela (a `.frame` centraliza o que não cabe).
    static let listHeight: CGFloat = 260

    @ObservedObject var history: NotificationHistory
    /// Chamado depois de abrir a origem: o card ao vivo se recolhe no clique e
    /// a linha do histórico faz o mesmo — senão a cortina fica aberta atrás do
    /// app que acabou de vir pra frente.
    var onOpen: () -> Void = {}

    private static let hora: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        Group {
            if history.items.isEmpty {
                Text("Nada nas últimas 24 h")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(history.items) { item in
                            linha(item)
                        }
                    }
                }
            }
        }
        .frame(height: Self.listHeight)
    }

    private func linha(_ item: NotchNotification) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.hora.string(from: item.date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 38, alignment: .leading)
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
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            NotchView.openSourceApp(item)
            onOpen()
        }
    }
}
