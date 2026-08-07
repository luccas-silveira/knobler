// Gate da página de novidades — o filtro de versões e a migração da base
// instalada.
//
// O erro que este check existe pra pegar é silencioso nos dois sentidos: um
// filtro errado ou nunca abre a página, ou a abre em todo launch.
//
// Arrasta o Updater (comparação de SemVer, como o avisoscheck) e o mesmo
// bloco de arquivos do plugincheck: `data-alvo="instalarPeca"` é validado
// contra o `PluginID` de verdade, que arrasta as fichas que ele referencia.
//
// xcrun swiftc -parse-as-library -swift-version 5 \
//   Knobler/Updater.swift Knobler/NovidadesCatalogo.swift Knobler/Plugin.swift \
//   Knobler/Pomodoro.swift Knobler/Reminders.swift Knobler/Descanso.swift \
//   Knobler/NotchSectionOrder.swift Knobler/Peer.swift Knobler/Wire.swift \
//   Knobler/LANMessaging.swift Knobler/MessageStore.swift Knobler/Permissions.swift \
//   Knobler/WebhookClient.swift Knobler/WebhookKeychainStore.swift \
//   Knobler/NotchNotification.swift Knobler/FileConverter.swift Knobler/ImageConverter.swift \
//   Knobler/DocumentConverter.swift Knobler/VideoConverter.swift \
//   tools/novidadescheck.swift \
//   -o /tmp/novidadescheck && /tmp/novidadescheck

import Foundation

