//
import Foundation

@main
struct AirDropCheck {
    static func expect(_ ok: Bool, _ msg: String) {
        if !ok { print("FALHOU: \(msg)"); exit(1) }
    }
    static func main() {
        testFase(); testDestino(); testAgregacao(); testInterrompido(); testTextos()
        print("airdropcheck ok")
    }
    // strings reais do dossiê (axdump de 2026-09-23)
    static func testFase() {
        expect(AirDropRegras.faseDoAlerta(appName: "AirDrop", title: "Recebendo um vídeo") == .recebendo, "recebendo")
        expect(AirDropRegras.faseDoAlerta(appName: "AirDrop Concluído", title: "Recebido: um vídeo") == .concluido, "concluído pt")
        expect(AirDropRegras.faseDoAlerta(appName: "AirDrop Completed", title: "Received: a video") == .concluido, "concluído en")
        expect(AirDropRegras.faseDoAlerta(appName: "Mensagens", title: "Oi") == nil, "não é AirDrop")
        expect(AirDropRegras.isAirDrop(appName: "Mensagens", title: "AirDrop, Recebendo uma foto"), "marca no título")
    }
    static func testDestino() {
        let a = AirDropRegras.destino(deDescricao: "iPhone (2), Enviando")
        expect(a?.aparelho == "iPhone (2)" && a?.enviado == false, "enviando")
        let b = AirDropRegras.destino(deDescricao: "iPhone (2), Enviado")
        expect(b?.aparelho == "iPhone (2)" && b?.enviado == true, "enviado")
        expect(AirDropRegras.destino(deDescricao: "Mana") == nil, "sem fase = não é destino ativo")
    }
    static func testAgregacao() {
        var e = AirDropRecebimentoEstado()
        let a = URL(fileURLWithPath: "/tmp/a.mov"), b = URL(fileURLWithPath: "/tmp/b.jpg")
        e.atualizar(a, fracao: 0.2); e.atualizar(b, fracao: 0.6)
        expect(abs((e.progresso ?? -1) - 0.4) < 0.0001, "média")
        expect(e.rotulo == "2 arquivos", "rótulo plural")
        e.atualizar(a, fracao: 1); expect(e.encerrar(a) == nil, "ainda há arquivo ativo")
        e.atualizar(b, fracao: 1)
        expect(e.encerrar(b) == .recebido([a, b]), "fim com os dois")
        expect(e.progresso == nil, "limpo depois do fim")
    }
    static func testInterrompido() {
        var e = AirDropRecebimentoEstado()
        let a = URL(fileURLWithPath: "/tmp/a.mov")
        e.atualizar(a, fracao: 0.3)
        expect(e.encerrar(a) == .interrompido, "fração < 1 = interrompido")
        expect(e.progresso == nil, "limpo")
    }
    static func testTextos() {
        expect(AirDropTexto.atividadeEnviando(destino: "iPhone") == "Enviando pra iPhone", "com destino")
        expect(AirDropTexto.atividadeEnviando(destino: nil) == "Enviando por AirDrop", "sem destino")
        expect(AirDropTexto.cardEnviado(destino: nil) == "Enviado", "card sem destino")
        expect(AirDropRegras.rotulo([URL(fileURLWithPath: "/x/foto.png")]) == "foto.png", "rótulo 1")
    }
}
