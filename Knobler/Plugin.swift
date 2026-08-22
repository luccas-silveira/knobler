//
//  Plugin.swift
//  Knobler
//
//  A máquina de peças: a ficha de cada feature, o registro, quem está
//  instalado e o host que faz as peças nascerem. Só `Foundation` de propósito
//  — assim o `plugincheck` compila isto isolado, sem arrastar AppKit (mesma
//  razão do `NovidadesCatalogo` e do `CalendarAviso`).
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

/// Os efeitos que a montagem dos Lembretes precisa do app: os itens (vêm do
/// `AppSettings`), o que fazer quando um dispara (card + som) e como desligar
/// um `oneShot` depois do disparo — os três passam por AppKit/SwiftUI.
///
/// `registrarWake` é o caso do observer de `NSWorkspace.didWakeNotification`:
/// exige AppKit, então mora aqui como uma borda emprestada — a ficha só decide
/// QUE existe um wake que precisa tickar o scheduler, não COMO se registra.
/// Recebe o `tick` a chamar e devolve o jeito de desligar (chamado no
/// `parar()`), pra não vazar observer quando a peça é desinstalada.
struct LembretesEfeitos {
    var itens: () -> [Reminder] = { [] }
    var disparou: (Reminder) -> Void = { _ in }
    var desligarUmaVez: (Reminder) -> Void = { _ in }
    var registrarWake: (@escaping () -> Void) -> (() -> Void) = { _ in {} }
}

/// Os efeitos que a montagem do Descanso precisa do app: os itens (vêm do
/// `AppSettings`), o overlay em si (janela de shield, quiosque — `DescansoController`,
/// AppKit) e o wake, no mesmo desenho dos Lembretes.
///
/// `iniciarBloqueio`/`pararBloqueioSeAtivo` são a borda pro `DescansoController`:
/// a ficha não guarda a referência (ele é AppKit, e este arquivo é só-Foundation),
/// só decide QUANDO chamar. `begin` do `DescansoServico` reexpõe `iniciarBloqueio`
/// pro efeito `pausaComecou` do Pomodoro, que fala com o serviço
/// (`plugins.servico(.descanso)`), não com uma referência fixa do `AppDelegate`.
struct DescansoEfeitos {
    var itens: () -> [ScreenBreak] = { [] }
    var iniciarBloqueio: (String, TimeInterval) -> Void = { _, _ in }
    /// Chamado no `parar()`: encerra o overlay em curso, se houver.
    var pararBloqueioSeAtivo: () -> Void = {}
    /// Pro veto de quit (`applicationShouldTerminate`): há bloqueio em curso?
    var estaAtivo: () -> Bool = { false }
    var desligarUmaVez: (ScreenBreak) -> Void = { _ in }
    var registrarWake: (@escaping () -> Void) -> (() -> Void) = { _ in {} }
}

/// Os efeitos que a montagem de Mensagens precisa do app: o perfil próprio
/// (vem do `AppSettings`), o que fazer quando uma mensagem chega (grava no
/// `MessageStore`, mostra o card, busca avatar — passa por `NotchViewModel`/
/// `MessageMedia`, que são AppKit/SwiftUI) e o aviso de nome/foto mudado nos
/// Ajustes, que reanuncia o perfil no Bonjour.
///
/// `registrarMudancaNome` é o mesmo desenho do `registrarWake` dos
/// Lembretes/Descanso: a ficha não conhece `AppSettings`/Combine (só
/// Foundation), então o app empresta a borda — recebe o `tick` a chamar e
/// devolve o jeito de desligar, chamado no `parar()`.
struct MensagensEfeitos {
    var perfilProprio: () -> PeerProfile = { PeerProfile(id: "", name: "") }
    var mensagemChegou: (PeerMessage, PeerProfile?, (Data, MediaKind)?) -> Void = { _, _, _ in }
    var registrarMudancaNome: (@escaping () -> Void) -> (() -> Void) = { _ in {} }
}

