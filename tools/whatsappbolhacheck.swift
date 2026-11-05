// Gate da etapa 7 do WhatsApp: a bolha de envio (Knobler/WhatsApp/WhatsAppEstado.swift).
// enviando → enviada → entregue → lida, ou falhou, casada pelo `ref` que a ponte
// devolve na resposta e no evento `mensagem` (docs/whatsapp-ponte.md:272-275),
// chegue um ou outro primeiro. Falha não reenvia sozinha: só `retentar`.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppEstado.swift \
//     tools/whatsappbolhacheck.swift \
//     -o /tmp/whatsappbolhacheck && /tmp/whatsappbolhacheck
//
// Tudo em memória: nenhuma rede, nenhum arquivo, nenhum UserDefaults.

import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappbolhacheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - fábricas

private let C = "8292"
private let X = "554799990001@s.whatsapp.net"
private let Y = "554799990002@s.whatsapp.net"
private let EU = "554799998292@s.whatsapp.net"

private func chave(_ jid: String = X) -> WAChave { WAChave(conta: C, jid: jid) }

private func mensagem(id: String, ts: Int, deMim: Bool = false, conversa: String = X,
                      texto: String = "oi", status: WAStatus? = nil) -> WAMensagem {
    WAMensagem(id: id, conversa: conversa,
               remetente: deMim ? EU : conversa,
               remetenteNome: nil, deMim: deMim, ts: ts, tipo: .texto,
               texto: texto, midia: nil, citacao: nil, reacoes: [],
               editada: nil, apagada: nil, status: status ?? (deMim ? .enviada : nil))
}

private func conversa(jid: String = X, ts: Int) -> WAConversa {
    WAConversa(jid: jid, jids: [jid], tipo: .individual, nome: "Fulano",
               naoLidas: 0, marcadaNaoLida: false, ts: ts, ultima: nil)
}

/// Conversa X carregada com uma recebida (ts 100) e uma minha antiga (ts 200).
private func carregado() -> WAEstado {
    var e = WAEstado()
    e.substituirConversas(conta: C, [conversa(ts: 200)])
    e.inserirMensagens([mensagem(id: "A", ts: 100),
                        mensagem(id: "B", ts: 200, deMim: true, status: .lida)],
                       em: chave(), antes: nil, maisVelhas: false)
    return e
}

@discardableResult
private func enviar(_ e: inout WAEstado, ref: String = "k-1", texto: String = "tudo bem?",
                    agora: Int = 300, k: WAChave = chave()) -> String {
    e.comecarEnvio(chave: k, texto: texto, citacao: nil, ref: ref, agora: agora, remetente: EU)
}

/// A mensagem real que a ponte devolve para o envio `k-1`.
private func real(id: String = "REAL1", ts: Int = 301, status: WAStatus = .enviada) -> WAMensagem {
    mensagem(id: id, ts: ts, deMim: true, texto: "tudo bem?", status: status)
}

private func eventoMensagem(_ m: WAMensagem, ref: String?) -> WAEventoNumerado {
    .mensagem(m, conversa(ts: m.ts), ref: ref)
}

private func recibo(_ ids: [String], _ r: WARecibo, ts: Int = 400) -> WAEventoNumerado {
    .recibo(conversa: X, ids: ids, recibo: r, de: X, ts: ts)
}

private func ids(_ e: WAEstado, _ k: WAChave = chave()) -> [String] { e.bolhas(de: k).map(\.id) }
private func bolha(_ e: WAEstado, _ id: String, _ k: WAChave = chave()) -> WABolha? {
    e.bolhas(de: k).first { $0.id == id }
}
private func estado(_ e: WAEstado, _ id: String, _ k: WAChave = chave()) -> WAEstadoDaBolha? {
    bolha(e, id, k).map { e.estadoDaBolha($0) }
}

// MARK: - casos

