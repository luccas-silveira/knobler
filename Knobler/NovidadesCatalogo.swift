//
//  NovidadesCatalogo.swift
//  Knobler
//
//  Quais versões da página de novidades esta instalação ainda não viu. Vive num
//  arquivo sem dependência de SwiftUI nem AppSettings de propósito — assim o
//  `novidadescheck` compila o filtro isolado (mesma razão do `CalendarAviso` e
//  do `DevAvisos`).
//
//  A comparação de SemVer é a do `Updater` (`isNewer`/`versionComponents`), a
//  mesma que o `DevAvisos` usa pra faixa de versão. Uma terceira cópia no repo
//  não se justifica.
//

import Foundation

enum NovidadesCatalogo {
    /// Versões com arquivo em `Knobler/Novidades/`. Escrita à mão junto do HTML;
    /// o `novidadescheck` confere que arquivo e lista batem.
    static let versoes: [String] = ["0.25.0"]

    /// A página da primeira abertura. Não é uma versão: nunca entra na
    /// comparação de SemVer.
    static let boasVindas = "boas-vindas"

    static let chaveVersao = "novidades.versaoVista"
    /// Chaves do wizard de boas-vindas, anterior à página.
    static let chaveLegado = "onboarding.versao"
    static let chaveLegadoPermissoes = "onboarding.permissoes.apresentado"

    /// Versão em que o wizard morreu: quem o viu inteiro já conhece tudo até
    /// aqui e só deve ver o que vier depois.
    static let versaoDoWizard = "0.24.0"

    /// Versões a exibir, mais nova primeiro. Instalação limpa vê só a
    /// boas-vindas — o histórico inteiro é longo demais pra primeira impressão.
    static func aExibir(instalada: String,
                        vista: String?,
                        versoes: [String] = versoes) -> [String] {
        guard let vista, vista != "0.0.0" else { return [boasVindas] }
        return versoes
            .filter { isNewer($0, than: vista) && !isNewer($0, than: instalada) }
            .sorted { isNewer($0, than: $1) }
    }

    /// Tudo, na ordem da página: o que o item de menu e a flag `--novidades`
    /// mostram.
    static func tudo(versoes: [String] = versoes) -> [String] {
        versoes.sorted { isNewer($0, than: $1) } + [boasVindas]
    }

    /// `nil` = instalação limpa (nunca viu nada).
    static func versaoVista(_ d: UserDefaults = .standard) -> String? {
        if let versao = d.string(forKey: chaveVersao) { return versao }
        if let wizard = d.object(forKey: chaveLegado) as? Int {
            return wizard >= 2 ? versaoDoWizard : "0.0.0"
        }
        return d.bool(forKey: chaveLegadoPermissoes) ? "0.0.0" : nil
    }

    static func marcarVisto(_ versao: String, _ d: UserDefaults = .standard) {
        d.set(versao, forKey: chaveVersao)
    }
}
