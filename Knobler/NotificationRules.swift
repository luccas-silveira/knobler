//
//  NotificationRules.swift
//  Knobler
//
//  Regras puras do interceptor: o que é botão de ação e o que é alerta de
//  AirDrop. Vivem fora do `NotificationInterceptor` porque ele não compila
//  isolado (AX, AppSettings) e estas decisões precisam de teste.
//

import Foundation

enum NotificationRules {
    /// A ação de fechar pode vir com nome cru ou localizado.
    static let closeActionHints = ["close", "clear", "fechar", "limpar"]
    /// Nome de marca: o alerta do AirDrop diz "AirDrop" em qualquer idioma.
    static let airdropMarker = "airdrop"

    /// Botão que vale espelhar no card. O X de fechar não é ação: espelhá-lo
    /// daria um botão inútil que ainda por cima destrói o alerta do sistema.
    static func isActionTitle(_ title: String) -> Bool {
        let lowered = title.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lowered.isEmpty else { return false }
        return !closeActionHints.contains { lowered.contains($0) }
    }

    /// O primeiro texto do alerta é o "app" de origem — no AirDrop vem
    /// literalmente "AirDrop".
    static func isAirDrop(appName: String?, title: String) -> Bool {
        [appName, title].contains { $0?.lowercased().contains(airdropMarker) == true }
    }
}
