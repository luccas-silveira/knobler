//
//  shelfdropcheck.swift
//  Gate do link/texto arrastado pro shelf.
//
//  O risco todo está em virar nome de arquivo: título com barra escreveria fora
//  da pasta, título vazio daria arquivo sem nome, e texto de 4 KB estouraria o
//  limite do sistema de arquivos.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/FileConverter.swift Knobler/ImageConverter.swift \
//    Knobler/DocumentConverter.swift Knobler/VideoConverter.swift \
//    Knobler/ShelfDrop.swift tools/shelfdropcheck.swift \
//    -o /tmp/shelfdropcheck && /tmp/shelfdropcheck
//

import Foundation

private var falhas = 0

private func check(_ condicao: Bool, _ descricao: String) {
    if condicao {
        print("  ok   \(descricao)")
    } else {
        print("  FALHOU \(descricao)")
        falhas += 1
    }
}

@main
enum ShelfDropCheck {
    static func main() {
        print("== nome seguro ==")
        nomes()
        print("== o que é link ==")
        links()
        print("== arquivos escritos ==")
        escrita()
        print("== barra de endereço ==")
        barraDeEndereco()

        if falhas > 0 {
            print("❌ \(falhas) falha(s)")
            exit(1)
        }
        print("✅ shelfdropcheck ok")
    }

    static func nomes() {
        // barra é o perigoso: sem sanitizar, "a/b" escreveria na subpasta "a"
        check(ShelfDrop.sanitizar("relatório/2026")?.contains("/") == false,
              "barra some do nome")
        check(ShelfDrop.sanitizar("a:b?c*d|e\"f<g>h")?
                .rangeOfCharacter(from: CharacterSet(charactersIn: ":?*|\"<>")) == nil,
              "os outros proibidos do Finder somem")
        check(ShelfDrop.sanitizar("linha 1\nlinha 2")?.contains("\n") == false,
              "quebra de linha some")

        check(ShelfDrop.sanitizar("") == nil, "vazio não vira nome")
        check(ShelfDrop.sanitizar("   ") == nil, "só espaço não vira nome")
        check(ShelfDrop.sanitizar("///") == nil, "só proibido não vira nome")
        check(ShelfDrop.sanitizar(".oculto") == "oculto",
              "ponto inicial sai (senão o Finder esconde o arquivo)")

        let gigante = String(repeating: "a", count: 4000)
        check((ShelfDrop.sanitizar(gigante)?.count ?? .max) <= ShelfDrop.maxNome,
              "texto gigante é truncado (o filesystem corta em 255 bytes)")

        check(ShelfDrop.nome(paraTexto: "\n\n  primeira útil\nsegunda") == "primeira útil",
              "texto vira a primeira linha com conteúdo")
        check(ShelfDrop.nome(paraTexto: "\n\n\n") == "trecho",
              "texto sem linha útil cai no fallback")
        check(ShelfDrop.nome(paraTexto: "///") == "trecho",
              "texto que sanitiza pra nada cai no fallback")
    }

    static func links() {
        check(LinkBrowser.isWebLink(URL(string: "https://claude.ai")!), "https é link")
        check(LinkBrowser.isWebLink(URL(string: "http://exemplo.com/x")!), "http é link")
        check(!LinkBrowser.isWebLink(URL(fileURLWithPath: "/tmp/x.png")),
              "arquivo NÃO é link (entra pelo caminho de arquivo)")
        check(!LinkBrowser.isWebLink(URL(string: "mailto:alguem@exemplo.com")!),
              "mailto não vira atalho")
        check(!LinkBrowser.isWebLink(URL(string: "https://")!), "sem host não é link")
    }

    static func escrita() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelfdropcheck-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        guard let txt = try? ShelfDrop.materializar(texto: "primeira\nsegunda", in: dir) else {
            check(false, "txt escrito")
            return
        }
        check(txt.lastPathComponent == "primeira.txt", "nome do trecho")
        check((try? String(contentsOf: txt, encoding: .utf8)) == "primeira\nsegunda",
              "o texto inteiro é gravado, não só a primeira linha")

        // um título que é só barras não pode virar caminho
        let perigoso = try? ShelfDrop.materializar(texto: "/etc/passwd\nresto", in: dir)
        check(perigoso?.deletingLastPathComponent().path == dir.path,
              "título com caminho não escapa da pasta")

        // .webloc do Finder tem que voltar a ser URL: é assim que "Abrir no
        // notch" sabe pra onde ir
        let atalho = dir.appendingPathComponent("site.webloc")
        let alvo = URL(string: "https://www.anthropic.com/news")!
        try? PropertyListSerialization.data(
            fromPropertyList: ["URL": alvo.absoluteString], format: .binary, options: 0)
            .write(to: atalho)
        check(ShelfDrop.link(de: atalho) == alvo, "o .webloc lê de volta a URL")
        check(ShelfDrop.link(de: txt) == nil, "arquivo comum não é atalho")
        let falso = dir.appendingPathComponent("corrompido.webloc")
        try? Data("não é plist".utf8).write(to: falso)
        check(ShelfDrop.link(de: falso) == nil, "webloc corrompido não vira link")
    }

    /// O campo de endereço do navegador interno aceita as três coisas que o
    /// usuário digita: endereço completo, domínio solto e busca.
    static func barraDeEndereco() {
        check(LinkBrowser.url(deEntrada: "https://claude.ai")?.absoluteString
                == "https://claude.ai",
              "URL completa passa intacta")
        check(LinkBrowser.url(deEntrada: "exemplo.com/x")?.absoluteString
                == "https://exemplo.com/x",
              "domínio solto ganha https://")
        check(LinkBrowser.url(deEntrada: "  claude.ai  ")?.absoluteString
                == "https://claude.ai",
              "espaço em volta não atrapalha")

        let busca = LinkBrowser.url(deEntrada: "como fazer pão")
        check(busca?.host == "duckduckgo.com", "texto com espaço vira busca")
        check(busca?.query?.contains("pão") == true || busca?.query?.contains("p%C3%A3o") == true,
              "o termo buscado vai na query")
        check(LinkBrowser.url(deEntrada: "palavrasolta")?.host == "duckduckgo.com",
              "palavra sem ponto é busca, não domínio")

        check(LinkBrowser.url(deEntrada: "") == nil, "vazio não navega")
        check(LinkBrowser.url(deEntrada: "   ") == nil, "só espaço não navega")
    }
}
