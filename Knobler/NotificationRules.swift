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

    /// Botão que vale espelhar no card. O X de fechar não é ação: espelhá-lo
    /// daria um botão inútil que ainda por cima destrói o alerta do sistema.
    static func isActionTitle(_ title: String) -> Bool {
        let lowered = title.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lowered.isEmpty else { return false }
        return !closeActionHints.contains { lowered.contains($0) }
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

    /// Microfone ligado há tempo suficiente pra ser uma chamada de verdade.
    ///
    /// O limiar existe porque abrir uma aba de reunião, testar o mic nos Ajustes
    /// ou gravar um áudio de WhatsApp acende o microfone por segundos — silenciar
    /// por causa disso engoliria card sem motivo. `desde` é o instante em que o
    /// microfone acendeu; `nil` = apagado.
    static func micIndicaChamada(
        desde: Date?, agora: Date, limiar: TimeInterval = 20
    ) -> Bool {
        guard let desde else { return false }
        return agora.timeIntervalSince(desde) >= limiar
    }

    // MARK: - Conteúdo do banner

    /// Um texto do banner com o rótulo que o macOS dá a ele (`AXIdentifier`:
    /// title, subtitle, body, date). `id` nil = texto sem rótulo.
    struct TextoDoBanner: Equatable {
        let id: String?
        let valor: String
    }

    /// Tira espaço das pontas e as marcas de direção de texto. O WhatsApp manda
    /// U+200E grudado no nome do app e no texto: sem isso "‎WhatsApp" nunca casa
    /// com o nome do processo. Só as marcas de direção (e o BOM): ZWJ e VS16
    /// também são "invisíveis", mas sem eles ❤️ e 👨‍👩‍👧 se desmontam.
    static func limpo(_ s: String) -> String {
        let marcas: Set<UInt32> = [0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
                                   0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF]
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: s.unicodeScalars.filter { !marcas.contains($0.value) })
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nome do app de origem. No Tahoe ele não é um dos textos do banner: vem
    /// no começo da descrição, no formato "App, título, corpo". A vírgula do
    /// conteúdo não tem escape, então só o primeiro trecho é confiável — e sem
    /// separador nenhum não dá pra saber o que é app.
    static func appName(fromDescription descricao: String?) -> String? {
        guard let descricao, let corte = descricao.range(of: ", ") else { return nil }
        let nome = limpo(String(descricao[..<corte.lowerBound]))
        return nome.isEmpty ? nil : nome
    }

    /// Título, subtítulo e corpo. Pelo rótulo quando o banner tem; pela posição
    /// só quando nenhum texto tem rótulo. A hora do banner (`date`) é
    /// descartada: o card calcula a própria.
    ///
    /// Sem rótulo, 3+ textos seguem o formato que o interceptor sempre leu,
    /// [app, título, corpo…]: é o caminho de macOS mais antigo que o Tahoe, que
    /// não deu pra medir, e mudar o sentido ali seria regressão às cegas.
    static func partes(_ textos: [TextoDoBanner])
        -> (app: String?, title: String, subtitle: String?, body: String)? {
        let t = textos.map { TextoDoBanner(id: $0.id, valor: limpo($0.valor)) }
            .filter { !$0.valor.isEmpty }
        let rotulos: Set<String> = ["title", "subtitle", "body", "date"]
        if t.contains(where: { $0.id.map(rotulos.contains) == true }) {
            func valor(_ id: String) -> String? { t.first { $0.id == id }?.valor }
            let body = valor("body") ?? ""
            switch (valor("title"), valor("subtitle")) {
            case let (title?, sub): return (nil, title, sub, body)
            case let (nil, sub?): return (nil, sub, nil, body)
            case (nil, nil): return body.isEmpty ? nil : (nil, body, nil, "")
            }
        }
        switch t.count {
        case 0: return nil
        case 1: return (nil, t[0].valor, nil, "")
        case 2: return (nil, t[0].valor, nil, t[1].valor)
        default: return (t[0].valor, t[1].valor, nil, t[2...].map(\.valor).joined(separator: " — "))
        }
    }

    /// Hora do card: "agora" no primeiro minuto, depois minutos, depois horas.
    static func haQuanto(_ data: Date, agora: Date) -> String {
        let s = max(0, agora.timeIntervalSince(data))
        if s < 60 { return "agora" }
        if s < 3600 { return "há \(Int(s / 60)) min" }
        return "há \(Int(s / 3600)) h"
    }
}
