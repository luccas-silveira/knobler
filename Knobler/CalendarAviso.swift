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
