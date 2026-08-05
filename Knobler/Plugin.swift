//
//  Plugin.swift
//  Knobler
//
//  A máquina de peças: a ficha de cada feature, o registro, quem está
//  instalado e o host que faz as peças nascerem. Só `Foundation` de propósito
//  — assim o `plugincheck` compila isto isolado, sem arrastar AppKit (mesma
//  razão do `Onboarding` e do `CalendarAviso`).
//
//  A forma é a do protótipo `.wayfinder/marketplace/prototypes/003-forma-da-peca.swift`:
//  a peça é DADO (um struct com campos) mais UMA closure `nascer`. Nada de
//  protocolo por feature, nada de descoberta mágica — a lista é literal.
//

import Foundation

// MARK: - A peça

/// Identidade estável da peça. É o que vai pro `UserDefaults` e pra vitrine;
/// renomear um caso desinstala a peça na máquina de quem já usava.
enum PluginID: String, CaseIterable {
    case pomodoro, lembretes, descanso, mensagens, webhooks, ditado
    case espelho, anotacao, notaRapida, previewLink, conversao
}

/// Um serviço vivo. A peça devolve isto ao nascer; soltar a referência é o que
/// mata timer/observer/tap. `parar()` existe pro que não morre sozinho no
/// `deinit` (tap global, listener de rede).
protocol PluginServico: AnyObject {
    func parar()
}

/// Os efeitos que a montagem do Pomodoro precisa do app: ajustes, telas, som e
/// o overlay do Descanso. A ficha faz a ligação (quem escuta o quê, os guards,
/// a borda); estes closures são só "como o app cumpre" cada efeito — nenhum
/// deles pode morar aqui, porque todos passam por AppKit.
///
/// ponytail: campos com nome de uma peça só num tipo próprio. Quando a segunda
/// e a terceira peça converterem, isto vira um saco de efeitos por peça (ou um
/// protocolo). Com uma cobaia, um struct nomeado é o mais curto que funciona.
struct PomodoroEfeitos {
    var config: () -> Pomodoro.Config = { .padrao }
    /// Estado pras telas (nil = idle).
    var publicarEstado: (PomodoroState?) -> Void = { _ in }
    /// Só nas bordas ligado/desligado — a ficha filtra os tiques de 1 s.
    var atividadeMudou: (Bool) -> Void = { _ in }
    /// Fase que acabou, próxima. O app notifica e toca o som.
    var fimDeFase: (PomodoroPhase, PomodoroPhase) -> Void = { _, _ in }
    /// Uma pausa começou a rodar, com esta duração. O app decide se trava a
    /// tela (é um ajuste do usuário).
    var pausaComecou: (TimeInterval) -> Void = { _ in }
}

/// O que a peça recebe pra nascer: a pergunta "a outra peça está instalada?"
/// (a única dependência plugin→plugin é Pomodoro→Descanso, e "não" é caminho
/// normal) e os efeitos que o app empresta.
struct PluginDeps {
    let instalado: (PluginID) -> Bool
    var pomodoro = PomodoroEfeitos()
}

/// A ficha da peça. Tudo aqui é dado, menos `nascer`.
struct Plugin {
    let id: PluginID
    /// Nome e frase de produto — é o que a vitrine mostra.
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
    /// Permissão do sistema que a peça exige.
    let permissao: String?

    /// Nasce. Devolve `nil` quando a peça decide não subir (falta dependência,
    /// preferência interna desligada) — isso não é erro. Peça ainda não
    /// convertida tem `nascer` vazio: quem cria o serviço é o `AppDelegate`,
    /// como sempre foi.
    let nascer: (PluginDeps) -> PluginServico?
}

/// Ficha decorativa das quatro de fábrica (Música/HUDs, Notificações,
/// Prateleira, AirPods). Não têm `PluginID` nem `nascer`: existem só pra
/// vitrine mostrar "Incluído no Knobler" (ticket 006).
struct PluginDeFabrica {
    let nome: String
    let descricao: String
    let simbolo: String
}

// MARK: - O registro

