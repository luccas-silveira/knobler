//
//  NotificationHistory.swift
//  Knobler
//
//  As notificações das últimas 24 h, em memória. Fica fora do NotchViewModel
//  porque existe um view model por tela: lá dentro o histórico seria copiado
//  por monitor e cada cópia podaria sozinha.
//
//  ponytail: sem disco porque notificação é efêmera por natureza — passou,
//  passou; reiniciou o app, zerou. Serializar seria quase de graça (os campos
//  são String/UUID/Bool; só `iconColor: NSColor?` precisaria de tratamento),
//  então o motivo NÃO é impedimento técnico: é que guardar em disco por 24 h
//  não vale o arquivo. Virar disco se alguém reclamar de perda num restart.
//

import Foundation

final class NotificationHistory: ObservableObject {
    static let shared = NotificationHistory()

    /// Mais recente primeiro.
    @Published private(set) var items: [NotchNotification] = []

    private let janela: TimeInterval = 24 * 3600
    /// ponytail: teto duro de linhas. A poda por idade sozinha não segura uma
    /// fonte que emita `webhookID` distinto em rajada — em 24 h a lista cresce
    /// sem limite e o `record` é O(n) por inserção. 300 é muito mais do que
    /// alguém lê numa cortina de 260 pt; quem precisar de mais precisa de
    /// busca, não de teto maior.
    private let capacidade = 300

    func record(_ n: NotchNotification) {
        // o enqueue roda uma vez por tela com a mesma notificação
        guard !items.contains(where: { $0.id == n.id }) else { return }
        // progresso: mesmo webhookID substitui, igual ao enqueue faz com o card
        if let wid = n.webhookID { items.removeAll { $0.webhookID == wid } }
        items.insert(n, at: 0)
        prune()
        if items.count > capacidade { items.removeLast(items.count - capacidade) }
    }

    /// Poda na escrita — a lista só muda quando algo entra, então não há timer.
    /// O pior caso é ver um item de 24 h e 1 min se nada chegou desde então.
    func prune(now: Date = Date()) {
        items.removeAll { now.timeIntervalSince($0.date) > janela }
    }
}
