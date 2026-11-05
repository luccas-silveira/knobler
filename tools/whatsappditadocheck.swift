// Gate da etapa 16 do WhatsApp: o ditado escreve no campo do WhatsApp em uso
// (seção ou card), como o destino `.ask`.
//
//   - `DictationDestination.escolher(askAtivo:campoWhatsApp:pidDaFrente:)`
//     (Knobler/DictationDestination.swift, só Foundation): Ask ativo vence,
//     depois o campo do WhatsApp em uso, depois o app da frente; sem nada, nil.
//   - `WhatsAppStore.receberDitado(_:chave:)`: só escreve quando a chave é a do
//     campo em uso; junta ao rascunho com UM espaço; senão devolve false e não
//     mexe em rascunho nenhum (o ditado então copia o texto, como no Ask).
//   - `campoEmUso` nasce nil e `_zerar()` o devolve a nil.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/DictationDestination.swift \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift \
//     Knobler/WhatsApp/WhatsAppCliente.swift Knobler/WhatsApp/WhatsAppCanal.swift \
//     Knobler/WhatsApp/WhatsAppEstado.swift Knobler/WhatsApp/WhatsAppStore.swift \
//     tools/whatsappditadocheck.swift \
//     -o /tmp/whatsappditadocheck && /tmp/whatsappditadocheck
//
// Nada sai pela rede: o store nunca recebe `start()`, e o cliente aponta pra
// um arquivo de chave inexistente em NSTemporaryDirectory() — a chave de
// verdade da ponte nunca é lida.

import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappditadocheck.swift:\(linha))")
        exit(1)
    }
}

private func d(_ x: DictationDestination?) -> String {
    x.map { "\($0)" } ?? "nil"
}

// MARK: - números do teste

private let A = "554791744143"
private let B = "554792508292"
private let X = "554799990001@s.whatsapp.net"
private let Y = "554799990002@s.whatsapp.net"

private let kX = WAChave(conta: A, jid: X)
private let kY = WAChave(conta: A, jid: Y)
/// Mesmo jid, outra conta: conversa diferente.
private let kXb = WAChave(conta: B, jid: X)

private let arquivoDaChave = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("whatsappditadocheck-\(getpid())-sem-chave")

@MainActor
private func novoStore() -> WhatsAppStore {
    WhatsAppStore(cliente: WACliente(porta: 18099, caminhoDaChave: arquivoDaChave))
}

// MARK: - destino

