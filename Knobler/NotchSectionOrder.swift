//
//  NotchSectionOrder.swift
//  Knobler
//
//  A parte pura da hierarquia do card aberto: quem aparece e em que ordem.
//  Sem AppKit/SwiftUI de propósito — é o que permite rodar isto no
//  sectionordercheck sem subir o app, como o NotchGesture faz com o scroll.
//

import Foundation

/// Uma seção do card expandido. O `rawValue` é o que vai pro UserDefaults e
/// pro `GET /status`, então renomear um caso quebra ordem salva de usuário.
enum NotchSection: String, CaseIterable {
    case musica, atividade, pomodoro, shelf, espelho, mensagens, historico, nota
}

/// O que o VM sabe de uma seção no instante em que o card abre.
struct NotchSectionState: Equatable {
    let section: NotchSection
    /// Tem o que mostrar? Sem música tocando, shelf vazio, Pomodoro idle → false.
    let hasContent: Bool
    /// Último **evento de transição** (troca de faixa, virada de fase, item
    /// novo). Nunca é o tique de progresso: `remaining` do Pomodoro e a posição
    /// da música mudam a cada segundo e promoveriam essas duas pra sempre.
    let lastEvent: Date?
}

enum NotchSectionOrder {
    /// Ordem de fábrica, usada quando não há nada salvo nos Ajustes.
    static let padrao: [NotchSection] = [
        .musica, .atividade, .pomodoro, .shelf, .espelho, .mensagens, .historico, .nota,
    ]

    /// Quanto tempo um evento continua promovendo a seção dele.
    ///
    /// ponytail: janela fixa em vez de preferência. Vira ajuste se alguém
    /// reclamar; o card vive segundos e ninguém cronometra isso.
    static let janelaDePromocao: TimeInterval = 10

    /// Ordem efetiva do card. Calculada UMA vez, na abertura — o congelamento
    /// é de quem chama (o VM), não daqui.
    ///
    /// - Parameters:
    ///   - base: ordem escolhida nos Ajustes.
    ///   - estados: o que cada seção tem a dizer agora.
    ///   - agora: injetado pra que o teste não dependa do relógio.
    ///   - travadaNaNota: usuário digitando na nota nesta tela.
    static func ordenar(base: [NotchSection],
                        estados: [NotchSectionState],
                        agora: Date,
                        travadaNaNota: Bool) -> [NotchSection] {
        let porSecao = Dictionary(uniqueKeysWithValues: estados.map { ($0.section, $0) })
        // seções fora da `base` (versão salva antiga) entram no fim, senão
        // sumiriam da UI sem ninguém perceber
        let ordemBase = base + padrao.filter { !base.contains($0) }
        let visiveis = ordemBase.filter { porSecao[$0]?.hasContent == true }

        let promovidas = visiveis
            .filter { s in
                guard let quando = porSecao[s]?.lastEvent else { return false }
                return agora.timeIntervalSince(quando) < janelaDePromocao
            }
            // mais recente primeiro; empate cai na ordem-base (sort estável não
            // é garantido em Swift, então o índice entra no critério)
            .sorted { a, b in
                let ta = porSecao[a]?.lastEvent ?? .distantPast
                let tb = porSecao[b]?.lastEvent ?? .distantPast
                if ta != tb { return ta > tb }
                return ordemBase.firstIndex(of: a)! < ordemBase.firstIndex(of: b)!
            }

        let resto = visiveis.filter { !promovidas.contains($0) }
        let ordenadas = promovidas + resto

        // digitar é o compromisso mais forte com o notch: nada tira o foco do
        // campo enquanto o teclado está nos dedos.
        guard travadaNaNota, ordenadas.contains(.nota) else { return ordenadas }
        return [.nota] + ordenadas.filter { $0 != .nota }
    }

    /// Lê a ordem do UserDefaults sem confiar nela: descarta o que não existe
    /// mais e completa o que faltou (versão antiga não conhece seção nova).
    static func sanear(salva: [String]) -> [NotchSection] {
        var vistas: [NotchSection] = []
        for raw in salva {
            guard let s = NotchSection(rawValue: raw), !vistas.contains(s) else { continue }
            vistas.append(s)
        }
        return vistas + padrao.filter { !vistas.contains($0) }
    }
}
