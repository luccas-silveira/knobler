// Self-check do filtro do keyLog (GET /status): só tecla de função entra no
// anel; nenhuma tecla que produz texto. Compila e roda (da raiz do repo):
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/TeclaDiagnostico.swift tools/keylogcheck.swift \
//     -o /tmp/keylogcheck && /tmp/keylogcheck
import Carbon.HIToolbox
import Foundation

@main
enum KeyLogCheck {
    static func check(_ ok: Bool, _ msg: String) {
        if !ok { print("FALHOU: \(msg)"); exit(1) }
    }

    static func entrada(_ code: Int) -> String? {
        TeclaDiagnostico.entrada(keyCode: UInt16(code))
    }

    /// O que a tecla digita no layout dado (vazio se a tradução falhar).
    static func texto(_ layout: UnsafePointer<UCKeyboardLayout>, _ code: Int, _ mods: UInt32) -> String {
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 8)
        var len = 0
        let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), mods,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                    &dead, chars.count, &len, &chars)
        return status == noErr ? String(utf16CodeUnits: chars, count: len) : ""
    }

    /// Algum caractere que aparece na tela: controle (F-keys viram 0x10) e área
    /// de uso privado (NSF13FunctionKey e afins) não contam.
    static func imprimivel(_ s: String) -> Bool {
        s.unicodeScalars.contains {
            ![.control, .privateUse, .format, .unassigned].contains($0.properties.generalCategory)
        }
    }

    static func main() {
        // As que motivaram o diagnóstico: brilho de teclado externo como keyDown.
        let f13a20 = [(kVK_F13, "F13"), (kVK_F14, "F14"), (kVK_F15, "F15"), (kVK_F16, "F16"),
                      (kVK_F17, "F17"), (kVK_F18, "F18"), (kVK_F19, "F19"), (kVK_F20, "F20")]
        for (code, nome) in f13a20 {
            check(entrada(code) == "kb=\(code) \(nome)", "\(nome) entra no anel como kb=\(code) \(nome)")
        }
        check(entrada(kVK_F1) == "kb=\(kVK_F1) F1", "F1 entra (brilho com teclas de função padrão)")
        // keyCode 72 (kVK_VolumeUp) digita "=" com Shift no layout ABNT2.
        for code in [kVK_VolumeUp, kVK_VolumeDown, kVK_Mute] {
            check(entrada(code) == nil, "tecla virtual de volume \(code) fica de fora")
        }

        // Teclas que digitam ou editam texto ficam de fora.
        let textuais = [kVK_ANSI_A, kVK_ANSI_Z, kVK_ANSI_Q, kVK_ANSI_M, kVK_ANSI_0, kVK_ANSI_9,
                        kVK_ANSI_Period, kVK_ANSI_Comma, kVK_ANSI_Slash, kVK_ANSI_Semicolon,
                        kVK_ANSI_Quote, kVK_ANSI_Grave, kVK_ISO_Section, kVK_Space, kVK_Return,
                        kVK_Tab, kVK_Delete, kVK_ForwardDelete, kVK_Escape, kVK_ANSI_Keypad0,
                        kVK_ANSI_KeypadEnter, kVK_ANSI_KeypadPlus, kVK_LeftArrow, kVK_RightArrow,
                        kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
                        kVK_JIS_Yen, kVK_JIS_Underscore, kVK_JIS_KeypadComma]
        for code in textuais {
            check(entrada(code) == nil, "keyCode \(code) não pode entrar no anel")
        }

        // Varredura completa: a lista é fechada — F1 a F20, nada além.
        let aceitas = (0...0xFF).filter { entrada($0) != nil }
        check(aceitas.count == 20, "20 teclas aceitas, vieram \(aceitas.count): \(aceitas)")
        check(aceitas.allSatisfy { entrada($0)!.hasPrefix("kb=\($0) ") }, "formato kb=<keyCode> <nome>")

        // Prova pelo layout de verdade: tecla que digita algo visível, com ou sem
        // Shift/Option, nunca entra no anel. Sem layout (sessão sem janela), a
        // varredura acima continua valendo e esta parte é pulada com aviso.
        guard let fonte = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let bruto = TISGetInputSourceProperty(fonte, kTISPropertyUnicodeKeyLayoutData)
        else {
            print("keylogcheck: sem layout de teclado; varredura UCKeyTranslate pulada")
            print("keylogcheck OK")
            return
        }
        let dados = Unmanaged<CFData>.fromOpaque(bruto).takeUnretainedValue() as Data
        dados.withUnsafeBytes { raw in
            let layout = raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
            // sanidade: sem isso a varredura passaria em branco
            check(imprimivel(texto(layout, kVK_ANSI_A, 0)), "layout traduz a tecla A")
            var textuaisNoLayout = 0
            for code in 0..<128 {
                // estado de modificador do UCKeyTranslate: (Carbon >> 8) & 0xFF
                let digita = [0, UInt32(shiftKey >> 8), UInt32(optionKey >> 8)]
                    .contains { imprimivel(texto(layout, code, $0)) }
                if digita {
                    textuaisNoLayout += 1
                    check(entrada(code) == nil, "keyCode \(code) digita texto e entrou no anel")
                }
            }
            check(textuaisNoLayout > 40, "layout com \(textuaisNoLayout) teclas que digitam")
            for code in aceitas where code < 128 {
                check(!imprimivel(texto(layout, code, 0)), "tecla aceita \(code) digita texto")
            }
        }
        print("keylogcheck OK")
    }
}
