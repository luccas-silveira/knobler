//
//  NotchNotification.swift
//  Knobler
//
//  O que um card do notch carrega. Mora fora do NotificationInterceptor porque
//  o interceptor depende de AppSettings/NotificationRules e não compila isolado
//  — e o self-check do histórico precisa só do struct.
//

import AppKit

struct NotchNotification: Identifiable, Equatable, Codable {
    /// `var`, não `let`: com valor default inline, um `let` fica de fora do
    /// memberwise init E não pode ser atribuído num `init(from:)` — o decode
    /// geraria um id novo, e o histórico deduplica por ele.
    var id = UUID()
    let appName: String?
    let title: String
    let body: String
    /// Bundle ID do app de origem (banners interceptados) — ícone/abrir exatos.
    var bundleID: String? = nil
    /// Alvo de sessão do Supacode: clique na notificação foca worktree/tab.
    var supacodeWorktree: String? = nil  // ID do worktree (path percent-encoded)
    var supacodeTab: String? = nil  // UUID da tab
    /// Lembrete do usuário: clique abre esta URL (http/https/file/app).
    var openURL: String? = nil
    /// Avatar remoto (webhook): URL https carregada com guardas no card.
    var iconURL: String? = nil
    /// Emoji fixo do perfil (webhook) — renderiza local, sem baixar nada.
    var iconEmoji: String? = nil
    /// Amostra de cor no lugar do ícone — conta-gotas.
    var iconColor: NSColor? = nil
    /// Botões do alerta original espelhados no card (vazio = card só informa).
    var actionTitles: [String] = []
    /// Chave pro interceptor achar os botões reais quando o card for clicado.
    var actionToken: UUID? = nil
    /// Card do AirDrop: clique revela a pasta de download (caminho do sistema,
    /// não uma URL — `openURL` aceita payload de webhook e não pode abrir file://).
    var revealsDownloads = false
    /// ID de dedupe do webhook: mesmo id substitui em vez de empilhar (progresso).
    var webhookID: String? = nil
    /// `var` pelo mesmo motivo do `id`: a poda por idade depende de restaurar
    /// esta data, não de carimbar uma nova no load.
    var date = Date()

    // MARK: - Codable

    /// **`actionTitles` e `actionToken` ficam de fora de propósito.** O token é
    /// uma chave viva pros `AXUIElement` que o `NotificationInterceptor` guarda
    /// em memória: depois de um restart não resolve nada, e um card restaurado
    /// com botões seria botão que não faz nada. Sem chave, eles voltam vazios
    /// por construção.
    ///
    /// `openURL`, `bundleID`, `revealsDownloads` e os campos do Supacode
    /// sobrevivem — são dados, não handles vivos, e o clique continua valendo.
    private enum CodingKeys: String, CodingKey {
        case id, appName, title, body, bundleID, supacodeWorktree, supacodeTab
        case openURL, iconURL, iconEmoji, iconColorRGBA, revealsDownloads
        case webhookID, date
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(UUID.self, forKey: .id)
        // decodeIfPresent em tudo que é opcional: arquivo gravado por uma versão
        // anterior (sem um campo novo) continua carregando em vez de virar lixo
        appName = try box.decodeIfPresent(String.self, forKey: .appName)
        title = try box.decode(String.self, forKey: .title)
        body = try box.decode(String.self, forKey: .body)
        bundleID = try box.decodeIfPresent(String.self, forKey: .bundleID)
        supacodeWorktree = try box.decodeIfPresent(String.self, forKey: .supacodeWorktree)
        supacodeTab = try box.decodeIfPresent(String.self, forKey: .supacodeTab)
        openURL = try box.decodeIfPresent(String.self, forKey: .openURL)
        iconURL = try box.decodeIfPresent(String.self, forKey: .iconURL)
        iconEmoji = try box.decodeIfPresent(String.self, forKey: .iconEmoji)
        revealsDownloads = try box.decodeIfPresent(Bool.self, forKey: .revealsDownloads) ?? false
        webhookID = try box.decodeIfPresent(String.self, forKey: .webhookID)
        date = try box.decode(Date.self, forKey: .date)
        if let rgba = try box.decodeIfPresent([Double].self, forKey: .iconColorRGBA),
           rgba.count == 4 {
            iconColor = NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
        }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encodeIfPresent(appName, forKey: .appName)
        try box.encode(title, forKey: .title)
        try box.encode(body, forKey: .body)
        try box.encodeIfPresent(bundleID, forKey: .bundleID)
        try box.encodeIfPresent(supacodeWorktree, forKey: .supacodeWorktree)
        try box.encodeIfPresent(supacodeTab, forKey: .supacodeTab)
        try box.encodeIfPresent(openURL, forKey: .openURL)
        try box.encodeIfPresent(iconURL, forKey: .iconURL)
        try box.encodeIfPresent(iconEmoji, forKey: .iconEmoji)
        try box.encode(revealsDownloads, forKey: .revealsDownloads)
        try box.encodeIfPresent(webhookID, forKey: .webhookID)
        try box.encode(date, forKey: .date)
        // RGBA em vez de hex: preserva alpha, e não obriga o gate do histórico a
        // arrastar o ColorPicker (SwiftUI) só pra converter cor.
        // A conversão de espaço espelha `ColorPicker.components`.
        if let c = iconColor?.usingColorSpace(.sRGB) {
            try box.encode(
                [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent],
                forKey: .iconColorRGBA)
        }
    }

    /// O memberwise init some quando existe `init(from:)` — este o repõe, com os
    /// mesmos defaults, pros 22 pontos que constroem notificação no app.
    init(
        id: UUID = UUID(),
        appName: String?,
        title: String,
        body: String,
        bundleID: String? = nil,
        supacodeWorktree: String? = nil,
        supacodeTab: String? = nil,
        openURL: String? = nil,
        iconURL: String? = nil,
        iconEmoji: String? = nil,
        iconColor: NSColor? = nil,
        actionTitles: [String] = [],
        actionToken: UUID? = nil,
        revealsDownloads: Bool = false,
        webhookID: String? = nil,
        date: Date = Date()
    ) {
        self.id = id
        self.appName = appName
        self.title = title
        self.body = body
        self.bundleID = bundleID
        self.supacodeWorktree = supacodeWorktree
        self.supacodeTab = supacodeTab
        self.openURL = openURL
        self.iconURL = iconURL
        self.iconEmoji = iconEmoji
        self.iconColor = iconColor
        self.actionTitles = actionTitles
        self.actionToken = actionToken
        self.revealsDownloads = revealsDownloads
        self.webhookID = webhookID
        self.date = date
    }
}
