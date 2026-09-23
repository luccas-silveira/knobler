// knobler: substitutos mínimos dos tipos do codenotch que não vieram (UI, prefs,
// providers fora do recorte). Nada daqui roda com dado real no Knobler.
import Foundation

enum Preferences {
    // knobler: o Knobler não expõe os limites extras do Codex.
    static func storedShowCodexExtraLimits() -> Bool { false }
}

// knobler: Antigravity fora do recorte; só os dois membros que o modelo consulta.
enum AntigravityProfile {
    static let defaultID = "gemini"
    static func slug(fromProviderID id: String) -> String? { nil }
}

// knobler: sem zstd, o cache do app desktop do Claude fica fora. O provider
// recebe nil (ver `ClaudeOAuthProvider.init`), então `read` nunca é chamado.
struct ClaudeDesktopUsageCache: Sendable {
    struct Reading: Equatable, Sendable {
        let windows: [LimitWindow]
        let capturedAt: Date
        let entry: URL
        func isFresh(at now: Date = Date(), within window: TimeInterval) -> Bool { false }
    }
    func read(organization: String, now: Date = Date()) -> Reading? { nil }
}

// knobler: sem o catálogo de traduções do codenotch; a chave (inglês) volta como veio.
// Nenhum texto daqui chega à UI do Knobler, que escreve os próprios rótulos.
enum L10n {
    static var locale: Locale { .current }
    static func t(_ key: String.LocalizationValue, locale: Locale = locale) -> String {
        String(localized: key, table: "Codenotch", locale: locale)
    }
}

// knobler: só as cores que o modelo consulta; a UI é do Knobler.
import SwiftUI
enum Palette {
    static let ample = Color(red: 0, green: 1, blue: 0.533)
    static let watch = Color(red: 0.949, green: 1, blue: 0)
    static let critical = Color(red: 1, green: 0.247, blue: 0)
    static let generationFast = Color(red: 0.039, green: 0.518, blue: 1)
    static let generationSlow = Color(red: 1, green: 0.271, blue: 0.227)
}