@main
struct NovidadesCheck {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("novidadescheck: \(message)") }
    }

    /// Lista fixa do teste — a de produção muda, as asserções não deviam.
    static let lista = ["0.25.0", "0.26.0", "0.30.0"]

    static func main() {
        // instalação limpa: só a boas-vindas, nunca o histórico
        check(NovidadesCatalogo.aExibir(instalada: "0.30.0", vista: nil, versoes: lista)
              == [NovidadesCatalogo.boasVindas],
              "instalação limpa deve ver só a boas-vindas")

        // quem viu o wizard parcial (migração de 0/1) também só vê a boas-vindas
        check(NovidadesCatalogo.aExibir(instalada: "0.30.0", vista: "0.0.0", versoes: lista)
              == [NovidadesCatalogo.boasVindas],
              "vista 0.0.0 deve ver só a boas-vindas")

        // quem pulou versões vê todas as pendentes, mais nova primeiro
        check(NovidadesCatalogo.aExibir(instalada: "0.30.0", vista: "0.24.0", versoes: lista)
              == ["0.30.0", "0.26.0", "0.25.0"],
              "vista 0.24.0 deve ver as três, decrescente")

        // versão mais nova que a instalada não aparece (build velha, arquivo novo)
        check(NovidadesCatalogo.aExibir(instalada: "0.26.0", vista: "0.24.0", versoes: lista)
              == ["0.26.0", "0.25.0"],
              "não mostrar versão acima da instalada")

        // em dia: nada a mostrar
        check(NovidadesCatalogo.aExibir(instalada: "0.30.0", vista: "0.30.0", versoes: lista).isEmpty,
              "quem está em dia não vê nada")

        // ordem por componente, não lexicográfica
        check(NovidadesCatalogo.aExibir(instalada: "0.10.0", vista: "0.8.0",
                                        versoes: ["0.9.0", "0.10.0"]) == ["0.10.0", "0.9.0"],
              "0.10.0 é mais nova que 0.9.0")

        // --- migração da chave antiga -------------------------------------
        let limpo = UserDefaults(suiteName: "novidadescheck.limpo")!
        limpo.removePersistentDomain(forName: "novidadescheck.limpo")
        check(NovidadesCatalogo.versaoVista(limpo) == nil, "sem chave nenhuma = instalação limpa")

        let wizard = UserDefaults(suiteName: "novidadescheck.wizard")!
        wizard.removePersistentDomain(forName: "novidadescheck.wizard")
        wizard.set(2, forKey: "onboarding.versao")
        check(NovidadesCatalogo.versaoVista(wizard) == NovidadesCatalogo.versaoDoWizard,
              "quem viu o wizard inteiro migra pra versão do wizard")

        let parcial = UserDefaults(suiteName: "novidadescheck.parcial")!
        parcial.removePersistentDomain(forName: "novidadescheck.parcial")
        parcial.set(1, forKey: "onboarding.versao")
        check(NovidadesCatalogo.versaoVista(parcial) == "0.0.0", "versão 1 do wizard migra pra 0.0.0")

        let legado = UserDefaults(suiteName: "novidadescheck.legado")!
        legado.removePersistentDomain(forName: "novidadescheck.legado")
        legado.set(true, forKey: "onboarding.permissoes.apresentado")
        check(NovidadesCatalogo.versaoVista(legado) == "0.0.0", "chave legada de permissões migra pra 0.0.0")

        // a chave nova ganha da antiga
        wizard.set("0.27.0", forKey: NovidadesCatalogo.chaveVersao)
        check(NovidadesCatalogo.versaoVista(wizard) == "0.27.0", "chave nova tem precedência")

        NovidadesCatalogo.marcarVisto("0.31.0", limpo)
        check(NovidadesCatalogo.versaoVista(limpo) == "0.31.0", "marcarVisto grava a versão")

        conferirConteudo()

        print("novidadescheck ok")
    }

    /// Raiz do repo: o gate roda de qualquer lugar, então sobe a partir do
    /// arquivo-fonte em vez de confiar no diretório corrente.
    static var raiz: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Ações que a ponte aceita. Espelha o enum de `NovidadesWindow`; o teste de
    /// que os dois não divergem é o próprio app não compilar com ação
    /// desconhecida.
    static let acoes = ["abrirAjustes", "instalarPeca", "abrirCard"]

    static func conferirConteudo() {
        let pasta = raiz.appendingPathComponent("Knobler/Novidades")
        let fm = FileManager.default
        let arquivos = (try? fm.contentsOfDirectory(atPath: pasta.path)) ?? []

        check(arquivos.contains("shell.html"), "falta shell.html")
        check(arquivos.contains("estilo.css"), "falta estilo.css")
        check(arquivos.contains("ponte.js"), "falta ponte.js")
        check(arquivos.contains("\(NovidadesCatalogo.boasVindas).html"),
              "falta \(NovidadesCatalogo.boasVindas).html")

        let shell = (try? String(contentsOf: pasta.appendingPathComponent("shell.html"),
                                 encoding: .utf8)) ?? ""
        check(shell.contains("id=\"conteudo\""),
              "shell.html precisa do container id=\"conteudo\" — é onde o corpo é injetado")

        // toda versão da lista tem arquivo, e todo arquivo de versão está na lista
        let deDisco = arquivos
            .filter { $0.hasSuffix(".html") && $0 != "shell.html"
                      && $0 != "\(NovidadesCatalogo.boasVindas).html" }
            .map { String($0.dropLast(5)) }
            .sorted()
        check(deDisco == NovidadesCatalogo.versoes.sorted(),
              "versoes do catálogo (\(NovidadesCatalogo.versoes.sorted())) != arquivos em disco (\(deDisco))")

        for versao in deDisco {
            check(versionComponents(versao) != nil, "nome de arquivo não é SemVer: \(versao).html")
        }

        let midia = Set((try? fm.contentsOfDirectory(atPath: pasta.appendingPathComponent("midia").path)) ?? [])

        for nome in deDisco.map({ "\($0).html" }) + ["\(NovidadesCatalogo.boasVindas).html"] {
            let html = (try? String(contentsOf: pasta.appendingPathComponent(nome),
                                    encoding: .utf8)) ?? ""
            check(!html.contains("<html"), "\(nome) deve conter só o corpo, sem <html>")
            check(!html.contains("<style"), "\(nome) não deve trazer <style> — o estilo é do estilo.css")

            for src in valores(de: "src", em: html) {
                check(src.hasPrefix("midia/"), "\(nome): src fora de midia/: \(src)")
                check(midia.contains(String(src.dropFirst("midia/".count))),
                      "\(nome): mídia inexistente: \(src)")
            }
            for acao in valores(de: "data-acao", em: html) {
                check(acoes.contains(acao), "\(nome): ação desconhecida: \(acao)")
            }
            if html.contains("data-acao=\"instalarPeca\"") {
                for alvo in valores(de: "data-alvo", em: html) where !alvo.isEmpty {
                    // ponytail: o gate não distingue qual data-alvo pertence a
                    // qual data-acao — aceita alvo válido pra qualquer uma das
                    // duas listas. Refinar se um alvo errado escapar.
                    check(pecas.contains(alvo) || paineis.contains(alvo),
                          "\(nome): alvo desconhecido: \(alvo)")
                }
            }
        }
    }

    /// As peças vêm do `PluginID` de verdade (`Plugin.swift`), que o gate
    /// compila junto — é o que faz renomear um caso lá quebrar aqui.
    static let pecas = PluginID.allCases.map(\.rawValue)
    /// Painéis são cópia: `SettingsPane` mora em `SettingsView.swift`, que
    /// arrasta SwiftUI e meia janela de Ajustes pro compile.
    /// ponytail: cópia de 11 strings; o custo de errar é um botão que não abre
    /// painel, e a flag `--ajustes=<painel>` já exercita a lista real.
    static let paineis = ["geral", "notch", "desenho", "ditado", "pomodoro", "lembretes",
                          "descanso", "webhooks", "mensagens", "plugins", "permissoes"]

    /// Valores de um atributo HTML, sem parser: os arquivos são nossos e o
    /// vocabulário é fechado.
    static func valores(de atributo: String, em html: String) -> [String] {
        var saida: [String] = []
        var resto = Substring(html)
        while let inicio = resto.range(of: "\(atributo)=\"") {
            resto = resto[inicio.upperBound...]
            guard let fim = resto.firstIndex(of: "\"") else { break }
            saida.append(String(resto[..<fim]))
            resto = resto[fim...]
        }
        return saida
    }
}