/// Os efeitos que a montagem de Notificações externas (webhooks) precisa do
/// app: o card quando uma notificação chega e o ajuste opt-in
/// (`AppSettings.shared.webhookNotifications`) que manda no `start()/stop()`
/// do `WebhookClient` — instalada e desligada por ajuste é estado normal,
/// distinto de desinstalada (a peça nem nasce).
///
/// `registrarMudancaAjuste` é o mesmo desenho do `registrarMudancaNome` de
/// Mensagens: a ficha não conhece `AppSettings`/Combine, então o app empresta
/// a borda — recebe o `tick` a chamar e devolve o jeito de desligar, chamado
/// no `parar()`.
struct WebhooksEfeitos {
    var notificacaoChegou: (NotchNotification) -> Void = { _ in }
    var ativado: () -> Bool = { false }
    var registrarMudancaAjuste: (@escaping () -> Void) -> (() -> Void) = { _ in {} }
}

/// Os efeitos que a montagem do Ditado precisa do app.
///
/// ponytail: diferente das peças anteriores, aqui é UM closure emprestado,
/// não vários tipados. `DictationController` importa `FluidAudio` (pacote
/// SPM) — referenciar o tipo neste arquivo arrastaria `Dictation.swift` (e o
/// pacote) pro compile isolado do `tools/plugincheck.swift`, que é `xcrun
/// swiftc` avulso sem resolução de SPM (diferente do `xcodebuild` do app).
/// `nascer` é a peça inteira: o `AppDelegate` cria o `DictationController`,
/// liga `onState`/`destinationProvider`/`transcriptSink` (tudo AppKit/
/// SwiftUI/AskStore) e chama `start()`. Teto: se uma 2ª peça precisar do
/// mesmo pacote pesado, vale extrair esse desenho pra um tipo nomeado.
///
/// O tap global da ⌥ direita **não** está aqui: quem o segura é o
/// `VolumeHUDController`, feature de fábrica — é dependência para baixo, não
/// plugin→plugin (003-brief). O `AppDelegate` continua dono do
/// `volumeHUD.onRightOption` e repassa pra `plugins.servico(.ditado)`, que é
/// `nil` com a peça desinstalada e vira no-op sozinho (`?.`).
struct DitadoEfeitos {
    var nascer: () -> PluginServico? = { nil }
}

/// Os efeitos que a montagem do Desenho precisa do app. Mesmo desenho do
/// `DitadoEfeitos`: `AnnotationController` é `.shared` (singleton — a tarefa
/// não o transforma em instância, views seguem lendo `.shared` direto) e é
/// AppKit puro, então referenciar o tipo aqui arrastaria AppKit pro compile
/// isolado do `plugincheck` (constraint 1). `nascer` é a peça inteira: liga o
/// singleton (`start()`) e devolve a conformidade `PluginServico` dele
/// (`AnnotationController.swift`), cujo `parar()` chama `stop()` — desmonta
/// os overlays por tela.
struct AnotacaoEfeitos {
    var nascer: () -> PluginServico? = { nil }
}

/// Os efeitos que a montagem do Espelho precisa do app. Mesmo desenho do
/// `DitadoEfeitos`/`AnotacaoEfeitos`: `MirrorController` importa AVFoundation
/// e SwiftUI, então referenciar o tipo aqui arrastaria os dois pro compile
/// isolado do `plugincheck` (constraint 1). `nascer` é a peça inteira: o
/// `AppDelegate` empresta o fechamento que desliga o espelho em todos os
/// notches e desarma o auto-open por calendário — é o que o `parar()`
/// devolvido chama.
struct EspelhoEfeitos {
    var nascer: () -> PluginServico? = { nil }
}

/// Os efeitos que a montagem da Nota rápida precisa do app. Mesmo desenho do
/// `EspelhoEfeitos`: `QuickNote` é `.shared` (singleton — `NotchView` e
/// `NotchViewModel` seguem lendo `.shared` direto) e importa AppKit, então
/// referenciar o tipo aqui arrastaria AppKit pro compile isolado do
/// `plugincheck` (constraint 1). `nascer` só devolve o singleton — ao
/// contrário do Desenho/Espelho não há `start()`: a nota fica dormente
/// (`active == false`) até o interruptor do menu ligá-la.
struct NotaRapidaEfeitos {
    var nascer: () -> PluginServico? = { nil }
}

