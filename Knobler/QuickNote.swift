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

import AppKit
import CoreGraphics
import Foundation

/// Conformidade da peça (ficha em `Plugin.swift`, `montarNotaRapida`). Mora
/// aqui e não lá porque `QuickNote` importa AppKit e `Plugin.swift` é
/// Foundation puro (constraint 1) — mesmo motivo do `MirrorServico`. Não há
/// `start()`: a nota já nasce dormente (`active == false`), então "ligar" a
/// peça não faz nada além de existir; `parar()` só reusa o `didSet` de
/// `active` — mas pelo caminho da desinstalação, que preserva texto e clipboard.
extension QuickNote: PluginServico {
    /// Desinstalar não é o usuário fechando a nota: não atropela o clipboard
    /// geral (007 — desinstalar não apaga nem mexe em nada do usuário) e não
    /// joga o rascunho fora. Reinstalar devolve a nota com o texto.
    func parar() { desativarPelaDesinstalacao() }
}

final class QuickNote: ObservableObject {
    static let shared = QuickNote()

    /// Onde o texto é despejado ao desligar. Seam só pro self-check, que não
    /// pode mexer no clipboard de verdade da máquina.
    var pasteboard: NSPasteboard = .general

    /// Verdadeiro só durante `desativarPelaDesinstalacao()`. Marca que o
    /// desligamento NÃO partiu do usuário — a rede de segurança do clipboard e
    /// o descarte do texto são do caminho do usuário, não da desinstalação.
    private var desinstalando = false

    @Published var active = false {
        didSet {
            guard !active else { return }
            if !desinstalando {
                stashToPasteboard()
                text = ""
            }
            editing = false
            hostDisplayID = nil
        }
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

    /// Esta tela assume a nota. É o que a seção fixada chama ao entrar em foco:
    /// fixada, ela aparece no card com a nota desligada, e o campo desenhado
    /// sem dono não recebe teclado (`keyboardAllowed` mede a hospedagem) nem
    /// conta pro badge do notch fechado.
    ///
    /// Ligada em OUTRA tela, o dono migra pra cá com o texto: a nota é uma só,
    /// e quem abriu a seção está olhando esta tela. Migrar não passa pelo
    /// `didSet` de `active`, então nada é apagado nem despejado no clipboard.
    func adotar(_ id: CGDirectDisplayID?) {
        guard let id, !hosted(by: id) else { return }
        hostDisplayID = id
        if !active { active = true }
    }

    /// Digitando nesta tela agora. Enquanto for true, notificação e HUD não
    /// tomam o card: tirar o campo da tela derruba o foco do teclado junto, e
    /// as teclas seguintes cairiam no app da frente sem nenhum aviso.
    func typing(on id: CGDirectDisplayID?) -> Bool {
        hosted(by: id) && editing
    }

    /// Desligar não apaga no vazio: o texto vai pro clipboard antes de sumir.
    /// É a única rede de segurança da nota, e as TRÊS formas de perdê-la passam
    /// por aqui — o interruptor do menu, o monitor dono desconectado e o quit.
    /// Nenhuma delas pergunta nada antes, e o `TextEditor` já saiu da árvore
    /// quando o texto some, então o Cmd+Z do campo não alcança.
    ///
    /// ponytail: sobrescreve o que estava copiado, sem restaurar depois. Perder
    /// a nota é pior que perder o clipboard. Se incomodar, o molde de
    /// salvar/restaurar já existe em `Dictation.swift`.
    /// Tira a nota da tela sem tocar no clipboard nem no texto. É o `parar()`
    /// da peça (`PluginServico`, acima).
    func desativarPelaDesinstalacao() {
        desinstalando = true
        active = false
        desinstalando = false
    }

    private func stashToPasteboard() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Prova o `parar()` da peça (`PluginServico`, ver `Plugin.swift`): liga
    /// a nota numa tela de brinquedo, escreve um texto, desliga, e checa que
    /// os quatro campos voltam ao repouso — o vazamento que a conversão em
    /// peça tinha que impedir era a nota continuar aberta na tela depois de
    /// desinstalar. Usa uma instância própria (não `.shared`) com um
    /// `NSPasteboard` nomeado, não o `.general` da máquina de verdade: rodar
    /// `--selfcheck` não pode sobrescrever o clipboard real do usuário — é
    /// pra isso que o `pasteboard` é um seam.
    static func _pararSelfCheck() -> Bool {
        let pb = NSPasteboard(name: NSPasteboard.Name("knobler.selfcheck.quicknote"))
        pb.clearContents()
        pb.setString("copiado antes", forType: .string)

        // Desinstalar: sai da tela, mas o texto sobrevive e o clipboard fica
        // como estava.
        let peca = QuickNote()
        peca.pasteboard = pb
        peca.adotar(1)
        peca.text = "rascunho"
        peca.parar()
        let desinstalarOK = !peca.active && !peca.editing && peca.hostDisplayID == nil
            && peca.text == "rascunho"
            && pb.string(forType: .string) == "copiado antes"

        // Caminho do usuário (interruptor/quit): aí sim despeja e limpa.
        let usuario = QuickNote()
        usuario.pasteboard = pb
        usuario.adotar(1)
        usuario.text = "rascunho"
        usuario.active = false
        let usuarioOK = !usuario.active && usuario.text.isEmpty && !usuario.editing
            && usuario.hostDisplayID == nil
            && pb.string(forType: .string) == "rascunho"

        return desinstalarOK && usuarioOK
    }
}
