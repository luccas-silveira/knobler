//
//  NotificationHistory.swift
//  Knobler
//
//  As notificações das últimas 24 h. Fica fora do NotchViewModel porque existe
//  um view model por tela: lá dentro o histórico seria copiado por monitor e
//  cada cópia podaria sozinha.
//
//  Passou a persistir em disco quando o "silenciar durante reuniões" entrou:
//  notificação silenciada NÃO vira card, vai só pro histórico — e aí um restart
//  no meio da reunião apagava a única cópia dela, sem o usuário jamais saber que
//  existiu. Antes disso o argumento (que ficou aqui por meses) era que
//  notificação é efêmera e não valia o arquivo; continuava válido enquanto o
//  card era o destino principal.
//
//  Os corpos das notificações passam a ficar em claro em Application Support por
//  24 h — mesma exposição do `messages.json` que já mora na mesma pasta.
//

import Foundation

final class NotificationHistory: ObservableObject {
    static let shared = NotificationHistory(arquivo: arquivoPadrao)

    /// Mais recente primeiro.
    @Published private(set) var items: [NotchNotification] = []

    private let janela: TimeInterval = 24 * 3600
    /// ponytail: teto duro de linhas. A poda por idade sozinha não segura uma
    /// fonte que emita `webhookID` distinto em rajada — em 24 h a lista cresce
    /// sem limite e o `record` é O(n) por inserção. 300 é muito mais do que
    /// alguém lê numa seção de 260 pt; quem precisar de mais precisa de
    /// busca, não de teto maior.
    private let capacidade = 300

    /// Onde persistir. **nil = não toca disco** — é o que mantém o
    /// `historycheck` e o harness de snapshot longe do histórico real do
    /// usuário. `var` porque o snapshot desliga em runtime, depois do `shared`
    /// já ter nascido.
    var arquivo: URL?
    private var saveWork: DispatchWorkItem?

    /// Mesma pasta do `MessageStore` — dado do app, criado sob demanda.
    static var arquivoPadrao: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Knobler", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notificationHistory.json")
    }

    /// O default nil deixa as instâncias do gate nascerem sem disco, sem
    /// precisar mudar os testes que já existem.
    init(arquivo: URL? = nil) {
        self.arquivo = arquivo
        guard let arquivo,
              let data = try? Data(contentsOf: arquivo),
              let salvos = try? JSONDecoder().decode([NotchNotification].self, from: data)
        else { return }
        items = salvos
        // o arquivo pode ser de ontem: sem podar aqui, item vencido
        // ressuscitaria e ficaria até a próxima escrita
        prune()
        if items.count > capacidade { items.removeLast(items.count - capacidade) }
    }

    func record(_ n: NotchNotification) {
        // o enqueue roda uma vez por tela com a mesma notificação
        guard !items.contains(where: { $0.id == n.id }) else { return }
        // progresso: mesmo webhookID substitui, igual ao enqueue faz com o card
        if let wid = n.webhookID { items.removeAll { $0.webhookID == wid } }
        items.insert(n, at: 0)
        prune()
        if items.count > capacidade { items.removeLast(items.count - capacidade) }
        scheduleSave()
    }

    /// Poda na escrita — a lista só muda quando algo entra, então não há timer.
    /// O pior caso é ver um item de 24 h e 1 min se nada chegou desde então.
    func prune(now: Date = Date()) {
        let antes = items.count
        items.removeAll { now.timeIntervalSince($0.date) > janela }
        // só agenda escrita se algo saiu: o snapshot chama `prune(now:
        // .distantFuture)` e uma poda que não mudou nada não merece um write
        if items.count != antes { scheduleSave() }
    }

    // MARK: - Disco

    /// Debounce de 1 s, igual ao `MessageStore`: uma rajada de webhook de
    /// progresso não pode virar uma escrita por evento.
    private func scheduleSave() {
        guard arquivo != nil else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func save() {
        guard let arquivo, let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: arquivo)
    }

    /// Escreve agora — o encerramento não espera o debounce.
    func flush() {
        saveWork?.cancel()
        saveWork = nil
        save()
    }
}
