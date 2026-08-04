//
//  Onboarding.swift
//  Knobler
//
//  Os passos da janela de boas-vindas e o filtro que decide quais deles esta
//  instalação ainda não viu. Vive num arquivo sem dependência nenhuma de
//  propósito — assim o `onboardingcheck` compila o filtro isolado, sem arrastar
//  SwiftUI nem AppSettings (mesma razão do `CalendarAviso`).
//

import Foundation

/// Um passo do wizard. O corpo do texto mora na view; aqui fica só o que o
/// filtro precisa decidir.
struct OnboardingPasso: Equatable {
    let id: String
    let titulo: String
    /// Versão em que o passo nasceu.
    let criadoEm: Int
    /// Versão da última alteração relevante do conteúdo.
    let revisadoEm: Int
}

/// Por que o passo está aparecendo.
enum Novidade: Equatable {
    case novo
    case atualizado
}

struct PassoVisivel: Equatable {
    let passo: OnboardingPasso
    let novidade: Novidade
}

enum Onboarding {
    static let passos: [OnboardingPasso] = [
        OnboardingPasso(id: "apresentacao", titulo: "O Knobler mora no notch",
                        criadoEm: 1, revisadoEm: 1),
        OnboardingPasso(id: "atalhos", titulo: "Dois atalhos globais",
                        criadoEm: 2, revisadoEm: 2),
    ]

    /// O maior `max(criadoEm, revisadoEm)` da lista acima. Subir um passo
    /// **obriga** a subir isto — senão o wizard reabre em todo launch (grava a
    /// versão velha, e o passo novo continua maior que ela). O
    /// `onboardingcheck` pega o esquecimento.
    static let versaoAtual = 2

    static let chaveVersao = "onboarding.versao"
    /// Chave do onboarding de permissões, anterior ao wizard. Quem a tem já
    /// conhece o app: migra pra versão 1 e vê só os atalhos.
    static let chaveLegado = "onboarding.permissoes.apresentado"

    /// Passos que `vista` ainda não viu, na ordem da lista.
    static func visiveis(paraVersao vista: Int,
                         passos: [OnboardingPasso] = passos) -> [PassoVisivel] {
        passos.compactMap { passo in
            guard max(passo.criadoEm, passo.revisadoEm) > vista else { return nil }
            return PassoVisivel(passo: passo, novidade: passo.criadoEm > vista ? .novo : .atualizado)
        }
    }

    static func versaoVista(_ d: UserDefaults = .standard) -> Int {
        if let versao = d.object(forKey: chaveVersao) as? Int { return versao }
        return d.bool(forKey: chaveLegado) ? 1 : 0
    }

    static func marcarVisto(_ d: UserDefaults = .standard) {
        d.set(versaoAtual, forKey: chaveVersao)
    }
}