/// Os efeitos que a montagem do Preview de Link precisa do app. Mesmo desenho
/// do `NotaRapidaEfeitos`: `LinkPreview` é `.shared` (singleton — `Shelf`/
/// `NotchView` seguem lendo direto) e importa AppKit/WebKit, então referenciar
/// o tipo aqui arrastaria os dois pro compile isolado do `plugincheck`
/// (constraint 1). `nascer` só devolve o singleton — sem estado próprio pra
/// ligar, ele já nasce "pronto" (nenhum link aberto).
struct PreviewLinkEfeitos {
    var nascer: () -> PluginServico? = { nil }
}

/// O que a peça recebe pra nascer: a pergunta "a outra peça está instalada?"
/// (a única dependência plugin→plugin é Pomodoro→Descanso, e "não" é caminho
/// normal) e os efeitos que o app empresta.
struct PluginDeps {
    let instalado: (PluginID) -> Bool
    var pomodoro = PomodoroEfeitos()
    var lembretes = LembretesEfeitos()
    var descanso = DescansoEfeitos()
    var mensagens = MensagensEfeitos()
    var webhooks = WebhooksEfeitos()
    var ditado = DitadoEfeitos()
    var anotacao = AnotacaoEfeitos()
    var espelho = EspelhoEfeitos()
    var notaRapida = NotaRapidaEfeitos()
    var previewLink = PreviewLinkEfeitos()
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

