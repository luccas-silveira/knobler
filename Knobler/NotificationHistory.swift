//
//  NotificationHistory.swift
//  Knobler
//
//  As notificações das últimas 24 h, em memória. Fica fora do NotchViewModel
//  porque existe um view model por tela: lá dentro o histórico seria copiado
//  por monitor e cada cópia podaria sozinha.
//
//  ponytail: sem disco. NotchNotification carrega NSImage e AXUIElement, que
//  não são serializáveis — persistir exigiria um DTO paralelo. Notificação é
//  efêmera; reiniciou o app, zerou. Virar disco se alguém reclamar de perda.
//

import Foundation

final class NotificationHistory: ObservableObject {
    static let shared = NotificationHistory()

    /// Mais recente primeiro.
    @Published private(set) var items: [NotchNotification] = []

    private let janela: TimeInterval = 24 * 3600

    func record(_ n: NotchNotification) {
        // o enqueue roda uma vez por tela com a mesma notificação
        guard !items.contains(where: { $0.id == n.id }) else { return }
        // progresso: mesmo webhookID substitui, igual ao enqueue faz com o card
        if let wid = n.webhookID {
            if let index = items.firstIndex(where: { $0.webhookID == wid }) {
                // Sustituição em lugar — progresso não pula pro topo
                items.remove(at: index)
                items.insert(n, at: index)
            } else {
                // Novo webhookID: depois dos outros webhooks
                if let lastWebhookIndex = items.lastIndex(where: { $0.webhookID != nil }) {
                    items.insert(n, at: lastWebhookIndex + 1)
                } else {
                    items.insert(n, at: 0)
                }
            }
        } else {
            items.insert(n, at: 0)
        }
        prune()
    }

    /// Poda na escrita — a lista só muda quando algo entra, então não há timer.
    /// O pior caso é ver um item de 24 h e 1 min se nada chegou desde então.
    func prune(now: Date = Date()) {
        items.removeAll { now.timeIntervalSince($0.date) > janela }
    }
}
