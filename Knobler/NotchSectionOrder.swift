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
    case musica, atividade, pomodoro, shelf, espelho, mensagens, historico, nota, link,
         anotacao

    /// Rótulo em pt-BR pros Ajustes e o `aria` da faixa.
    var titulo: String {
        switch self {
        case .musica: return "Música"
        case .atividade: return "Atividade"
        case .pomodoro: return "Pomodoro"
        case .shelf: return "Prateleira"
        case .espelho: return "Espelho"
        case .mensagens: return "Mensagens"
        case .historico: return "Histórico"
        case .nota: return "Nota rápida"
        case .link: return "Link"
        case .anotacao: return "Anotação"
        }
    }

    /// Símbolo SF da faixa de ícones e da lista de Ajustes.
    var simbolo: String {
        switch self {
        case .musica: return "music.note"
        case .atividade: return "arrow.triangle.2.circlepath"
        case .pomodoro: return "timer"
        case .shelf: return "tray.full.fill"
        case .espelho: return "person.crop.square"
        case .mensagens: return "bubble.left.and.bubble.right.fill"
        case .historico: return "bell.fill"
        case .nota: return "square.and.pencil"
        case .link: return "globe"
        case .anotacao: return "pencil.tip.crop.circle"
        }
    }
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
        .link, .anotacao,
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
    ///   - fixadas: seções que o usuário quer ver mesmo vazias.
    ///   - agora: injetado pra que o teste não dependa do relógio.
    ///   - travadaNaNota: usuário digitando na nota nesta tela.
    static func ordenar(base: [NotchSection],
                        estados: [NotchSectionState],
                        fixadas: Set<NotchSection>,
                        agora: Date,
                        travadaNaNota: Bool) -> [NotchSection] {
        // duplicata em `estados` é bug de quem chama, mas aqui não pode virar
        // trap: `uniqueKeysWithValues` derruba o app inteiro. A última entrada
        // vence — é a mais nova que o VM escreveu.
        let porSecao = Dictionary(estados.map { ($0.section, $0) }, uniquingKeysWith: { $1 })
        // seções fora da `base` (versão salva antiga) entram no fim, senão
        // sumiriam da UI sem ninguém perceber
        let ordemBase = base + padrao.filter { !base.contains($0) }
        // fixada aparece vazia, na posição da ordem-base: sem `lastEvent`
        // recente ela não é promovida, então cai onde o usuário a deixou.
        let visiveis = ordemBase.filter {
            porSecao[$0]?.hasContent == true || fixadas.contains($0)
        }

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

    /// Lê as fixadas do UserDefaults sem confiar nelas. Diferente de `sanear`,
    /// não completa nada: conjunto vazio é o estado de fábrica.
    static func sanearFixadas(salvas: [String]) -> Set<NotchSection> {
        Set(salvas.compactMap(NotchSection.init(rawValue:)))
    }
}
