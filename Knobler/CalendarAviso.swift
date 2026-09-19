//
//  CalendarAviso.swift
//  Knobler
//
//  Próximo evento do calendário, já reduzido ao que a UI precisa: título e
//  quanto falta. Vive num arquivo sem dependência nenhuma de propósito — assim
//  o `calendariocheck` compila a formatação isolada, sem arrastar AppSettings.
//

import Foundation

struct CalendarAviso: Equatable {
    let titulo: String
    /// Segundos até o começo. Negativo = já começou (o countdown ainda o
    /// mantém por 1 min depois).
    let faltam: TimeInterval

    /// "agora" / "em 1 min" / "em 12 min" — arredonda pra cima.
    var quando: String {
        let minutos = Int(ceil(faltam / 60))
        switch minutos {
        case ..<1: return "agora"
        case 1: return "em 1 min"
        default: return "em \(minutos) min"
        }
    }

    /// A pílula fechada só cede o lugar do timer nos últimos 5 minutos.
    var urgente: Bool { faltam <= 5 * 60 }
}

/// Cópia em memória: a interface não retém objetos mutáveis do EventKit.
struct CalendarEvento: Equatable, Identifiable {
    let id: String
    let titulo: String
    let calendario: String
    let inicio: Date
    let fim: Date
    let diaInteiro: Bool

    func emAndamento(em agora: Date) -> Bool {
        !diaInteiro && inicio <= agora && agora < fim
    }
}

struct CalendarAgenda: Equatable {
    var dia = Calendar.current.startOfDay(for: Date())
    var atualizadoEm = Date()
    var autorizado = false
    var eventos: [CalendarEvento] = []

    static func eventosDoDia(_ eventos: [CalendarEvento], dia: Date,
                             calendario: Calendar = .current) -> [CalendarEvento] {
        guard let intervalo = calendario.dateInterval(of: .day, for: dia) else { return [] }
        return eventos.filter {
            $0.inicio < intervalo.end && ($0.fim > intervalo.start
                || ($0.inicio == $0.fim && $0.inicio >= intervalo.start))
        }.sorted {
            if $0.diaInteiro != $1.diaInteiro { return $0.diaInteiro }
            if $0.inicio != $1.inicio { return $0.inicio < $1.inicio }
            if $0.titulo != $1.titulo { return $0.titulo < $1.titulo }
            return $0.id < $1.id
        }
    }
}

struct CalendarDestino: Equatable, Identifiable {
    let id: String
    let nome: String
    let conta: String
    var padrao = false

    var rotulo: String { conta.isEmpty ? nome : "\(nome) — \(conta)" }
}

enum CalendarErro: Error, LocalizedError, Equatable {
    case titulo, datas, link, permissao, calendario, gravacao

    var errorDescription: String? {
        switch self {
        case .titulo: return "Preencha o título do evento."
        case .datas: return "O fim deve ser posterior ao início. Em dia inteiro, a data final pode ser a mesma."
        case .link: return "Use um link completo, começando com https:// ou http://."
        case .permissao: return "Permita o acesso ao calendário para salvar. Seu rascunho foi mantido."
        case .calendario: return "Escolha um calendário disponível para criação de eventos."
        case .gravacao: return "Não foi possível salvar o evento. Seu rascunho foi mantido; tente novamente."
        }
    }
}

/// Apenas em memória. O fim de dia inteiro é inclusivo no formulário.
struct CalendarRascunho: Equatable {
    var titulo = ""
    var inicio: Date
    var fim: Date
    var diaInteiro = false
    var calendarioID = ""
    var local = ""
    var link = ""
    var observacoes = ""

    static func novo(no dia: Date, agora: Date = Date(),
                     calendario: Calendar = .current) -> Self {
        let inicio: Date
        if calendario.isDate(dia, inSameDayAs: agora) {
            let hora = calendario.dateInterval(of: .hour, for: agora)!.start
            let minutos = (calendario.component(.minute, from: agora) / 15 + 1) * 15
            inicio = calendario.date(byAdding: .minute, value: minutos, to: hora)!
        } else {
            inicio = calendario.date(bySettingHour: 9, minute: 0, second: 0, of: dia)!
        }
        return Self(inicio: inicio, fim: inicio.addingTimeInterval(3600))
    }

    func intervalo(calendario: Calendar = .current) throws -> DateInterval {
        let inicio = diaInteiro ? calendario.startOfDay(for: inicio) : inicio
        let fim = diaInteiro
            ? calendario.date(byAdding: .day, value: 1, to: calendario.startOfDay(for: fim))!
            : fim
        guard fim > inicio else { throw CalendarErro.datas }
        return DateInterval(start: inicio, end: fim)
    }

    var url: URL? {
        let texto = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty, !texto.contains(where: \.isWhitespace),
              let url = URL(string: texto), let host = url.host, !host.isEmpty,
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    func validar(autorizado: Bool, destinos: [CalendarDestino]) throws {
        guard autorizado else { throw CalendarErro.permissao }
        guard destinos.contains(where: { $0.id == calendarioID }) else { throw CalendarErro.calendario }
        guard !titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CalendarErro.titulo }
        _ = try intervalo()
        if !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && url == nil {
            throw CalendarErro.link
        }
    }
}
