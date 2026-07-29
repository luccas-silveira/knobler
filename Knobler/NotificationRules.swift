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

    /// Evento que justifica silenciar o notch. Fora do `CalendarCountdown` pelo
    /// mesmo motivo do resto deste arquivo: lá dentro depende do EventKit e não
    /// dá pra testar.
    ///
    /// Exige link de call de propósito. "Almoço" e "Aniversário da Ana" são
    /// eventos de agenda, não reunião — silenciar por causa deles faria o
    /// usuário perder notificação sem entender por quê. Dia inteiro nunca conta,
    /// pelo mesmo motivo.
    ///
    /// O fim é exclusivo: às 15h em ponto, a reunião que ia até as 15h acabou.
    static func silenciaOChat(
        isAllDay: Bool, start: Date, end: Date, temLinkDeCall: Bool, agora: Date
    ) -> Bool {
        guard !isAllDay, temLinkDeCall else { return false }
        return start <= agora && end > agora
    }
}