/// `comecarEnvio` cria a bolha local `deMim` no fim, em `.enviando(ref:)`.
private func comecar() {
    var e = carregado()
    let id = enviar(&e)
    exigir(id == "local-k-1", "comecarEnvio devolve \"local-<ref>\"; veio \(id)")
    exigir(ids(e) == ["A", "B", "local-k-1"], "a bolha local entra no fim da conversa; veio \(ids(e))")

    guard let b = bolha(e, "local-k-1") else { return exigir(false, "bolha local ausente") }
    exigir(b.mensagem.deMim, "a bolha local é minha (deMim)")
    exigir(b.mensagem.texto == "tudo bem?", "a bolha local mostra o texto digitado; veio \(b.mensagem.texto)")
    exigir(b.mensagem.ts == 300, "a bolha local leva o `agora` como ts; veio \(b.mensagem.ts)")
    exigir(b.mensagem.remetente == EU, "o remetente da bolha local é o número da conta; veio \(b.mensagem.remetente)")
    exigir(b.mensagem.status == nil, "bolha ainda não confirmada não tem status; veio \(String(describing: b.mensagem.status))")
    exigir(b.mensagem.tipo == .texto, "o tipo padrão é texto; veio \(b.mensagem.tipo)")
    exigir(b.envio == .enviando(ref: "k-1"), "envio .enviando(ref: k-1); veio \(String(describing: b.envio))")
    exigir(e.estadoDaBolha(b) == .enviando, "a bolha local aparece como enviando; veio \(e.estadoDaBolha(b))")

    // as bolhas que já estavam não mudam
    exigir(estado(e, "A") == .recebida && estado(e, "B") == .lida,
           "começar um envio não mexe nas bolhas anteriores")

    // a citação e o tipo vão para a bolha local
    let cit = WACitacao(id: "A", remetente: X, texto: "oi")
    let id2 = e.comecarEnvio(chave: chave(), texto: "olha", tipo: .imagem, citacao: cit,
                             ref: "k-2", agora: 310, remetente: EU)
    let b2 = bolha(e, id2)
    exigir(id2 == "local-k-2", "segundo envio devolve local-k-2; veio \(id2)")
    exigir(b2?.mensagem.citacao == cit, "a citação respondida aparece na bolha local")
    exigir(b2?.mensagem.tipo == .imagem, "o tipo passado vai para a bolha local")
    exigir(ids(e) == ["A", "B", "local-k-1", "local-k-2"], "dois envios seguidos ficam na ordem; veio \(ids(e))")
}

/// Resposta HTTP antes do evento: a resposta troca a bolha, o evento não duplica.
private func respostaAntesDoEvento() {
    var e = carregado()
    enviar(&e)
    e.confirmarEnvio(ref: "k-1", mensagem: real(), chave: chave())
    exigir(ids(e) == ["A", "B", "REAL1"], "a confirmação troca a bolha local pela real; veio \(ids(e))")
    let b = bolha(e, "REAL1")
    exigir(b?.mensagem.status == .enviada, "a bolha real chega com status enviada")
    exigir(b?.envio == nil, "a bolha confirmada não tem mais envio pendente; veio \(String(describing: b?.envio))")
    exigir(estado(e, "REAL1") == .enviada, "a bolha confirmada aparece como enviada")

    e.aplicar(eventoMensagem(real(), ref: "k-1"), conta: C)
    exigir(ids(e) == ["A", "B", "REAL1"], "o evento com o mesmo ref depois da resposta não duplica; veio \(ids(e))")
    exigir(estado(e, "REAL1") == .enviada, "o evento depois da resposta mantém enviada")
}

/// Evento antes da resposta: o evento troca a bolha, a resposta não duplica nem volta status.
private func eventoAntesDaResposta() {
    var e = carregado()
    enviar(&e)
    e.aplicar(eventoMensagem(real(), ref: "k-1"), conta: C)
    exigir(ids(e) == ["A", "B", "REAL1"], "o evento com ref k-1 troca a bolha local pela real; veio \(ids(e))")
    exigir(bolha(e, "REAL1")?.envio == nil, "a bolha trocada pelo evento não fica enviando")
    exigir(estado(e, "REAL1") == .enviada, "a bolha trocada pelo evento aparece como enviada")

    // o recibo chega antes da resposta HTTP
    e.aplicar(recibo(["REAL1"], .entregue), conta: C)
    exigir(estado(e, "REAL1") == .entregue, "recibo entregue antes da resposta vira entregue")

    e.confirmarEnvio(ref: "k-1", mensagem: real(status: .enviada), chave: chave())
    exigir(ids(e) == ["A", "B", "REAL1"], "a resposta depois do evento não duplica; veio \(ids(e))")
    exigir(estado(e, "REAL1") == .entregue,
           "a resposta atrasada não volta o status de entregue para enviada; veio \(String(describing: estado(e, "REAL1")))")
}