/// A lista. Array literal num arquivo só: esquecer de registrar uma peça é
/// erro de gente, e o remédio é o gate `plugincheck`, não reflexão.
///
/// Nomes, frases e símbolos são os do protótipo da vitrine (ticket 006) — a F4
/// bate o martelo neles.
enum PluginRegistry {
    static let todos: [Plugin] = [
        Plugin(id: .pomodoro, nome: "Pomodoro",
               descricao: "Ciclos de foco com pausa contada.",
               simbolo: "timer", secao: "pomodoro", painel: "pomodoro",
               rotas: [], permissao: nil,
               nascer: { deps in montarPomodoro(deps.pomodoro) }),

        Plugin(id: .lembretes, nome: "Lembretes",
               descricao: "Avisos na hora certa, direto no notch.",
               simbolo: "bell.badge.fill", secao: nil, painel: "lembretes",
               rotas: [], permissao: "calendario",
               nascer: { _ in nil }),

        Plugin(id: .descanso, nome: "Descanso",
               descricao: "Trava a tela e obriga a levantar.",
               simbolo: "moon.zzz.fill", secao: nil, painel: "descanso",
               rotas: [], permissao: nil,
               nascer: { _ in nil }),

        Plugin(id: .mensagens, nome: "Mensagens",
               descricao: "Recados entre Macs na mesma rede.",
               simbolo: "bubble.left.and.bubble.right.fill",
               secao: "mensagens", painel: "mensagens",
               rotas: [], permissao: nil,
               nascer: { _ in nil }),

        Plugin(id: .webhooks, nome: "Notificações externas",
               descricao: "Seus sistemas avisam pelo notch.",
               simbolo: "bell.and.waves.left.and.right.fill",
               secao: nil, painel: "webhooks",
               rotas: [], permissao: nil,
               nascer: { _ in nil }),

        Plugin(id: .ditado, nome: "Ditado",
               descricao: "Fale e o texto aparece onde o cursor está.",
               simbolo: "mic.fill", secao: nil, painel: "ditado",
               rotas: [], permissao: "microfone",
               nascer: { _ in nil }),

        Plugin(id: .espelho, nome: "Espelho",
               descricao: "Sua câmera no notch antes da reunião.",
               simbolo: "person.crop.square", secao: "espelho", painel: nil,
               rotas: ["POST /mirror"], permissao: "camera",
               nascer: { _ in nil }),

        Plugin(id: .anotacao, nome: "Anotação",
               descricao: "Desenhe por cima da tela.",
               simbolo: "pencil.tip.crop.circle", secao: "anotacao", painel: "desenho",
               rotas: [], permissao: "acessibilidade",
               nascer: { _ in nil }),

        Plugin(id: .notaRapida, nome: "Nota rápida",
               descricao: "Um rascunho sempre à mão no notch.",
               simbolo: "note.text", secao: "nota", painel: nil,
               rotas: [], permissao: nil,
               nascer: { _ in nil }),

        Plugin(id: .previewLink, nome: "Preview de Link",
               descricao: "Espia o site do link antes de abrir.",
               simbolo: "safari.fill", secao: "link", painel: nil,
               rotas: [], permissao: nil,
               nascer: { _ in nil }),

        Plugin(id: .conversao, nome: "Conversão de arquivo",
               descricao: "Solte na prateleira e troque o formato.",
               simbolo: "arrow.2.squarepath", secao: nil, painel: nil,
               rotas: [], permissao: nil,
               nascer: { _ in nil }),
    ]

    static let deFabrica: [PluginDeFabrica] = [
        PluginDeFabrica(nome: "Música",
                        descricao: "Faixa tocando e volume/brilho no notch.",
                        simbolo: "music.note"),
        PluginDeFabrica(nome: "Notificações",
                        descricao: "Avisos do Mac aparecem no notch.",
                        simbolo: "bell.fill"),
        PluginDeFabrica(nome: "Prateleira",
                        descricao: "Arraste arquivos pro notch e leve com você.",
                        simbolo: "tray.full.fill"),
        PluginDeFabrica(nome: "AirPods",
                        descricao: "Bateria e conexão dos seus fones.",
                        simbolo: "airpodspro"),
    ]

    static func ficha(_ id: PluginID) -> Plugin? {
        todos.first { $0.id == id }
    }

    /// Gate: falta peça no registro, o `plugincheck` quebra.
    static var completo: Bool {
        Set(todos.map(\.id)) == Set(PluginID.allCases)
    }
}

// MARK: - O instalado

/// Instalado é uma **lista de ids** numa chave só (ticket 005), não um booleano
/// por plugin: uma leitura responde tudo, e id que sai do catálogo não vira
/// lixo nos ajustes.
enum PluginsInstalados {
    static let chave = "pluginsInstalados"
    /// Truque de versão do `Onboarding`: a migração roda uma vez por versão.
    static let chaveMigracao = "plugins.migracao"
    /// Subir isto reinstala tudo em todo mundo — só faz sentido se um dia a
    /// regra "todos instalados" mudar. Hoje: 1.
    static let versaoMigracao = 1

    /// Todo mundo atravessa com os 11 instalados — quem atualiza e quem instala
    /// do zero. Roda uma vez só.
    static func migrarSePreciso(_ d: UserDefaults = .standard) {
        guard d.integer(forKey: chaveMigracao) < versaoMigracao else { return }
        d.set(PluginID.allCases.map(\.rawValue), forKey: chave)
        d.set(versaoMigracao, forKey: chaveMigracao)
    }

