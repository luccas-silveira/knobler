//
//  ShelfDrop.swift
//  Knobler
//
//  Texto arrastado pro notch. A prateleira guarda arquivos, então o texto vira
//  um `.txt` e herda tudo que o shelf já sabe fazer — AirDrop, arrastar de volta
//  pro Finder, converter.
//
//  Link NÃO passa por aqui: ele abre o preview e pronto (ver LinkPreview). O
//  `link(de:)` continua porque um `.webloc` pode chegar do Finder.
//
//  Sem AppKit/SwiftUI de propósito: nomear arquivo a partir de texto arbitrário
//  é onde mora o risco (nome vazio, barra, arquivo gigante) e isso precisa de
//  teste.
//

import Foundation

enum ShelfDrop {
    /// Pasta dos itens materializados. Fora de `Documentos`/`Desktop`: isto é
    /// dado do app, e o usuário não pediu arquivo novo na pasta dele.
    static func directory(
        base: URL? = nil,
        create: Bool = true
    ) -> URL {
        let root = base ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = root.appendingPathComponent("Knobler/Arrastados", isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Caracteres que não podem ir num nome de arquivo. A barra é o perigoso: um
    /// título com "/" viraria caminho e escreveria fora da pasta.
    private static let proibidos = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")

    /// Limite de nome. O HFS+/APFS aceita 255 bytes; 60 deixa margem pro sufixo
    /// de desambiguação (`-1`, `-2`…) e mantém a legenda do shelf legível.
    static let maxNome = 60

    /// Nome de arquivo seguro a partir de um texto qualquer. Devolve `nil`
    /// quando não sobra nada aproveitável — quem chama usa o fallback.
    static func sanitizar(_ texto: String) -> String? {
        let limpo = texto
            .components(separatedBy: proibidos)
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else { return nil }
        // ponto inicial esconderia o arquivo do Finder
        let semPonto = limpo.hasPrefix(".") ? String(limpo.dropFirst()) : limpo
        guard !semPonto.isEmpty else { return nil }
        return String(semPonto.prefix(maxNome))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nome pro trecho de texto: a primeira linha com conteúdo.
    static func nome(paraTexto texto: String) -> String {
        let primeira = texto
            .split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init) ?? ""
        return sanitizar(primeira) ?? "trecho"
    }

    /// Escreve o texto como `.txt` e devolve o arquivo criado.
    static func materializar(texto: String, in directory: URL? = nil) throws -> URL {
        let dir = directory ?? Self.directory()
        let out = FileConverter.uniqueURL(
            directory: dir, name: nome(paraTexto: texto), ext: "txt")
        try Data(texto.utf8).write(to: out)
        return out
    }

    /// Lê de volta a URL de um `.webloc` da prateleira. nil = não é atalho (ou
    /// está corrompido), e o item segue como arquivo comum.
    static func link(de url: URL) -> URL? {
        guard url.pathExtension.lowercased() == "webloc",
              let bytes = try? Data(contentsOf: url),
              let plist = (try? PropertyListSerialization.propertyList(
                from: bytes, options: [], format: nil)) as? [String: String],
              let texto = plist["URL"],
              let link = URL(string: texto),
              LinkBrowser.isWebLink(link)
        else { return nil }
        return link
    }

}