    /// A peça já nasce de verdade por aqui. Falso = o `AppDelegate` ainda é quem
    /// cria o serviço, e o `nascer` abaixo é vazio; a vitrine mostra "Em breve"
    /// no lugar do botão, porque instalar o que não nasce seria mentira
    /// (ticket 009). Vira `true` na fase que converter a peça.
    var pronta = false

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
               rotas: [], permissao: nil, pronta: true,
               nascer: montarPomodoro),

        Plugin(id: .lembretes, nome: "Lembretes",
               descricao: "Avisos na hora certa, direto no notch.",
               simbolo: "bell.badge.fill", secao: nil, painel: "lembretes",
               rotas: [], permissao: "calendario", pronta: true,
               nascer: montarLembretes),

        Plugin(id: .descanso, nome: "Descanso",
               descricao: "Trava a tela e obriga a levantar.",
               simbolo: "moon.zzz.fill", secao: nil, painel: "descanso",
               rotas: [], permissao: nil, pronta: true,
               nascer: montarDescanso),

        Plugin(id: .mensagens, nome: "Mensagens",
               descricao: "Recados entre Macs na mesma rede.",
               simbolo: "bubble.left.and.bubble.right.fill",
               secao: "mensagens", painel: "mensagens",
               rotas: [], permissao: nil, pronta: true,
               nascer: montarMensagens),

        Plugin(id: .webhooks, nome: "Notificações externas",
               descricao: "Seus sistemas avisam pelo notch.",
               simbolo: "bell.and.waves.left.and.right.fill",
               secao: nil, painel: "webhooks",
               rotas: [], permissao: nil, pronta: true,
               nascer: montarWebhooks),

        Plugin(id: .ditado, nome: "Ditado",
               descricao: "Fale e o texto aparece onde o cursor está.",
               simbolo: "mic.fill", secao: nil, painel: "ditado",
               rotas: [], permissao: "microfone", pronta: true,
               nascer: montarDitado),

        Plugin(id: .espelho, nome: "Espelho",
               descricao: "Sua câmera no notch antes da reunião.",
               simbolo: "person.crop.square", secao: "espelho", painel: nil,
               rotas: ["POST /mirror"], permissao: "camera", pronta: true,
               nascer: montarEspelho),

        // O nome do card é o do painel ("Desenho"), decidido na F4: os dois
        // aparecem lado a lado na vitrine e o ABRIR levaria a um painel com
        // outro nome. O `PluginID` e a seção do card seguem `anotacao` — mexer
        // neles desinstalaria a peça na máquina de quem já usa (003).
        Plugin(id: .anotacao, nome: "Desenho",
               descricao: "Desenhe por cima da tela.",
               simbolo: "pencil.tip.crop.circle", secao: "anotacao", painel: "desenho",
               rotas: [], permissao: "acessibilidade", pronta: true,
               nascer: montarAnotacao),

        Plugin(id: .notaRapida, nome: "Nota rápida",
               descricao: "Um rascunho sempre à mão no notch.",
               simbolo: "note.text", secao: "nota", painel: nil,
               rotas: [], permissao: nil, pronta: true,
               nascer: montarNotaRapida),

        Plugin(id: .previewLink, nome: "Preview de Link",
               descricao: "Espia o site do link antes de abrir.",
               simbolo: "safari.fill", secao: "link", painel: nil,
               rotas: [], permissao: nil, pronta: true,
               nascer: montarPreviewLink),

        Plugin(id: .conversao, nome: "Conversão de arquivo",
               descricao: "Solte na prateleira e troque o formato.",
               simbolo: "arrow.2.squarepath", secao: nil, painel: nil,
               rotas: [], permissao: nil, pronta: true,
               nascer: montarConversao),
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

    /// As superfícies que sumiram junto com as peças desinstaladas. Devolve o
    /// nome cru (o `rawValue` de `NotchSection`/`SettingsPane`) — quem chama
    /// converte, pra este arquivo seguir Foundation puro.
    static func escondidas(_ campo: KeyPath<Plugin, String?>,
                           instalados: Set<PluginID>) -> Set<String> {
        Set(todos.filter { !instalados.contains($0.id) }.compactMap { $0[keyPath: campo] })
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
    /// Truque de versão do `NovidadesCatalogo`: a migração roda uma vez por versão.
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

// MARK: - O botão da vitrine

/// O que o card oferece. O card **não muda de lugar** entre um estado e outro
/// (006) — só o botão muda, e reinstalar é o desfazer de desinstalar.
enum EstadoDoCard: Equatable {
    /// Peça ainda não convertida: a palavra "Em breve" onde iria o botão.
    case emBreve
    /// Instalada. `ABRIR` é sempre vivo — nada de rótulo cinza morto.
    case abrir
    case instalar

    /// O "⋯" com "Desinstalar (seus dados ficam salvos)" só existe em peça
    /// instalada — desinstalar o que nunca nasceu não quer dizer nada.
    var temMenuDeDesinstalar: Bool { self == .abrir }
}

// MARK: - Quem lê a declaração

/// O lugar do `AppDelegate`: sai de "cria quinze serviços na mão" pra "cria os
/// que estão ligados". Ninguém consulta isto ainda — a fiação é a F2.
final class PluginHost: ObservableObject {
    /// Uma por app: as telas (Ajustes, faixa do notch) precisam saber o que
    /// está instalado sem que o `AppDelegate` costure o host em cada view.
    static let shared = PluginHost()

    private let defaults: UserDefaults
    /// `@Published` porque a barra lateral dos Ajustes tem que perder o painel
    /// no mesmo instante em que o botão da vitrine é clicado — sem isso a lista
    /// só se corrige na próxima abertura da janela.
    @Published private(set) var instalados: Set<PluginID>
    private var vivos: [PluginID: PluginServico] = [:]
    /// Preenchido pelo `AppDelegate` antes do `subir()`.
    var pomodoroEfeitos = PomodoroEfeitos()
    var lembretesEfeitos = LembretesEfeitos()
    var descansoEfeitos = DescansoEfeitos()
    var mensagensEfeitos = MensagensEfeitos()
    var webhooksEfeitos = WebhooksEfeitos()
    var ditadoEfeitos = DitadoEfeitos()
    var anotacaoEfeitos = AnotacaoEfeitos()
    var espelhoEfeitos = EspelhoEfeitos()
    var notaRapidaEfeitos = NotaRapidaEfeitos()
    var previewLinkEfeitos = PreviewLinkEfeitos()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        PluginsInstalados.migrarSePreciso(defaults)
        instalados = PluginsInstalados.ler(defaults)
    }

    private func deps() -> PluginDeps {
        PluginDeps(instalado: { [weak self] id in self?.instalados.contains(id) ?? false },
                   pomodoro: pomodoroEfeitos, lembretes: lembretesEfeitos,
                   descanso: descansoEfeitos, mensagens: mensagensEfeitos,
                   webhooks: webhooksEfeitos, ditado: ditadoEfeitos, anotacao: anotacaoEfeitos,
                   espelho: espelhoEfeitos, notaRapida: notaRapidaEfeitos,
                   previewLink: previewLinkEfeitos)
    }

    /// O launch inteiro. Peça desligada nem é visitada — custo zero de verdade.
    func subir() {
        for peca in PluginRegistry.todos where instalados.contains(peca.id) {
            vivos[peca.id] = peca.nascer(deps())
        }
    }

    func estaInstalado(_ id: PluginID) -> Bool { instalados.contains(id) }

    /// O que o card daquela peça oferece. É a única regra da vitrine: "não
    /// convertida" ganha de tudo, e o resto sai da lista de instalados.
    func estadoDoCard(_ id: PluginID) -> EstadoDoCard {
        guard PluginRegistry.ficha(id)?.pronta == true else { return .emBreve }
        return instalados.contains(id) ? .abrir : .instalar
    }

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

    /// O avesso: o que as telas precisam **esconder**. Superfície que não é de
    /// peça nenhuma (Geral, Notch, Música) nunca aparece aqui, logo nunca some.
    var secoesEscondidas: Set<String> {
        PluginRegistry.escondidas(\.secao, instalados: instalados)
    }
    var paineisEscondidos: Set<String> {
        PluginRegistry.escondidas(\.painel, instalados: instalados)
    }
}

