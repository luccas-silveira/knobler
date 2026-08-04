//
//  WebhookAssistant.swift
//  Knobler
//
//  A parte SEM tela do assistente de perfis (decisões 004/013): quais passos
//  existem, em que passo uma retomada cai e o que a linha do perfil diz.
//
//  O passo de retomada é DERIVADO do estado do perfil no relay — não existe
//  campo "passo em que parei" (seria um segundo estado pra manter em sincronia).
//
//  Sem SwiftUI de propósito: o gate (`tools/assistentecheck.swift`) compila só
//  este arquivo.
//

import Foundation

enum PassoAssistente: Int, CaseIterable {
    case nome, servico, link, primeiroEnvio, mapa

    var titulo: String {
        switch self {
        case .nome: return "Nome"
        case .servico: return "Serviço"
        case .link: return "Link"
        case .primeiroEnvio: return "Primeiro envio"
        case .mapa: return "Mapa"
        }
    }

    var proximo: PassoAssistente? { PassoAssistente(rawValue: rawValue + 1) }
    var anterior: PassoAssistente? { PassoAssistente(rawValue: rawValue - 1) }

    /// Onde a retomada cai, a partir do estado do perfil. `nil` = não é retomada:
    /// já tem mapa, então o clique abre o editor direto, sem assistente (013).
    static func retomada(hasMapping: Bool, lastPayloadAt: Double?) -> PassoAssistente? {
        if hasMapping { return nil }
        return lastPayloadAt == nil ? .primeiroEnvio : .mapa
    }
}

enum EstadoDoPerfil {
    /// Legenda da linha do perfil no painel (004: estado, não "Campos mapeados").
    /// `agora`/`lastPayloadAt` em segundos desde 1970.
    static func legenda(hasMapping: Bool, lastPayloadAt: Double?, agora: Double) -> String {
        guard let at = lastPayloadAt else {
            return hasMapping ? "Mapeado — esperando o primeiro envio"
                              : "Esperando o primeiro envio"
        }
        let quando = haQuantoTempo(agora - at)
        return hasMapping ? "Último webhook \(quando)"
                          : "Sem mapa — último webhook \(quando)"
    }

    /// "agora", "há 3 min", "há 5 h", "há 2 d". Formatação própria em vez de
    /// `RelativeDateTimeFormatter` porque este texto entra num gate — o do
    /// Foundation muda com o locale da máquina.
    static func haQuantoTempo(_ segundos: Double) -> String {
        let s = max(0, segundos)
        if s < 60 { return "agora" }
        if s < 3600 { return "há \(Int(s / 60)) min" }
        if s < 86_400 { return "há \(Int(s / 3600)) h" }
        return "há \(Int(s / 86_400)) d"
    }
}