    /// Id desconhecido é ignorado **calado** — plugin que volte com o mesmo
    /// nome volta instalado (ticket 005).
    static func ler(_ d: UserDefaults = .standard) -> Set<PluginID> {
        Set((d.stringArray(forKey: chave) ?? []).compactMap(PluginID.init(rawValue:)))
    }

    /// Grava preservando os ids órfãos que já estavam lá: desinstalar não apaga
    /// nada, e um id que este build não conhece não é lixo, é peça de outra
    /// versão.
    static func gravar(_ ids: Set<PluginID>, _ d: UserDefaults = .standard) {
        let conhecidos = Set(PluginID.allCases.map(\.rawValue))
        let orfaos = (d.stringArray(forKey: chave) ?? []).filter { !conhecidos.contains($0) }
        d.set(PluginID.allCases.filter(ids.contains).map(\.rawValue) + orfaos, forKey: chave)
    }
}

// MARK: - Quem lê a declaração

/// O lugar do `AppDelegate`: sai de "cria quinze serviços na mão" pra "cria os
/// que estão ligados". Ninguém consulta isto ainda — a fiação é a F2.
final class PluginHost {
    private let defaults: UserDefaults
    private(set) var instalados: Set<PluginID>
    private var vivos: [PluginID: PluginServico] = [:]
    /// Preenchido pelo `AppDelegate` antes do `subir()`.
    var pomodoroEfeitos = PomodoroEfeitos()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        PluginsInstalados.migrarSePreciso(defaults)
        instalados = PluginsInstalados.ler(defaults)
    }

    private func deps() -> PluginDeps {
        PluginDeps(instalado: { [weak self] id in self?.instalados.contains(id) ?? false },
                   pomodoro: pomodoroEfeitos)
    }

    /// O launch inteiro. Peça desligada nem é visitada — custo zero de verdade.
    func subir() {
        for peca in PluginRegistry.todos where instalados.contains(peca.id) {
            vivos[peca.id] = peca.nascer(deps())
        }
    }

    func estaInstalado(_ id: PluginID) -> Bool { instalados.contains(id) }

    func estaVivo(_ id: PluginID) -> Bool { vivos[id] != nil }

    /// O serviço vivo, pra quem precisa falar com ele.
    func servico<T: PluginServico>(_ id: PluginID, as tipo: T.Type = T.self) -> T? {
        vivos[id] as? T
    }

    /// Desinstalar chama `parar()` e solta a referência: é disso que o custo
    /// zero depende. Dado em disco fica onde está (ticket 007).
    func desinstalar(_ id: PluginID) {
        guard instalados.remove(id) != nil else { return }
        PluginsInstalados.gravar(instalados, defaults)
        vivos.removeValue(forKey: id)?.parar()
    }

    func instalar(_ id: PluginID) {
        guard !instalados.contains(id) else { return }
        instalados.insert(id)
        PluginsInstalados.gravar(instalados, defaults)
        guard let peca = PluginRegistry.ficha(id) else { return }
        vivos[id] = peca.nascer(deps())
    }

    // --- Superfícies desenhadas a partir da lista, não de `switch` na mão ---

    private var instaladas: [Plugin] {
        PluginRegistry.todos.filter { instalados.contains($0.id) }
    }

    var secoes: [String] { instaladas.compactMap(\.secao) }
    var paineis: [String] { instaladas.compactMap(\.painel) }
    var rotas: [String] { instaladas.flatMap(\.rotas) }
}

// MARK: - Conformidades das features convertidas

/// Cobaia do piloto (ticket 004). `reset()` já invalida o `Timer` de 1 s e
/// publica idle — é exatamente o "morrer" que a peça precisa.
extension Pomodoro: PluginServico {
    func parar() { reset() }
}

/// O nascimento do Pomodoro: era este bloco que morava no `AppDelegate`
/// (v0.22.0, `KnoblerApp.swift:410-438`). Ficou aqui a decisão de quem escuta o
/// quê, a borda de atividade e o filtro "só pausa trava a tela"; o `AppDelegate`
/// só empresta os efeitos.
func montarPomodoro(_ efeitos: PomodoroEfeitos) -> Pomodoro {
    let p = Pomodoro()
    p.configProvider = efeitos.config
    // `onState` chega a cada segundo; a atividade só interessa nas bordas —
    // republicar a cada tique carimbaria evento de seção sem parar.
    var ativo = false
    p.onState = { estado in
        efeitos.publicarEstado(estado)
        let agora = estado != nil   // parado chega como nil, não como .idle
        guard agora != ativo else { return }
        ativo = agora
        efeitos.atividadeMudou(agora)
    }
    p.onPhaseEnd = efeitos.fimDeFase
    p.onPhaseBegin = { fase in
        guard fase == .shortBreak || fase == .longBreak else { return }
        efeitos.pausaComecou(Pomodoro.duration(of: fase, config: efeitos.config()))
    }
    return p
}