// MARK: - As superfícies perguntando pelo dono

extension NotchSection {
    /// As seções que sumiram com a peça. Quem desenha o card e o editor de
    /// ordem passa isto pro `NotchSectionOrder`, que não conhece o registro.
    static func desinstaladas(_ host: PluginHost = .shared) -> Set<NotchSection> {
        Set(host.secoesEscondidas.compactMap(NotchSection.init(rawValue:)))
    }
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
func montarPomodoro(_ deps: PluginDeps) -> Pomodoro {
    let efeitos = deps.pomodoro
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
        // quem trava a tela é o Descanso: sem a peça, o efeito não roda nem com
        // o ajuste antigo ligado (desinstalar não apaga ajuste — 007).
        guard deps.instalado(.descanso) else { return }
        efeitos.pausaComecou(Pomodoro.duration(of: fase, config: efeitos.config()))
    }
    return p
}

/// A segunda conversão (ticket 010, tarefa 1). `stop()` já invalida o `Timer`
/// de 15s **e** desliga o wake (`wakeUnregister`, ver `Reminders.swift`) — é
/// exatamente o "morrer" que a peça precisa, sem vazar observer.
extension ScheduleEngine: PluginServico {
    func parar() { stop() }
}

/// O nascimento dos Lembretes: era este bloco que morava no `AppDelegate`
/// (v0.23.0, `KnoblerApp.swift:446-472`). Ficou aqui a decisão de ligar os
/// providers e desligar o `oneShot` que acabou de disparar; o `AppDelegate` só
/// empresta os efeitos (card, som, e o registro do wake, que exige AppKit).
func montarLembretes(_ deps: PluginDeps) -> ReminderScheduler {
    let efeitos = deps.lembretes
    let s = ReminderScheduler()
    s.itemsProvider = efeitos.itens
    s.onFire = { r in
        efeitos.disparou(r)
        if case .oneShot = r.schedule { efeitos.desligarUmaVez(r) }
    }
    // ⚠️ o wake é registrado DEPOIS do `start()`: `start()` começa chamando
    // `stop()`, que derruba o `wakeUnregister` (`Reminders.swift`). Registrar
    // antes desligava o observer no mesmo instante — lembrete marcado pra uma
    // hora de sono era perdido, e o `parar()` não tinha mais o que desregistrar.
    s.start()
    s.wakeUnregister = efeitos.registrarWake { [weak s] in s?.tick() }
    return s
}

/// A terceira conversão (tarefa 2). O `ScheduleEngine<ScreenBreak>` já é
/// `PluginServico` pela conformidade genérica acima — o que falta é o overlay:
/// `parar()` tem que encerrar um bloqueio em curso, e o efeito `pausaComecou`
/// do Pomodoro (`montarPomodoro` acima) precisa de um jeito de PEDIR um
/// bloqueio, não só desligar um agendado. `DescansoServico` é essa borda:
/// guarda o scheduler e repassa pro `DescansoController` (via `efeitos`, sem
/// conhecer o tipo — AppKit) tanto o pedido de bloqueio quanto o fim dele.
final class DescansoServico: PluginServico {
    let scheduler = ScheduleEngine<ScreenBreak>()
    private let efeitos: DescansoEfeitos

    init(efeitos: DescansoEfeitos) { self.efeitos = efeitos }

