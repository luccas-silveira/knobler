//
//  NotchNotification.swift
//  Knobler
//
//  O que um card do notch carrega. Mora fora do NotificationInterceptor porque
//  o interceptor depende de AppSettings/NotificationRules e não compila isolado
//  — e o self-check do histórico precisa só do struct.
//

import AppKit

struct NotchNotification: Identifiable, Equatable {
    let id = UUID()
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
    let date = Date()
}
