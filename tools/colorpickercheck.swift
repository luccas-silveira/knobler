//
//  tools/colorpickercheck.swift — self-check da formatação do conta-gotas.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/ColorPicker.swift tools/colorpickercheck.swift -o /tmp/colorpickercheck \
//    && /tmp/colorpickercheck
//

import AppKit

@main
struct ColorPickerCheck {
    static func main() {
        testHex()
        testFormats()
        testDetail()
        print("✅ colorpickercheck ok")
    }

    private static func srgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    static func testHex() {
        assert(ColorPicker.hex(srgb(1, 0, 0)) == "#FF0000", "vermelho puro")
        assert(ColorPicker.hex(srgb(0, 0, 0)) == "#000000", "preto")
        assert(ColorPicker.hex(srgb(1, 1, 1)) == "#FFFFFF", "branco")
        // arredonda, não trunca: 0.5*255 = 127.5 → 128 (0x80)
        assert(ColorPicker.hex(srgb(0.5, 0.5, 0.5)) == "#808080", "cinza médio arredonda")
        // dois dígitos sempre: sem zero à esquerda o HEX sairia com 5 chars
        assert(ColorPicker.hex(srgb(1 / 255, 0, 0)) == "#010000", "zero à esquerda")
    }

    static func testFormats() {
        let c = srgb(1, 0, 170.0 / 255)
        assert(ColorPicker.string(c, format: .rgb) == "rgb(255, 0, 170)", "rgb legado")
        assert(ColorPicker.string(c, format: .css) == "rgb(255 0 170)", "css moderno")
        assert(
            ColorPicker.string(c, format: .swiftUI)
                == "Color(red: 1.000, green: 0.000, blue: 0.667)",
            "swiftUI em 0…1 com 3 casas")
        // cor fora do sRGB (P3) precisa converter, não estourar
        let p3 = NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
        assert(ColorPicker.hex(p3).hasPrefix("#"), "P3 converte pra sRGB sem crashar")
    }

    static func testDetail() {
        let detail = ColorPicker.detail(srgb(1, 0, 0), copied: .hex)
        assert(!detail.contains("#FF0000"), "o formato copiado não se repete no corpo")
        assert(detail.contains("rgb(255, 0, 0)"), "mostra rgb")
        assert(detail.contains("Color(red:"), "mostra swiftUI")
    }
}
