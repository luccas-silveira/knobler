// Gate do onboarding — o filtro de passos por versão e a leitura da chave
// (incluindo a migração da base instalada).
//
// O erro que este check existe pra pegar é silencioso nos dois sentidos: um
// filtro errado ou nunca abre o wizard, ou o abre em todo launch.
//
// xcrun swiftc -parse-as-library -swift-version 5 \
//   Knobler/Onboarding.swift tools/onboardingcheck.swift \
//   -o /tmp/onboardingcheck && /tmp/onboardingcheck

import Foundation

@main
struct OnboardingCheck {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("onboardingcheck: \(message)") }
    }

    /// Lista fixa do teste — a de produção muda, as asserções não deviam.
    static let a = OnboardingPasso(id: "a", titulo: "A", criadoEm: 1, revisadoEm: 1)
    static let b = OnboardingPasso(id: "b", titulo: "B", criadoEm: 2, revisadoEm: 2)
    /// Nasceu na 1 e foi revisado na 3.
    static let c = OnboardingPasso(id: "c", titulo: "C", criadoEm: 1, revisadoEm: 3)

    static func ids(_ vistos: [PassoVisivel]) -> [String] { vistos.map(\.passo.id) }

    static func main() {
        let lista = [a, b, c]

        // instalação nova: vê tudo, tudo é novo
        let zero = Onboarding.visiveis(paraVersao: 0, passos: lista)
        check(ids(zero) == ["a", "b", "c"], "vista 0 deve ver todos os passos")
        check(zero.allSatisfy { $0.novidade == .novo }, "vista 0: tudo é novo")

        // passo novo: só ele, marcado "Novo"
        let um = Onboarding.visiveis(paraVersao: 1, passos: lista)
        check(ids(um) == ["b", "c"], "vista 1 vê o passo novo e o revisado")
        check(um.first?.novidade == .novo, "b nasceu depois da 1: novo")

        // passo revisado: criadoEm <= vista < revisadoEm → "Atualizado"
        let dois = Onboarding.visiveis(paraVersao: 2, passos: lista)
        check(ids(dois) == ["c"], "vista 2 vê só o revisado")
        check(dois.first?.novidade == .atualizado, "c já era conhecido: atualizado")

        // ordem preservada
        check(ids(Onboarding.visiveis(paraVersao: 0, passos: [c, a])) == ["c", "a"],
              "a ordem da lista é a da apresentação")

        // usuário em dia → nada, e portanto o wizard não abre
        check(Onboarding.visiveis(paraVersao: 3, passos: lista).isEmpty,
              "vista acima do topo não vê nada")

        // === lista de produção ===
        // versaoAtual desatualizada reabriria o wizard pra sempre
        check(Onboarding.visiveis(paraVersao: Onboarding.versaoAtual).isEmpty,
              "versaoAtual não cobre todos os passos — o wizard reabriria em todo launch")
        check(ids(Onboarding.visiveis(paraVersao: 0)) == ["apresentacao", "atalhos"],
              "instalação nova vê os dois passos")
        // base migrada: já conhece o app, só não conhece os atalhos
        check(ids(Onboarding.visiveis(paraVersao: 1)) == ["atalhos"],
              "base migrada vê só os atalhos")

        // === leitura da chave ===
        let suite = "com.zoi.knobler.onboardingcheck"
        guard let d = UserDefaults(suiteName: suite) else {
            fatalError("onboardingcheck: suite de teste não abriu")
        }
        d.removePersistentDomain(forName: suite)
        check(Onboarding.versaoVista(d) == 0, "suite vazia é instalação nova")

        d.set(true, forKey: Onboarding.chaveLegado)
        check(Onboarding.versaoVista(d) == 1, "chave legada migra pra versão 1")

        Onboarding.marcarVisto(d)
        check(Onboarding.versaoVista(d) == Onboarding.versaoAtual,
              "a chave nova ganha da legada")
        d.removePersistentDomain(forName: suite)

        print("onboardingcheck: OK")
    }
}