private func destino() {
    let ask = "ask-1"
    let campo = kX.texto
    let pid: pid_t = 4242

    // Ask ativo vence tudo
    var r = DictationDestination.escolher(askAtivo: ask, campoWhatsApp: campo, pidDaFrente: pid)
    exigir(r == .ask(id: ask), "Ask ativo + campo do WhatsApp + app da frente deu \(d(r)), esperado .ask(id: \"\(ask)\")")
    r = DictationDestination.escolher(askAtivo: ask, campoWhatsApp: nil, pidDaFrente: pid)
    exigir(r == .ask(id: ask), "Ask ativo + app da frente deu \(d(r)), esperado .ask")
    r = DictationDestination.escolher(askAtivo: ask, campoWhatsApp: campo, pidDaFrente: nil)
    exigir(r == .ask(id: ask), "Ask ativo + campo do WhatsApp (sem app da frente) deu \(d(r)), esperado .ask")
    r = DictationDestination.escolher(askAtivo: ask, campoWhatsApp: nil, pidDaFrente: nil)
    exigir(r == .ask(id: ask), "só Ask ativo deu \(d(r)), esperado .ask")

    // sem Ask, o campo do WhatsApp em uso vence o app da frente
    r = DictationDestination.escolher(askAtivo: nil, campoWhatsApp: campo, pidDaFrente: pid)
    exigir(r == .whatsapp(chave: campo), "sem Ask, campo do WhatsApp + app da frente deu \(d(r)), esperado .whatsapp(chave: \"\(campo)\")")
    r = DictationDestination.escolher(askAtivo: nil, campoWhatsApp: campo, pidDaFrente: nil)
    exigir(r == .whatsapp(chave: campo), "sem Ask, só o campo do WhatsApp deu \(d(r)), esperado .whatsapp")
    // a chave vai inteira, conta|jid
    r = DictationDestination.escolher(askAtivo: nil, campoWhatsApp: kXb.texto, pidDaFrente: pid)
    exigir(r == .whatsapp(chave: kXb.texto), "campo da outra conta deu \(d(r)), esperado .whatsapp(chave: \"\(kXb.texto)\")")

    // sem Ask e sem campo: o app da frente
    r = DictationDestination.escolher(askAtivo: nil, campoWhatsApp: nil, pidDaFrente: pid)
    exigir(r == .application(pid: pid), "sem Ask e sem campo deu \(d(r)), esperado .application(pid: \(pid))")

    // sem nada
    r = DictationDestination.escolher(askAtivo: nil, campoWhatsApp: nil, pidDaFrente: nil)
    exigir(r == nil, "sem Ask, sem campo e sem app da frente deu \(d(r)), esperado nil")

    // os destinos são distintos entre si
    exigir(DictationDestination.whatsapp(chave: kX.texto) != .whatsapp(chave: kY.texto),
           ".whatsapp de conversas diferentes saiu igual")
    exigir(DictationDestination.whatsapp(chave: "a") != .ask(id: "a"),
           ".whatsapp(chave: \"a\") igual a .ask(id: \"a\")")
}

// MARK: - campo em uso

@MainActor
private func campoEmUso() {
    let s = novoStore()
    exigir(s.campoEmUso == nil, "campoEmUso não nasce nil (\(String(describing: s.campoEmUso)))")
    s.campoEmUso = kX
    exigir(s.campoEmUso == kX, "campoEmUso não guardou a chave")
    s._zerar()
    exigir(s.campoEmUso == nil, "_zerar() não devolveu campoEmUso a nil")
    // depois de zerar, ditado não entra em lugar nenhum
    exigir(s.receberDitado("oi", chave: kX.texto) == false, "receberDitado aceitou depois de _zerar()")
    exigir(s.rascunho(kX) == "", "receberDitado escreveu depois de _zerar() (\"\(s.rascunho(kX))\")")
}

// MARK: - receber ditado