    /// Pro efeito `pausaComecou` do Pomodoro: `plugins.servico(.descanso)?.begin(...)`.
    func begin(label: String, duration: TimeInterval) {
        efeitos.iniciarBloqueio(label, duration)
    }

    /// Pro veto de quit em `applicationShouldTerminate`.
    var isActive: Bool { efeitos.estaAtivo() }

    func parar() {
        efeitos.pararBloqueioSeAtivo()
        scheduler.stop()
    }
}

/// O nascimento do Descanso: era este bloco que morava no `AppDelegate`
/// (v0.23.0, `KnoblerApp.swift:477-495`). Ficou aqui a decisão de ligar os
/// providers e desligar o `oneShot` que acabou de disparar, no mesmo desenho
/// dos Lembretes; o `AppDelegate` só empresta os efeitos (overlay e o
/// registro do wake, que exigem AppKit).
func montarDescanso(_ deps: PluginDeps) -> DescansoServico {
    let efeitos = deps.descanso
    let servico = DescansoServico(efeitos: efeitos)
    let s = servico.scheduler
    s.itemsProvider = efeitos.itens
    s.onFire = { b in
        efeitos.iniciarBloqueio(b.label, TimeInterval(max(1, b.durationMinutes) * 60))
        if case .oneShot = b.schedule { efeitos.desligarUmaVez(b) }
    }
    // Mesma ordem dos Lembretes acima: `start()` chama `stop()`, que zera o
    // `wakeUnregister` — registrar antes matava o observer no nascimento.
    s.start()
    s.wakeUnregister = efeitos.registrarWake { [weak s] in s?.tick() }
    return servico
}

/// A quarta conversão (tarefa 3). Uma peça, dois objetos que precisam viver
/// juntos: mensagem chegada no `LANMessaging` grava no `MessageStore` — um
/// `PluginServico` pequeno é mais curto que inventar dois registros
/// separados na máquina (mesmo motivo do `DescansoServico`).
final class MensagensServico: PluginServico {
    let lanMessaging = LANMessaging()
    let messageStore = MessageStore()
    private var desligarMudancaNome: (() -> Void)?

    init(efeitos: MensagensEfeitos) {
        lanMessaging.profileProvider = efeitos.perfilProprio
        lanMessaging.onIncoming = efeitos.mensagemChegou
        desligarMudancaNome = efeitos.registrarMudancaNome { [weak self] in
            self?.lanMessaging.refreshIdentity()
        }
    }

    /// Era `messageStore.flush()` + `lanMessaging.stop()` no
    /// `applicationWillTerminate` (v0.23.0, `KnoblerApp.swift:1411/1414`) — o
    /// mesmo par vira o "morrer" da peça, mais o observer de nome que não
    /// pode sobreviver à desinstalação.
    func parar() {
        messageStore.flush()
        lanMessaging.stop()
        desligarMudancaNome?()
    }
}

/// O nascimento de Mensagens: era a fiação em `KnoblerApp.swift:360-392`
/// (perfil, recebimento, reanúncio de nome). Ficou aqui a decisão de ligar os
/// providers; o `AppDelegate` empresta o que exige AppSettings/AppKit/SwiftUI
/// (o card e a busca de avatar em `mensagemChegou`, o observer de nome em
/// `registrarMudancaNome`).
func montarMensagens(_ deps: PluginDeps) -> MensagensServico {
    MensagensServico(efeitos: deps.mensagens)
}

/// A quinta conversão (tarefa 4). `shutdown()` já fecha o socket, cancela o
/// `NWPathMonitor` e invalida a sessão — é o "morrer" que a peça precisa, e
/// também desliga o observer do ajuste (`ajusteUnregister`, ver
/// `WebhookClient.swift`), pra não vazar quando a peça é desinstalada.
extension WebhookClient: PluginServico {
    func parar() { shutdown() }
}

/// O nascimento de Notificações externas: era `webhookClient.onNotify = ...`
/// em `KnoblerApp.swift:379` mais o `if AppSettings.shared.webhookNotifications`
/// que ligava/desligava o socket a cada mudança de qualquer ajuste
/// (`:602-606`). Ficou aqui a decisão de aplicar o ajuste no nascimento e a
/// cada mudança dele; o `AppDelegate` empresta o card (AppKit) e o observer
/// do ajuste (Combine/AppSettings).
func montarWebhooks(_ deps: PluginDeps) -> WebhookClient {
    let efeitos = deps.webhooks
    let client = WebhookClient()
    client.onNotify = efeitos.notificacaoChegou
    func aplicarAjuste() {
        if efeitos.ativado() { client.start() } else { client.stop() }
    }
    client.ajusteUnregister = efeitos.registrarMudancaAjuste(aplicarAjuste)
    aplicarAjuste()
    return client
}

