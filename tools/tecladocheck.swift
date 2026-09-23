//
//  tools/tecladocheck.swift — self-check do bloqueio de teclado.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//    xcrun swiftc -parse-as-library -swift-version 5 \
//      Knobler/TecladoBloqueado.swift tools/tecladocheck.swift \
//      -o /tmp/tecladocheck && /tmp/tecladocheck
//
import CoreGraphics

@main
struct TecladoCheck {
    static func main() {
        let sys = CGEventType(rawValue: 14)!
        for t in [CGEventType.keyDown, .keyUp, .flagsChanged, sys] {
            precondition(TecladoBloqueado.deveEngolir(t), "devia engolir \(t.rawValue)")
        }
        for t in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput, .leftMouseDown, .mouseMoved] {
            precondition(!TecladoBloqueado.deveEngolir(t), "não devia engolir \(t.rawValue)")
        }
        let t = TecladoBloqueado.shared
        t.desligar()                       // desligar sem ligar não quebra
        precondition(!t.ativo)
        print("tecladocheck: ok")
    }
}
