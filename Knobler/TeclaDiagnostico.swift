//
//  TeclaDiagnostico.swift
//  Knobler
//
//  Filtro do anel de teclas do diagnóstico (`keyLog` no GET /status). O monitor
//  global de keyDown do `VolumeHUDController` vê toda tecla digitada em qualquer
//  app, e o /status responde sem autenticação a qualquer processo local: gravar
//  tudo ali expunha o que o usuário digitava. Só entra no anel tecla de função,
//  que não produz texto.
//

import Carbon.HIToolbox

enum TeclaDiagnostico {
    /// Teclas que o diagnóstico precisa ver e que nunca produzem texto. O monitor
    /// existe por causa delas: teclado externo costuma mandar brilho como keyDown
    /// comum em vez do evento NX — F14/F15 (Scroll Lock/Pause num teclado de PC),
    /// ou F1/F2 com "usar F1, F2 etc. como teclas de função padrão" ligado.
    /// As teclas virtuais de volume (`kVK_VolumeUp` e afins) ficam de fora: no
    /// layout ABNT2 o keyCode 72 com Shift digita "=".
    static let nomes: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14",
        kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// Entrada do anel para um keyDown, ou nil quando a tecla não pode ser
    /// registrada — o caso de toda tecla que digita alguma coisa.
    static func entrada(keyCode: UInt16) -> String? {
        nomes[Int(keyCode)].map { "kb=\(keyCode) \($0)" }
    }
}
