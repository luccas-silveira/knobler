//
//  tools/quicknotecheck.swift — self-check da nota rápida.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/QuickNote.swift tools/quicknotecheck.swift \
//    -o /tmp/quicknotecheck && /tmp/quicknotecheck
//

import AppKit

@main
struct QuickNoteCheck {
    static func main() {
        testDesligarCopiaAntesDeApagar()
        testNotaVaziaNaoMexeNoClipboard()
        testSoBrancoNaoMexeNoClipboard()
        testDono()
        testDigitandoSoNaTelaDona()
        print("✅ quicknotecheck ok")
    }

    /// Pasteboard próprio: o self-check não pode encostar no clipboard da máquina.
    static func fixture() -> (QuickNote, NSPasteboard) {
        let pb = NSPasteboard(name: .init("knobler.quicknote.selfcheck"))
        pb.clearContents()
        let note = QuickNote()
        note.pasteboard = pb
        return (note, pb)
    }

    /// O P1 inteiro: desligar apagava no vazio, sem undo e sem saída.
    static func testDesligarCopiaAntesDeApagar() {
        let (note, pb) = fixture()
        note.hostDisplayID = 1
        note.active = true
        note.editing = true
        note.text = "pedido 88213"

        note.active = false

        assert(pb.string(forType: .string) == "pedido 88213", "texto não foi pro clipboard")
        assert(note.text.isEmpty, "texto deveria ter sido apagado depois de copiado")
        assert(!note.editing, "editing preso em true trava o notch aberto")
        assert(note.hostDisplayID == nil, "dono deveria sair junto")
    }

    /// Desligar sem ter escrito nada não pode torrar o que o usuário copiou.
    static func testNotaVaziaNaoMexeNoClipboard() {
        let (note, pb) = fixture()
        pb.clearContents()
        pb.setString("coisa importante do usuário", forType: .string)
        note.hostDisplayID = 1
        note.active = true

        note.active = false

        assert(pb.string(forType: .string) == "coisa importante do usuário",
               "clipboard do usuário foi sobrescrito por uma nota vazia")
    }

    /// Idem pra nota que só tem espaço/enter — é vazia pro usuário.
    static func testSoBrancoNaoMexeNoClipboard() {
        let (note, pb) = fixture()
        pb.clearContents()
        pb.setString("coisa importante do usuário", forType: .string)
        note.hostDisplayID = 1
        note.active = true
        note.text = "  \n\t "

        note.active = false

        assert(pb.string(forType: .string) == "coisa importante do usuário",
               "clipboard sobrescrito por nota só com espaço em branco")
    }

    /// A nota mora numa tela só; nas outras ela não existe.
    static func testDono() {
        let (note, _) = fixture()
        assert(!note.hosted(by: 1), "desligada não é hospedada em lugar nenhum")
        note.hostDisplayID = 1
        note.active = true
        assert(note.hosted(by: 1))
        assert(!note.hosted(by: 2), "nota vazou pro monitor errado")
        assert(!note.hosted(by: nil), "sem display id não pode casar com o dono")
    }

    /// `typing(on:)` guarda a prioridade de modo e a trava de hover-out:
    /// uma nota focada no monitor A não pode congelar o card do monitor B.
    static func testDigitandoSoNaTelaDona() {
        let (note, _) = fixture()
        note.hostDisplayID = 1
        note.active = true
        assert(!note.typing(on: 1), "sem foco não está digitando")
        note.editing = true
        assert(note.typing(on: 1))
        assert(!note.typing(on: 2), "digitação vazou pro outro monitor")
    }
}
