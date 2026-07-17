//
//  TranscriptFormatter.swift
//  Knobler
//
//  Limpa o transcript cru via um LLM local OpenAI-compatible (Ollama/LM Studio),
//  no estilo "Fluid Intelligence" do FluidVoice: tira fillers e falsos começos,
//  arruma pontuação/acento/capitalização — sem inventar conteúdo.
//  Schema OpenAI puro → serve Ollama /v1, LM Studio e afins.
//  ponytail: default gemma3:4b — 4B é o piso de qualidade em PT-BR (benchmark);
//  abaixo disso o modelo inverte o sentido ou apaga o texto.
//

import Foundation

struct TranscriptFormatter {
    let endpoint: String   // ex: http://localhost:11434/v1/chat/completions
    let model: String      // ex: gemma3:4b

    private static let system = """
    Você formata transcrições de voz. Faça apenas edições mínimas: remova fillers \
    (tipo "é", "ééé", "tipo", "sabe") e falsos começos, corrija pontuação, capitalização \
    e acentuação. NÃO adicione nem invente conteúdo, NÃO responda perguntas nem explique \
    nada. Preserve o sentido, o tom e o idioma da entrada. Devolva SOMENTE o texto \
    corrigido, sem aspas nem comentários.
    """

    /// Chamada mínima só pra carregar o modelo na RAM (mantém quente entre ditados).
    func prewarm() async {
        _ = try? await complete(system: "Responda: ok", user: "ok", timeout: 60)
    }

    /// Texto limpo; string vazia da IA → devolve o cru (nunca some com o ditado).
    func format(_ text: String) async throws -> String {
        let out = try await complete(system: Self.system, user: text, timeout: 15)
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    private func complete(system: String, user: String, timeout: TimeInterval) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "TranscriptFormatter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "endpoint inválido"])
        }
        struct Msg: Encodable { let role: String; let content: String }
        struct Req: Encodable {
            let model: String
            let messages: [Msg]
            let temperature: Double
            let stream: Bool
        }
        let body = Req(
            model: model,
            messages: [Msg(role: "system", content: system), Msg(role: "user", content: user)],
            temperature: 0, stream: false)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "TranscriptFormatter", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }
        return try Self.parse(data)
    }

    /// Extrai `choices[0].message.content` da resposta OpenAI-compatible.
    static func parse(_ data: Data) throws -> String {
        struct Resp: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
            let choices: [Choice]
        }
        return try JSONDecoder().decode(Resp.self, from: data).choices.first?.message.content ?? ""
    }

    #if DEBUG
    /// ponytail: self-check do parse + do caminho de fallback. Roda no launch em debug.
    static func _selfCheck() {
        let ok = #"{"choices":[{"message":{"role":"assistant","content":"Olá mundo."}}]}"#
        assert((try? parse(Data(ok.utf8))) == "Olá mundo.", "parse deveria extrair o content")
        assert((try? parse(Data("{}".utf8))) == nil, "JSON sem choices deveria falhar → fallback pro cru")
    }
    #endif
}