/// Recibos seguintes: entregue, lida, e entregue atrasado não desfaz lida.
private func recibosSeguintes() {
    var e = carregado()
    enviar(&e)
    e.confirmarEnvio(ref: "k-1", mensagem: real(), chave: chave())

    e.aplicar(recibo(["REAL1"], .entregue), conta: C)
    exigir(estado(e, "REAL1") == .entregue, "recibo entregue → entregue")
    e.aplicar(recibo(["REAL1"], .lida, ts: 410), conta: C)
    exigir(estado(e, "REAL1") == .lida, "recibo lida → lida")
    e.aplicar(recibo(["REAL1"], .entregue, ts: 420), conta: C)
    exigir(estado(e, "REAL1") == .lida, "recibo entregue depois de lida mantém lida")
}

/// Falha sem status, retry no mesmo lugar com ref novo, confirmação do ref velho ignorada.
private func falhaERetry() {
    var e = carregado()
    enviar(&e)
    // chega uma recebida depois, para o "mesmo lugar" ter o que provar
    e.aplicar(eventoMensagem(mensagem(id: "C", ts: 350), ref: nil), conta: C)
    exigir(ids(e) == ["A", "B", "local-k-1", "C"], "a recebida entra depois da bolha local; veio \(ids(e))")

    e.falharEnvio(ref: "k-1", chave: chave())
    let f = bolha(e, "local-k-1")
    exigir(f != nil, "a bolha que falhou continua na conversa")
    exigir(estado(e, "local-k-1") == .falhou, "falharEnvio → falhou; veio \(String(describing: estado(e, "local-k-1")))")
    exigir(f?.mensagem.status == nil, "bolha que falhou não tem status")
    exigir(f?.envio == .falhou(ref: "k-1"), "envio .falhou(ref: k-1); veio \(String(describing: f?.envio))")

    let posicao = ids(e).firstIndex(of: "local-k-1")
    e.retentar(idLocal: "local-k-1", novoRef: "k-2", chave: chave())
    exigir(ids(e).firstIndex(of: "local-k-1") == posicao && ids(e) == ["A", "B", "local-k-1", "C"],
           "retentar mantém a bolha no mesmo lugar; veio \(ids(e))")
    exigir(bolha(e, "local-k-1")?.envio == .enviando(ref: "k-2"),
           "retentar volta a .enviando com o ref novo; veio \(String(describing: bolha(e, "local-k-1")?.envio))")
    exigir(estado(e, "local-k-1") == .enviando, "a bolha retentada aparece como enviando")
    exigir(bolha(e, "local-k-1")?.mensagem.status == nil, "a bolha retentada continua sem status")

    // confirmação atrasada do ref velho: ignorada, nada entra nem muda
    let antesDaVelha = e.bolhas(de: chave())
    e.confirmarEnvio(ref: "k-1", mensagem: real(id: "VELHA", ts: 302), chave: chave())
    exigir(e.bolhas(de: chave()) == antesDaVelha,
           "confirmação com o ref de antes do retry é ignorada; veio \(ids(e))")

    // a do ref novo troca a bolha
    e.confirmarEnvio(ref: "k-2", mensagem: real(id: "REAL2", ts: 360), chave: chave())
    exigir(!ids(e).contains("local-k-1") && ids(e).contains("REAL2"),
           "a confirmação do ref novo troca a bolha local; veio \(ids(e))")
    exigir(ids(e).filter { $0 == "REAL2" }.count == 1, "a bolha real aparece uma vez só")
    exigir(estado(e, "REAL2") == .enviada, "a bolha confirmada depois do retry aparece como enviada")

    // falharEnvio de ref já confirmado não derruba a bolha real
    e.falharEnvio(ref: "k-2", chave: chave())
    exigir(estado(e, "REAL2") == .enviada, "falha atrasada de envio já confirmado não vira falhou")
}

/// Recebida (deMim false) é sempre `.recebida`; minha do histórico segue o status.
private func recebida() {
    var e = carregado()
    exigir(estado(e, "A") == .recebida, "mensagem de outro aparece como recebida")
    e.aplicar(eventoMensagem(mensagem(id: "D", ts: 500), ref: nil), conta: C)
    exigir(estado(e, "D") == .recebida, "mensagem nova de outro aparece como recebida")
    exigir(bolha(e, "D")?.envio == nil, "recebida não tem envio")
    e.inserirMensagens([mensagem(id: "E", ts: 50, deMim: true, status: .entregue)],
                       em: chave(), antes: nil, maisVelhas: true)
    exigir(estado(e, "E") == .entregue, "minha mensagem do histórico mostra o status dela")
    exigir(estado(e, "B") == .lida, "minha mensagem lida do histórico aparece como lida")
}

