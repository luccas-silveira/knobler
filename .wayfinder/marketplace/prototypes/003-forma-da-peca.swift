//
//  003-forma-da-peca.swift
//  Protótipo do ticket "A forma da peça" (.wayfinder/marketplace).
//
//  Não é código do app. É a forma menor que responde às cinco perguntas do
//  ticket e compila sozinha, com asserções no fim provando o comportamento:
//
//      xcrun swiftc -parse-as-library -swift-version 5 \
//        .wayfinder/marketplace/prototypes/003-forma-da-peca.swift \
//        -o /tmp/formadapeca && /tmp/formadapeca
//
//  Decisões que a forma encarna (o "porquê" está na resolução do ticket):
//  1. A peça é DADO, não protocolo: um `struct Plugin` com campos + duas
//     funções (nascer/morrer). Protocolo daria uma classe por feature sem
//     ganho nenhum — as quinze features já são classes diferentes.
//  2. A lista é um array literal (`registro`). Nada de descoberta mágica.
//  3. Nascer/morrer é closure, então serve tanto pra `let x = Servico()`
//     quanto pros quatro singletons `.shared` que não passam pelo AppDelegate.
//  4. Peça desligada não é iterada: quem pergunta "quais seções?" já recebe
//     só as instaladas.
//

import Foundation

// MARK: - A peça

/// Identidade estável da peça. É o que vai pra preferência e pro catálogo;
/// renomear um caso desinstala a peça na máquina de quem já usava.
enum PluginID: String, CaseIterable {
    case pomodoro, descanso, ditado, espelho, nota
    // ... as outras seis do catálogo de 002 entram aqui.
}

/// O que a peça recebe pra nascer. Hoje isso é o punhado de coisas que o
/// AppDelegate injeta na mão em cada serviço; aqui é um saco só, passado a
/// todas. Cresce quando a cobaia mostrar o que falta.
struct PluginDeps {
    let publicar: (String) -> Void
    /// A peça pergunta se outra peça está instalada. "não" é caminho normal:
    /// a opção sai da tela, ninguém avisa nada (decisão de 002).
    let instalado: (PluginID) -> Bool
}

/// Um serviço vivo. A peça devolve isto ao nascer; soltar a referência é o
/// que mata timer/observer/tap. `parar()` existe pro que não morre sozinho
/// no `deinit` (tap global, listener de rede).
protocol PluginServico: AnyObject {
    func parar()
}

/// A peça. Tudo aqui é dado, menos `nascer`.
struct Plugin {
    let id: PluginID
    /// Nome e descrição de produto — é o que a vitrine mostra.
    let nome: String
    let descricao: String
    /// Símbolo SF pro catálogo e pra faixa do notch.
    let simbolo: String

    // --- Superfícies. `nil` = a peça não ocupa aquela superfície. ---

    /// Seção do card aberto (o `rawValue` casa com `NotchSection`).
    let secao: String?
    /// Painel de Ajustes (o `rawValue` casa com `SettingsPane`).
    let painel: String?
    /// Rotas da API local que só existem com a peça instalada (ticket 008).
    let rotas: [String]
    /// Permissão do sistema que a peça exige (fog: "permissões por plugin").
    let permissao: String?

    /// Nasce. Devolve `nil` quando a peça decide não subir (falta dependência,
    /// preferência interna desligada) — isso não é erro.
    let nascer: (PluginDeps) -> PluginServico?
}

// MARK: - O registro

/// A lista. Array literal num arquivo só: esquecer de registrar uma peça é
/// erro de gente, e o remédio é o gate de compilação abaixo, não reflexão.
enum PluginRegistry {
    static let todos: [Plugin] = [
        Plugin(id: .pomodoro, nome: "Pomodoro", descricao: "Ciclos de foco no notch.",
               simbolo: "timer", secao: "pomodoro", painel: "pomodoro",
               rotas: [], permissao: nil,
               nascer: { deps in PomodoroFake(deps: deps) }),

        Plugin(id: .descanso, nome: "Descanso", descricao: "Pausa de tela cheia.",
               simbolo: "moon.zzz.fill", secao: nil, painel: "descanso",
               rotas: [], permissao: nil,
               nascer: { _ in DescansoFake() }),

        Plugin(id: .ditado, nome: "Ditado", descricao: "Fala vira texto.",
               simbolo: "mic.fill", secao: nil, painel: "ditado",
               rotas: [], permissao: "microfone",
               nascer: { _ in DitadoFake() }),

        Plugin(id: .espelho, nome: "Espelho", descricao: "Sua cara antes da call.",
               simbolo: "person.crop.square", secao: "espelho", painel: nil,
               rotas: ["POST /mirror"], permissao: "camera",
               // Singleton: não cria nada, só liga o que já existe.
               nascer: { _ in EspelhoShim() }),

        Plugin(id: .nota, nome: "Nota rápida", descricao: "Um bloco no notch.",
               simbolo: "square.and.pencil", secao: "nota", painel: nil,
               rotas: [], permissao: nil,
               nascer: { _ in NotaShim() }),
    ]

    /// Gate de compilação: falta peça no registro, o check quebra.
    /// No app isto vira uma linha em `tools/check.sh`.
    static var completo: Bool {
        Set(todos.map(\.id)) == Set(PluginID.allCases)
    }
}

