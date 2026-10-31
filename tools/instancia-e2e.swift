//
//  tools/instancia-e2e.swift — app-brinquedo do tools/instancia-e2e.sh. Roda a
//  `InstanciaUnica.garantir()` de verdade (AppKit + LaunchServices) com bundle
//  id próprio (com.zoi.knobler.instanciateste): nunca encosta no Knobler.
//  NÃO faz parte do alvo do app; o script compila e empacota.
//
//  Flags: --cli    modo headless (não sobe NSApplication), como o
//                  `--download-model` do cask e o `--selfcheck`
//         --veta   applicationShouldTerminate recusa (o Descanso em curso)
//         --adia   applicationShouldTerminate adia 1 s (restauração dos monitores)
//

import AppKit

/// Linha "<pid> <evento>" no log.txt ao lado do .app (ou do binário solto).
func registra(_ evento: String) {
    let pasta = Bundle.main.bundleIdentifier == nil
        ? Bundle.main.bundleURL : Bundle.main.bundleURL.deletingLastPathComponent()
    let url = pasta.appendingPathComponent("log.txt")
    let linha = Data("\(ProcessInfo.processInfo.processIdentifier) \(evento)\n".utf8)
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(linha); try? h.close()
    } else {
        try? linha.write(to: url)
    }
}

final class Delegado: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if CommandLine.arguments.contains("--veta") { registra("vetou"); return .terminateCancel }
        if CommandLine.arguments.contains("--adia") {
            registra("adiou")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) { registra("saiu-limpo") }
}

@main
@MainActor
enum InstanciaE2E {
    static let delegado = Delegado()

    static func main() {
        if CommandLine.arguments.contains("--cli") {
            registra("cli"); sleep(20); exit(0)
        }
        let app = NSApplication.shared
        InstanciaUnica.garantir()
        registra("montou")
        app.delegate = delegado
        app.run()
    }
}
