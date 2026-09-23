//
//  ColorPicker.swift
//  Knobler
//
//  Conta-gotas: NSColorSampler (a mesma lupa nativa do sistema) e o resultado
//  vira card no notch com o HEX já copiado.
//

import AppKit

enum ColorPicker {
    /// Formato copiado pro clipboard. O card mostra os outros.
    enum Format: String, CaseIterable {
        case hex, rgb, swiftUI, css
    }

    /// Abre a lupa, copia a cor no formato escolhido e devolve a cor amostrada
    /// (nil = usuário cancelou com Esc).
    /// Lupa viva. Sem referência forte o sampler morria antes de responder e o
    /// serviço da lupa (ColorSampler) ficava órfão com a janela invisível por
    /// cima das telas, engolindo todo clique e tecla até ser morto.
    private static var ativo: NSColorSampler?

    static func pick(format: Format, completion: @escaping (NSColor?) -> Void) {
        // segunda lupa por cima da primeira deixa uma delas sem dono
        guard ativo == nil else { return }
        let sampler = NSColorSampler()
        ativo = sampler
        // app agente não é ativo: sem isso o Esc vai pro app da frente e a lupa
        // não tem como ser cancelada
        NSApp.activate(ignoringOtherApps: true)
        sampler.show { color in
            ativo = nil
            if let color {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(string(color, format: format), forType: .string)
            }
            completion(color)
        }
    }

    /// A cor amostrada vem no espaço do display; sRGB é o denominador comum dos
    /// quatro formatos. Se a conversão falhar (espaço exótico), cai em preto —
    /// melhor que crashar num componente inexistente.
    private static func components(_ color: NSColor) -> (Int, Int, Int) {
        guard let c = color.usingColorSpace(.sRGB) else { return (0, 0, 0) }
        return (
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded())
        )
    }

    static func hex(_ color: NSColor) -> String {
        let (r, g, b) = components(color)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func string(_ color: NSColor, format: Format) -> String {
        let (r, g, b) = components(color)
        switch format {
        case .hex:
            return hex(color)
        case .rgb:
            return "rgb(\(r), \(g), \(b))"
        case .css:
            return "rgb(\(r) \(g) \(b))"
        case .swiftUI:
            let f = { (v: Int) in String(format: "%.3f", Double(v) / 255) }
            return "Color(red: \(f(r)), green: \(f(g)), blue: \(f(b)))"
        }
    }

    /// Corpo do card: os formatos que NÃO foram copiados, pra consulta rápida.
    static func detail(_ color: NSColor, copied: Format) -> String {
        Format.allCases
            .filter { $0 != copied && $0 != .css }  // css duplica rgb visualmente
            .map { string(color, format: $0) }
            .joined(separator: "  ·  ")
    }
}