// MARK: - Quem lê a declaração

/// O lugar do AppDelegate. Sai de "cria quinze serviços na mão" pra
/// "cria os que estão ligados".
final class PluginHost {
    private var instalados: Set<PluginID>
    private var vivos: [PluginID: PluginServico] = [:]
    /// Só pra demonstração: o que foi publicado.
    private(set) var publicados: [String] = []

    init(instalados: Set<PluginID>) {
        self.instalados = instalados
    }

    private func deps() -> PluginDeps {
        PluginDeps(publicar: { [weak self] texto in self?.publicados.append(texto) },
                   instalado: { [weak self] id in self?.instalados.contains(id) ?? false })
    }

    /// O launch inteiro. Peça desligada nem é visitada — custo zero de verdade.
    func subir() {
        for peca in PluginRegistry.todos where instalados.contains(peca.id) {
            vivos[peca.id] = peca.nascer(deps())
        }
    }

    /// Instalar/desinstalar no meio do uso. Desinstalar chama `parar()` e
    /// solta a referência: é isso que mata timer/observer/tap.
    func desinstalar(_ id: PluginID) {
        instalados.remove(id)
        vivos.removeValue(forKey: id)?.parar()
    }

    func instalar(_ id: PluginID) {
        guard !instalados.contains(id) else { return }
        instalados.insert(id)
        guard let peca = PluginRegistry.todos.first(where: { $0.id == id }) else { return }
        vivos[id] = peca.nascer(deps())
    }

    func estaVivo(_ id: PluginID) -> Bool { vivos[id] != nil }

    /// O serviço vivo, pra quem precisa falar com ele (o AppDelegate hoje já
    /// segura essas referências na mão).
    func servico<T: PluginServico>(_ id: PluginID, as tipo: T.Type = T.self) -> T? {
        vivos[id] as? T
    }

    // --- Superfícies desenhadas a partir da lista, não de `switch` na mão ---

    var secoes: [String] {
        PluginRegistry.todos.filter { instalados.contains($0.id) }.compactMap(\.secao)
    }

    var paineis: [String] {
        PluginRegistry.todos.filter { instalados.contains($0.id) }.compactMap(\.painel)
    }

    var rotas: [String] {
        PluginRegistry.todos.filter { instalados.contains($0.id) }.flatMap(\.rotas)
    }
}

// MARK: - Dublês das features (só o suficiente pra provar a forma)

final class PomodoroFake: PluginServico {
    private let deps: PluginDeps
    private(set) var timerLigado = true
    /// A peça pergunta pela outra. "não" é caminho normal: a opção some.
    var travaTelaNaPausa: Bool { deps.instalado(.descanso) }

    init(deps: PluginDeps) { self.deps = deps }
    func parar() { timerLigado = false }
}

final class DescansoFake: PluginServico {
    func parar() {}
}

final class DitadoFake: PluginServico {
    func parar() {}
}

/// Singleton que já existe hoje (`MirrorController.shared`): a peça não cria,
/// só liga e desliga. Prova que a forma alcança as quatro features `.shared`.
final class EspelhoSingleton {
    static let shared = EspelhoSingleton()
    private(set) var ativo = false
    func ligar() { ativo = true }
    func desligar() { ativo = false }
}

final class EspelhoShim: PluginServico {
    init() { EspelhoSingleton.shared.ligar() }
    func parar() { EspelhoSingleton.shared.desligar() }
}

final class NotaShim: PluginServico {
    func parar() {}
}

// MARK: - Check

@main
enum Demo {
    static func main() {
        // O gate: registro cobre todos os ids.
        assert(PluginRegistry.completo, "peça fora do registro")

        // 1. Peça desligada não nasce.
        let host = PluginHost(instalados: [.pomodoro, .descanso, .espelho])
        host.subir()
        assert(host.estaVivo(.pomodoro))
        assert(!host.estaVivo(.ditado), "peça desinstalada nasceu")

        // 2. Superfície de peça desligada não aparece na iteração.
        assert(host.secoes == ["pomodoro", "espelho"], "seções: \(host.secoes)")
        assert(!host.paineis.contains("ditado"))
        assert(host.rotas == ["POST /mirror"])

        // 3. Singleton entra na forma: nasceu ligado.
        assert(EspelhoSingleton.shared.ativo)

        // 4. Peça pergunta por peça. Com Descanso instalado, a opção existe.
        let pomodoro = host.servico(.pomodoro, as: PomodoroFake.self)!
        assert(pomodoro.travaTelaNaPausa)

        // 5. Desinstalar mata o serviço — é disso que depende o custo zero.
        host.desinstalar(.descanso)
        assert(!pomodoro.travaTelaNaPausa, "opção sobreviveu à desinstalação")
        host.desinstalar(.espelho)
        assert(!EspelhoSingleton.shared.ativo, "singleton continuou ligado")
        host.desinstalar(.pomodoro)
        assert(!pomodoro.timerLigado, "timer sobreviveu à desinstalação")

        // 6. Instalar no meio do uso.
        host.instalar(.ditado)
        assert(host.estaVivo(.ditado))
        assert(host.paineis.contains("ditado"))

        print("forma da peça: ok")
    }
}
