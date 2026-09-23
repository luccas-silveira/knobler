import Foundation

/// Which mark a provider cell draws.
enum ProviderGlyph: String, Codable, Equatable {
    case claude
    case devin
    case openai
    case third
    case cursor
    /// The raw value stays `gemini`: it is the key archived readings were
    /// written under, and renaming it would make every stored reading for this
    /// provider undecodable.
    case antigravity = "gemini"
    /// Gemini's own sparkle, for the provider that meters a raw API key.
    ///
    /// It cannot be called `gemini`: that raw value already names Antigravity's
    /// arch inside every archived snapshot, and swapping its meaning would
    /// redraw old readings as a mark they were never written for. So the
    /// sparkle gets a key of its own instead.
    case geminiSpark = "gemini-spark"
    case glm
    case qwen
    case gemma
    case meta
    case deepseek
    case mistral
    case grok
    case opencode
    case commandcode
    case copilot
    case kimi
    case kiro
    case amp
    case minimax
    case ollama
    case ollamaLocal = "ollama-local"
    case lmstudio
    /// The QianwenAI platform's own console mark, which is a different emblem
    /// from the local Qwen model brand in `.qwen` — a ring wearing this one is
    /// the platform account, not a model.
    case qianwenAI = "qianwenai"

    /// If an asset with this name is in the bundle it wins over the traced
    /// outline — drop a PDF/SVG export from Figma in and it is picked up.
    var assetName: String { self == .ollamaLocal ? "glyph-ollama" : "glyph-\(rawValue)" }

    // knobler: desenho do glifo (outline, escala óptica, ProviderGlyphView) fora;
    // o Knobler só usa o enum como chave de modelo.
}
