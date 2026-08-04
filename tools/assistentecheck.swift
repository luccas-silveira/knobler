//
//  assistentecheck.swift
//  O assistente de perfis de webhook não tem "passo em que parei" gravado: o
//  passo de retomada e a legenda da linha SAEM do estado do perfil (013). Este
//  gate guarda essa derivação — a tela em si é sheet e não renderiza no harness
//  de snapshot.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/WebhookAssistant.swift tools/assistentecheck.swift \
//    -o /tmp/assistentecheck && /tmp/assistentecheck
//

import Foundation

var falhas = 0
func check(_ ok: Bool, _ msg: @autoclosure () -> String) {
    guard !ok else { return }
    FileHandle.standardError.write("✗ \(msg())\n".data(using: .utf8)!)
    falhas += 1
}

@main enum Gate {
    static func main() {
        // --- retomada derivada (tabela do ticket 013) ---
        check(PassoAssistente.retomada(hasMapping: false, lastPayloadAt: nil) == .primeiroEnvio,
              "sem payload e sem mapa retoma no Primeiro envio")
        check(PassoAssistente.retomada(hasMapping: false, lastPayloadAt: 1) == .mapa,
              "com payload e sem mapa retoma no Mapa")
        check(PassoAssistente.retomada(hasMapping: true, lastPayloadAt: 1) == nil,
              "com mapa não abre assistente — vai direto pro editor")
        check(PassoAssistente.retomada(hasMapping: true, lastPayloadAt: nil) == nil,
              "mapa aplicado antes do primeiro POST também dispensa o assistente")

        // --- ordem e navegação dos passos (004) ---
        check(PassoAssistente.allCases.map(\.titulo)
              == ["Nome", "Serviço", "Link", "Primeiro envio", "Mapa"],
              "os cinco passos, nesta ordem")
        check(PassoAssistente.nome.anterior == nil, "o primeiro passo não volta")
        check(PassoAssistente.mapa.proximo == nil, "o último passo não avança")
        check(PassoAssistente.link.proximo == .primeiroEnvio && PassoAssistente.link.anterior == .servico,
              "vizinhos do passo Link")

        // --- legenda da linha do perfil (004) ---
        let agora = 1_000_000.0
        check(EstadoDoPerfil.legenda(hasMapping: false, lastPayloadAt: nil, agora: agora)
              == "Esperando o primeiro envio", "perfil recém-criado espera o primeiro envio")
        check(EstadoDoPerfil.legenda(hasMapping: false, lastPayloadAt: agora - 180, agora: agora)
              == "Sem mapa — último webhook há 3 min", "captura-only mostra que falta o mapa")
        check(EstadoDoPerfil.legenda(hasMapping: true, lastPayloadAt: agora - 180, agora: agora)
              == "Último webhook há 3 min", "perfil pronto mostra só o tempo")

        // --- tempo relativo (formatação própria: o do Foundation muda com o locale) ---
        check(EstadoDoPerfil.haQuantoTempo(0) == "agora", "zero é agora")
        check(EstadoDoPerfil.haQuantoTempo(59) == "agora", "menos de um minuto é agora")
        check(EstadoDoPerfil.haQuantoTempo(60) == "há 1 min", "um minuto")
        check(EstadoDoPerfil.haQuantoTempo(3599) == "há 59 min", "quase uma hora ainda é minuto")
        check(EstadoDoPerfil.haQuantoTempo(7200) == "há 2 h", "duas horas")
        check(EstadoDoPerfil.haQuantoTempo(172_800) == "há 2 d", "dois dias")
        // relógio do Mac atrás do relay não vira "há -1 min"
        check(EstadoDoPerfil.haQuantoTempo(-500) == "agora", "futuro é tratado como agora")

        if falhas > 0 {
            FileHandle.standardError.write("\(falhas) falha(s)\n".data(using: .utf8)!)
            exit(1)
        }
        print("assistentecheck ok")
    }
}