@MainActor
private func receber() {
    // rascunho "oi" + "tudo bem"
    do {
        let s = novoStore()
        s.campoEmUso = kX
        s.definirRascunho("oi", para: kX)
        let ok = s.receberDitado("tudo bem", chave: kX.texto)
        exigir(ok == true, "receberDitado com o campo em uso devolveu false")
        exigir(s.rascunho(kX) == "oi tudo bem", "\"oi\" + \"tudo bem\" virou \"\(s.rascunho(kX))\", esperado \"oi tudo bem\"")
        // um segundo ditado continua do mesmo jeito
        exigir(s.receberDitado("e você", chave: kX.texto) == true, "segundo ditado devolveu false")
        exigir(s.rascunho(kX) == "oi tudo bem e você", "segundo ditado virou \"\(s.rascunho(kX))\", esperado \"oi tudo bem e você\"")
        // o campo segue em uso
        exigir(s.campoEmUso == kX, "receberDitado mexeu no campoEmUso")
    }

    // rascunho vazio vira só o ditado
    do {
        let s = novoStore()
        s.campoEmUso = kX
        exigir(s.receberDitado("tudo bem", chave: kX.texto) == true, "receberDitado com rascunho vazio devolveu false")
        exigir(s.rascunho(kX) == "tudo bem", "rascunho vazio + \"tudo bem\" virou \"\(s.rascunho(kX))\", esperado \"tudo bem\"")
    }

    // rascunho apagado (definido como "") também conta como vazio
    do {
        let s = novoStore()
        s.campoEmUso = kX
        s.definirRascunho("oi", para: kX)
        s.definirRascunho("", para: kX)
        exigir(s.receberDitado("tudo bem", chave: kX.texto) == true, "receberDitado com rascunho apagado devolveu false")
        exigir(s.rascunho(kX) == "tudo bem", "rascunho apagado + \"tudo bem\" virou \"\(s.rascunho(kX))\", esperado \"tudo bem\"")
    }

    // rascunho terminado em espaço não ganha espaço duplo
    do {
        let s = novoStore()
        s.campoEmUso = kX
        s.definirRascunho("oi ", para: kX)
        exigir(s.receberDitado("tudo bem", chave: kX.texto) == true, "receberDitado com rascunho \"oi \" devolveu false")
        exigir(s.rascunho(kX) == "oi tudo bem", "\"oi \" + \"tudo bem\" virou \"\(s.rascunho(kX))\", esperado \"oi tudo bem\"")
    }

    // campo em uso de outra conversa: false, nenhum rascunho mexido
    do {
        let s = novoStore()
        s.campoEmUso = kY
        s.definirRascunho("oi", para: kX)
        s.definirRascunho("rascunho do Y", para: kY)
        let ok = s.receberDitado("tudo bem", chave: kX.texto)
        exigir(ok == false, "receberDitado com campoEmUso de outra conversa devolveu true")
        exigir(s.rascunho(kX) == "oi", "campoEmUso de outra conversa mexeu no rascunho da chave pedida (\"\(s.rascunho(kX))\")")
        exigir(s.rascunho(kY) == "rascunho do Y", "campoEmUso de outra conversa mexeu no rascunho do campo em uso (\"\(s.rascunho(kY))\")")
        exigir(s.campoEmUso == kY, "receberDitado recusado mexeu no campoEmUso")
    }

    // mesmo jid, outra conta: também é outra conversa
    do {
        let s = novoStore()
        s.campoEmUso = kXb
        s.definirRascunho("oi", para: kX)
        let ok = s.receberDitado("tudo bem", chave: kX.texto)
        exigir(ok == false, "receberDitado com campoEmUso do mesmo jid em outra conta devolveu true")
        exigir(s.rascunho(kX) == "oi", "campo da outra conta mexeu no rascunho (\"\(s.rascunho(kX))\")")
        exigir(s.rascunho(kXb) == "", "campo da outra conta ganhou o ditado (\"\(s.rascunho(kXb))\")")
    }

    // campo em uso nil: false, nenhum rascunho mexido
    do {
        let s = novoStore()
        s.definirRascunho("oi", para: kX)
        let ok = s.receberDitado("tudo bem", chave: kX.texto)
        exigir(ok == false, "receberDitado sem campoEmUso devolveu true")
        exigir(s.rascunho(kX) == "oi", "receberDitado sem campoEmUso mexeu no rascunho (\"\(s.rascunho(kX))\")")
        exigir(s.campoEmUso == nil, "receberDitado sem campoEmUso ligou um campo")
    }

    // campo em uso, mas o ditado era de outra conversa (o campo mudou no meio)
    do {
        let s = novoStore()
        s.campoEmUso = kX
        s.definirRascunho("oi", para: kX)
        let ok = s.receberDitado("tudo bem", chave: kY.texto)
        exigir(ok == false, "ditado de outra conversa entrou no campo em uso")
        exigir(s.rascunho(kX) == "oi", "ditado de outra conversa mexeu no rascunho do campo em uso (\"\(s.rascunho(kX))\")")
        exigir(s.rascunho(kY) == "", "ditado de outra conversa escreveu na conversa fora de uso (\"\(s.rascunho(kY))\")")
    }
}

@main
enum Gate {
    @MainActor
    static func main() {
        destino()
        campoEmUso()
        receber()
        print("whatsappditadocheck ok")
    }
}
