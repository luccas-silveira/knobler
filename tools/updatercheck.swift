//
//  tools/updatercheck.swift — self-check das funções puras do Updater.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/Updater.swift tools/updatercheck.swift -o /tmp/updatercheck && /tmp/updatercheck
//

import Foundation

@main
struct UpdaterCheck {
    static func main() {
        testVersionOrdering()
        testVersionEdgeCases()
        testStripMarkdown()
        testParseRelease()
        testParseSkipsDraftAndPrerelease()
        print("✅ updatercheck ok")
    }

    static func testVersionOrdering() {
        assert(isNewer("0.9.0", than: "0.8.4"), "minor maior")
        assert(isNewer("0.10.0", than: "0.9.0"), "10 > 9 numericamente, não alfabeticamente")
        assert(isNewer("1.0.0", than: "0.99.99"), "major domina")
        assert(isNewer("0.8.5", than: "0.8.4"), "patch maior")
        assert(!isNewer("0.8.4", than: "0.9.0"), "menor não é maior")
        assert(!isNewer("0.8.4", than: "0.8.4"), "igual não é maior")
    }

    static func testVersionEdgeCases() {
        assert(isNewer("v0.9.0", than: "0.8.4"), "prefixo v tolerado à esquerda")
        assert(isNewer("0.9.0", than: "v0.8.4"), "prefixo v tolerado à direita")
        assert(!isNewer("abacaxi", than: "0.8.4"), "lixo não é maior")
        assert(!isNewer("0.9", than: "0.8.4"), "sem 3 componentes não é maior")
        assert(!isNewer("0.9.0", than: ""), "vazio não crasha")
    }

    static func testStripMarkdown() {
        let raw = "### Fixed\n- **Ditado** parava de `funcionar`\n\n### Added\n- Card novo\n"
        let clean = stripMarkdown(raw)
        assert(!clean.contains("#"), "cabeçalho sem #")
        assert(!clean.contains("**"), "sem negrito")
        assert(!clean.contains("`"), "sem crase")
        assert(clean.contains("Fixed"), "texto do cabeçalho sobrevive")
        assert(clean.contains("Ditado"), "texto do item sobrevive")
        assert(!clean.hasSuffix("\n"), "sem newline sobrando no fim")
    }

    static func testParseRelease() {
        let json = """
        {
          "tag_name": "v0.9.0",
          "html_url": "https://github.com/luccas-silveira/knobler/releases/tag/v0.9.0",
          "body": "### Fixed\\n- **algo**",
          "draft": false,
          "prerelease": false,
          "assets": [
            {"name": "Knobler-0.9.0.zip",
             "browser_download_url": "https://github.com/luccas-silveira/knobler/releases/download/v0.9.0/Knobler-0.9.0.zip"}
          ]
        }
        """.data(using: .utf8)!
        // `try?` achata Release? — nil aqui é erro de decode OU draft/prerelease
        guard let release = try? parseRelease(json) else {
            assertionFailure("parse devia ter devolvido um release"); return
        }
        assert(release.version == "0.9.0", "versão sem o v: \(release.version)")
        assert(release.asset?.lastPathComponent == "Knobler-0.9.0.zip", "asset .zip encontrado")
        assert(release.notes.contains("algo"), "notas parseadas")
        assert(!release.notes.contains("**"), "notas já vêm limpas")
    }

    static func testParseSkipsDraftAndPrerelease() {
        func payload(draft: Bool, pre: Bool) -> Data {
            """
            {"tag_name":"v0.9.0",
             "html_url":"https://github.com/luccas-silveira/knobler/releases/tag/v0.9.0",
             "body":"x","draft":\(draft),"prerelease":\(pre),"assets":[]}
            """.data(using: .utf8)!
        }
        assert((try? parseRelease(payload(draft: true, pre: false))) == nil, "draft ignorado")
        assert((try? parseRelease(payload(draft: false, pre: true))) == nil, "prerelease ignorado")
        // release sem .zip ainda é válido — só não terá caminho de download direto
        guard let noAsset = try? parseRelease(payload(draft: false, pre: false)) else {
            assertionFailure("release sem asset ainda é um release"); return
        }
        assert(noAsset.asset == nil, "sem asset .zip → asset nil")
    }
}
