// Gate da página de novidades — o filtro de versões e a migração da base
// instalada.
//
// O erro que este check existe pra pegar é silencioso nos dois sentidos: um
// filtro errado ou nunca abre a página, ou a abre em todo launch.
//
// Arrasta o Updater (comparação de SemVer, como o avisoscheck).
//
// xcrun swiftc -parse-as-library -swift-version 5 \
//   Knobler/Updater.swift Knobler/NovidadesCatalogo.swift tools/novidadescheck.swift \
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

        print("novidadescheck ok")
    }
}