/// A sexta conversão (tarefa 5) e a primeira com **gancho global**. A
/// montagem em si (criar o `DictationController`, ligar providers, chamar
/// `start()`) mora inteira em `deps.ditado.nascer` — ver o `ponytail:` em
/// `DitadoEfeitos` sobre por que não dá pra decompor em efeitos tipados aqui
/// como nas peças anteriores. O tap da ⌥ direita não nasce aqui: é do
/// `VolumeHUDController` (factory), e o `AppDelegate` continua repassando pra
/// `plugins.servico(.ditado)` fora desta função.
func montarDitado(_ deps: PluginDeps) -> PluginServico? {
    deps.ditado.nascer()
}

/// A sétima conversão (tarefa 6) e a primeira peça `.shared`: quem nasce e
/// morre aqui é o serviço, não o singleton — `AnnotationController.shared`
/// continua existindo desinstalada (as views o consomem direto), só que
/// parado (`isActive == false`, sem tap nem painel). `deps.anotacao.nascer`
/// chama `AnnotationController.shared.start()` e devolve o próprio singleton
/// como o `PluginServico` (ver a conformidade em `AnnotationController.swift`).
func montarAnotacao(_ deps: PluginDeps) -> PluginServico? {
    deps.anotacao.nascer()
}

/// A oitava conversão (tarefa 7) e a primeira **sem painel de Ajustes** — o
/// `abrir` dela mora na vitrine (`PluginsSettingsPane`), não aqui (ver a seção
/// "O ABRIR das peças sem painel" do plano). Mesmo desenho do `montarDitado`/
/// `montarAnotacao`: a montagem inteira mora em `deps.espelho.nascer`.
func montarEspelho(_ deps: PluginDeps) -> PluginServico? {
    deps.espelho.nascer()
}

/// A nona conversão (tarefa 8) e a segunda **sem painel de Ajustes** — o
/// `abrir` dela também mora na vitrine (`PluginsSettingsPane`). Mesmo desenho
/// do `montarEspelho`: a montagem inteira mora em `deps.notaRapida.nascer`.
func montarNotaRapida(_ deps: PluginDeps) -> PluginServico? {
    deps.notaRapida.nascer()
}

/// A décima conversão (tarefa 9) e a terceira **sem painel de Ajustes** — o
/// `abrir` dela também mora na vitrine (`PluginsSettingsPane`). Mesmo desenho
/// do `montarNotaRapida`: a montagem inteira mora em `deps.previewLink.nascer`.
func montarPreviewLink(_ deps: PluginDeps) -> PluginServico? {
    deps.previewLink.nascer()
}

/// A décima primeira e última conversão (tarefa 10) — e a única sem serviço de
/// verdade nem `nascer` emprestado: `FileConverter` (`FileConverter.swift`) é
/// um utilitário estático (`targets`, `convert`, `uniqueURL`), sem instância
/// nem singleton, e é Foundation puro (só `UniformTypeIdentifiers` além
/// disso), então nem precisa dos closures emprestados das últimas quatro
/// peças — o tipo é citável direto aqui. Não há nada pra ligar/desligar: a
/// peça vive inteira nos guards dos pontos que OFERECEM a conversão (o menu
/// "Converter" da prateleira, `Shelf.swift`), não num processo rodando.
/// `ConversaoServico` existe só pra peça ter uma referência viva enquanto
/// instalada — é o que faz `estaVivo(.conversao)` responder certo.
final class ConversaoServico: PluginServico {
    /// Nada a parar: `FileConverter` não tem timer, observer, socket nem tap
    /// — é uma função pura chamada sob demanda. Desinstalar só precisa fazer
    /// os pontos de uso pararem de oferecer a ação (guard em `estaInstalado`);
    /// não há estado próprio da peça pra desligar aqui.
    func parar() {}
}

func montarConversao(_ deps: PluginDeps) -> PluginServico? {
    ConversaoServico()
}