/// Depois de falhar, nada reenvia nem muda a bolha até `retentar`.
private func semReenvioAutomatico() {
    var e = carregado()
    enviar(&e)
    e.falharEnvio(ref: "k-1", chave: chave())
    let falhou = bolha(e, "local-k-1")

    // o resto da vida da conversa segue
    e.aplicar(eventoMensagem(mensagem(id: "F", ts: 320), ref: nil), conta: C)
    e.aplicar(recibo(["B"], .lida), conta: C)
    e.aplicar(.reacao(conversa: X, alvo: "A", remetente: X, deMim: false, emoji: "👍", ts: 330), conta: C)
    e.falharEnvio(ref: "k-1", chave: chave())
    e.falharEnvio(ref: "k-9", chave: chave())
    e.confirmarEnvio(ref: "k-8", mensagem: mensagem(id: "OUTRA", ts: 340, deMim: true, conversa: Y),
                     chave: chave(Y))
    e.definirRascunho("depois", para: chave())
    let outro = enviar(&e, ref: "k-3", texto: "outra", agora: 350)
    e.confirmarEnvio(ref: "k-3", mensagem: real(id: "REAL3", ts: 351), chave: chave())

    exigir(outro == "local-k-3", "um envio novo não reaproveita a bolha que falhou")
    exigir(bolha(e, "local-k-1") == falhou,
           "a bolha que falhou fica igual até retentar; veio \(String(describing: bolha(e, "local-k-1")))")
    exigir(estado(e, "local-k-1") == .falhou, "a bolha que falhou continua falhou")
    exigir(e.bolhas(de: chave()).filter { $0.envio != nil }.map(\.id) == ["local-k-1"],
           "nenhuma bolha volta a enviar sozinha; pendentes: \(e.bolhas(de: chave()).filter { $0.envio != nil }.map(\.id))")
}

/// Conversa não carregada: o envio carrega a lista com a bolha local.
private func conversaNaoCarregada() {
    var e = carregado()
    let k = chave(Y)
    exigir(!e.carregada(k), "pré-condição: a conversa Y não está carregada")
    let id = enviar(&e, ref: "k-5", texto: "primeira", agora: 600, k: k)
    exigir(id == "local-k-5", "comecarEnvio em conversa não carregada devolve local-k-5; veio \(id)")
    exigir(e.carregada(k), "o envio carrega a conversa aberta")
    exigir(ids(e, k) == ["local-k-5"], "a conversa recém-carregada mostra a bolha local; veio \(ids(e, k))")
    exigir(estado(e, "local-k-5", k) == .enviando, "a bolha da conversa recém-carregada aparece enviando")
    exigir(ids(e) == ["A", "B"], "o envio em Y não mexe na conversa X; veio \(ids(e))")

    e.confirmarEnvio(ref: "k-5", mensagem: real(id: "REAL5", ts: 601), chave: k)
    exigir(ids(e, k) == ["REAL5"], "a confirmação troca a bolha na conversa recém-carregada; veio \(ids(e, k))")
}

/// Resposta chegou e o evento se perdeu, sem bolha local: a real entra.
private func confirmacaoSemBolhaLocal() {
    var e = carregado()
    e.confirmarEnvio(ref: "k-7", mensagem: real(id: "REAL7", ts: 700), chave: chave())
    exigir(ids(e) == ["A", "B", "REAL7"], "confirmação sem bolha local nem real insere a real; veio \(ids(e))")
    exigir(estado(e, "REAL7") == .enviada, "a real inserida aparece como enviada")
    e.confirmarEnvio(ref: "k-7", mensagem: real(id: "REAL7", ts: 700), chave: chave())
    exigir(ids(e) == ["A", "B", "REAL7"], "a mesma confirmação de novo não duplica; veio \(ids(e))")
}

@main
enum Gate {
    static func main() {
        comecar()
        respostaAntesDoEvento()
        eventoAntesDaResposta()
        recibosSeguintes()
        falhaERetry()
        recebida()
        semReenvioAutomatico()
        conversaNaoCarregada()
        confirmacaoSemBolhaLocal()
        print("ok")
    }
}
