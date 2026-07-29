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

import Foundation

final class QuickNote: ObservableObject {
    static let shared = QuickNote()

    @Published var active = false {
        didSet { if !active { text = ""; editing = false } }
    }
    @Published var text = ""
    /// Campo com foco de teclado — segura o card aberto contra o hover-out.
    @Published var editing = false
}
