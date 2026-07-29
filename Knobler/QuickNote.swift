//
//  QuickNote.swift
//  Knobler
//
//  Nota rápida: um campo de texto que vive no card aberto enquanto o
//  interruptor do menu estiver ligado. Desligar apaga.
//
//  ponytail: sem persistência e sem timer de expiração. O interruptor é a
//  regra de fim de vida inteira — nota que morre em minutos não precisa de
//  arquivo nem de Ajuste de intervalo.
//

import CoreGraphics
import Foundation

final class QuickNote: ObservableObject {
    static let shared = QuickNote()

    @Published var active = false {
        didSet { if !active { text = ""; editing = false; hostDisplayID = nil } }
    }
    @Published var text = ""
    /// Campo com foco de teclado — segura o card aberto contra o hover-out.
    @Published var editing = false
    /// Tela dona da nota (a que estava sob o mouse quando o interruptor ligou);
    /// nil quando desligada. Só ela desenha o campo, só ela recebe o teclado e
    /// só ela abre/fecha por causa da nota. Sem dono, `NotchView` é instanciada
    /// por tela: cada cópia desenharia um campo, todas disputariam a janela
    /// chave e todas escreveriam no MESMO `editing` — a que perdesse o foco
    /// escreveria `false` com a outra ainda focada, rearmando o hover-out que
    /// a guarda existe pra impedir.
    @Published var hostDisplayID: CGDirectDisplayID?

    /// A nota é desta tela? Onde não for, ela não existe.
    func hosted(by id: CGDirectDisplayID?) -> Bool {
        active && id != nil && hostDisplayID == id
    }
}
