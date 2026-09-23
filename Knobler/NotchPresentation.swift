// Apresentação do knob: decisões puras, compartilhadas pelo desenho e pela interação.
import Foundation
import CoreGraphics

enum NotchMode: Equatable {
    case closed, music, notification, hud, dictation, question, pomodoro, airpods, airpodsIsland, message, update, tecladoBloqueado
}

struct NotchContentState {
    var question = false
    var incoming = false
    var reply = false
    var dictation = false
    var typingNote = false
    var editingAgenda = false
    var editingReminders = false
    var notification = false
    var hud = false
    var update = false
    var airpods = false
    /// Ilha compacta de conexão dos AirPods; o card (`airpods`) vence ela.
    var airpodsIsland = false
    var expanded = false
    var pomodoro = false
    var focus: NotchSection?
    /// Teclado bloqueado pra limpeza vence tudo: nada mais recebe tecla.
    var tecladoBloqueado = false

    var mode: NotchMode {
        if tecladoBloqueado { return .tecladoBloqueado }
        if question { return .question }
        if incoming { return .message }
        if dictation { return .dictation }
        if typingNote || editingAgenda || editingReminders { return .music }
        if notification { return .notification }
        if hud { return .hud }
        if update { return .update }
        if airpods { return .airpods }
        if airpodsIsland { return .airpodsIsland }
        if expanded { return .music }
        if pomodoro { return .pomodoro }
        return .closed
    }

    var keyboard: Bool {
        switch mode {
        case .question: return true
        case .message: return reply
        case .music: return expanded && ([.nota, .mensagens, .link, .monitores].contains(focus) || editingAgenda || editingReminders)
        default: return false
        }
    }
}

/// Nenhum timer conhece SwiftUI. O relógio entra por parâmetro e cada pedido
/// invalida o anterior, inclusive se o callback cancelado já entrou na fila.
struct NotchOpening {
    struct Pending: Equatable {
        let generation: UInt64
        let deadline: TimeInterval
        let expanded: Bool
    }
    private(set) var expanded = false
    private(set) var hovering = false
    private(set) var pending: Pending?
    private(set) var generation: UInt64 = 0
    private var collapsedAt = -Double.infinity
    static let openDelay = 0.18
    static let closeDelay = 0.30
    static let typingDelay = 3.0
    static let cooldown = 0.45

    mutating func cancel() {
        generation &+= 1
        pending = nil
    }

    mutating func suspend() {
        cancel()
        hovering = false
    }

    mutating func setExpanded(_ value: Bool, now: TimeInterval) {
        cancel()
        if expanded && !value { collapsedAt = now }
        expanded = value
    }

    mutating func hover(_ inside: Bool, typing: Bool, now: TimeInterval) {
        cancel()
        hovering = inside
        if inside {
            guard !expanded, now - collapsedAt >= Self.cooldown else { return }
        }
        pending = Pending(generation: generation,
                          deadline: now + (inside ? Self.openDelay : (typing ? Self.typingDelay : Self.closeDelay)),
                          expanded: inside)
    }

    mutating func fire(_ request: Pending, now: TimeInterval, linkOpen: Bool) -> Bool? {
        guard pending == request, now >= request.deadline else { return nil }
        cancel()
        guard request.expanded || !linkOpen else { return nil }
        setExpanded(request.expanded, now: now)
        return request.expanded
    }
}

struct NotchPresentation: Equatable {
    let mode: NotchMode
    let focus: NotchSection?
    let size: CGSize
    let topInset: CGFloat
    let keyboard: Bool
    let contentID: String

    var compact: Bool { [.closed, .hud, .dictation, .pomodoro, .airpodsIsland].contains(mode) }
    var hoverPadding: CGFloat { mode == .music ? 16 : 0 }
    var interactionSize: CGSize {
        CGSize(width: mode == .music ? size.width + 2 * hoverPadding : 400,
               height: size.height + (mode == .music ? hoverPadding : 10))
    }

    struct Layout {
        var notch = CGSize(width: 200, height: 32)
        var realNotch = true
        var available = CGSize(width: 900, height: 900)
        var closedContent = false
        var sectionHeight: CGFloat = 118
        var sectionWidth: CGFloat = 430
        var notificationActions = false
        /// Altura a mais do card de notificação: subtítulo e, com o mouse em
        /// cima, o texto inteiro. Medida pela NotchView; teto em `notificationExtraMax`.
        var notificationExtra: CGFloat = 0
        var mediaHeight: CGFloat = 0
        var questionSize = CGSize(width: 460, height: 120)
        var contentID = ""
    }

    init(content: NotchContentState, layout: Layout) {
        mode = content.mode
        focus = mode == .music ? content.focus : nil
        keyboard = content.keyboard
        contentID = layout.contentID
        topInset = layout.realNotch ? layout.notch.height : 4
        let target: CGSize
        switch mode {
        case .closed:
            target = CGSize(width: layout.realNotch
                ? layout.notch.width + (layout.closedContent ? 88 : 0)
                : (layout.closedContent ? 200 : 160), height: layout.notch.height)
        case .hud, .dictation, .pomodoro, .airpodsIsland:
            target = CGSize(width: layout.realNotch ? layout.notch.width + 170 : 232,
                            height: layout.notch.height)
        case .music:
            target = CGSize(width: layout.sectionWidth,
                            height: topInset + layout.sectionHeight + 60)
        case .notification:
            target = CGSize(width: 380, height: topInset + (layout.notificationActions ? 92 : 56)
                            + min(max(layout.notificationExtra, 0), Self.notificationExtraMax))
        case .message:
            target = CGSize(width: 360, height: topInset + (content.reply ? 108 : 72)
                            + (layout.mediaHeight > 0 ? layout.mediaHeight + 6 : 0))
        case .airpods:
            // nunca mais estreito que a ilha: senão encolhe sob o cursor na promoção
            let ilha = layout.realNotch ? layout.notch.width + 170 : 232
            target = CGSize(width: max(Self.airpodsCardWidth, ilha), height: topInset + Self.airpodsCardHeight)
        case .update, .tecladoBloqueado: target = CGSize(width: 380, height: topInset + 72)
        case .question:
            target = CGSize(width: layout.questionSize.width, height: topInset + layout.questionSize.height)
        }
        size = CGSize(width: min(target.width, max(1, layout.available.width - 64)),
                      height: min(target.height, max(1, layout.available.height - 24)))
    }

    /// Largura/altura do card de AirPods, lidas também pela NotchView. A largura
    /// cobre a ilha (notch + 170) pra o card não encolher sob o cursor no hover.
    static let airpodsCardWidth: CGFloat = 380
    static let airpodsCardHeight: CGFloat = 184
    /// Teto do texto aberto no hover: o resto é cortado, o card não cresce além.
    static let notificationExtraMax: CGFloat = 200

    /// Janela fixa: reserva folga para hover, sombra e overshoot do card largo.
    static func hostFrame(screen: CGRect, visible: CGRect) -> CGRect {
        let size = CGSize(width: min(screen.width, 900), height: screen.maxY - visible.minY)
        return CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height,
                      width: size.width, height: size.height)
    }
}

/// Medidas usadas tanto pelas seções quanto pelo contêiner; nunca estimadas duas vezes.
enum NotchMetrics {
    static let historyHeight: CGFloat = 260
    static let agendaHeight: CGFloat = 260
    static func alturaAgenda(editando: Bool, disponivel: CGFloat, topo: CGFloat) -> CGFloat {
        min(editando ? 400 : agendaHeight, max(0, disponivel - topo - 84))
    }
    static let annotationButtonHeight: CGFloat = 50
    static let shelfCellHeight: CGFloat = 48 + 3 + 24
    static let sectionStripHeight: CGFloat = 22
    /// Altura do campo da nota. Mesma regra da `historyHeight`:
    /// o `currentSize` soma ESTA constante, então layout e moldura mudam juntos.
    static let noteEditorHeight: CGFloat = 120
    /// O card do link é mais largo que o resto: uma página de site em 386 pt
    /// não é leitura, é miniatura.
    static let linkCardWidth: CGFloat = 780
    /// Sobra depois das margens internas do card (as mesmas 44 do `.frame`).
    static var linkContentWidth: CGFloat { linkCardWidth - 44 }
    /// A página em 16:9, a proporção de tela que o site espera. A altura da
    /// seção soma o cabeçalho de controles.
    static var linkWebHeight: CGFloat { (linkContentWidth * 9 / 16).rounded() }
    static let linkHeaderHeight: CGFloat = 24

    /// Largura do card por seção em foco: só o link foge do padrão — e só
    /// quando tem página. A barra de endereço sozinha não pede 780 pt.
    static func larguraDoCard(_ focus: NotchSection?, padrao: CGFloat,
                              linkAberto: Bool = true) -> CGFloat {
        focus == .link && linkAberto ? linkCardWidth : padrao
    }

    /// A prateleira é a seção com mais alturas: a linha de itens, o preview de
    /// conversão (presets e botões) e a pilha aberta em grade.
    static let shelfPreviewHeight: CGFloat = 112
    /// Derivada e não literal: a grade da pilha muda de tamanho junto com a
    /// célula, e o número solto aqui sairia de sincronia calado.
    static let shelfPilhaHeight: CGFloat =
        18 + 8 + shelfCellHeight * 2 + 8
    /// Espelho fixado e desligado é ícone + botão: os 202 da câmera deixariam
    /// meio card vazio.
    static let espelhoDesligadoHeight: CGFloat = 96
    static func alturaDaSecao(_ s: NotchSection, preview: Bool = false,
                              pilhaAberta: Bool = false,
                              espelhoLigado: Bool = true,
                              linkAberto: Bool = true,
                              eventoProximo: Bool = false) -> CGFloat {
        switch s {
        case .musica: return 118
        // a linha do próximo evento do calendário só existe quando há evento
        case .pomodoro: return eventoProximo ? 150 : 128
        case .atividade: return 60
        // a ordem não é livre: os dois estados podem estar ligados ao mesmo
        // tempo (converter a partir de dentro da pilha aberta), e o
        // `ShelfRowView.body` testa `preview` primeiro. Inverter aqui daria
        // altura de pilha com conteúdo de preview desenhado.
        case .shelf: return preview ? shelfPreviewHeight
                                    : (pilhaAberta ? shelfPilhaHeight : 76)
        case .espelho: return espelhoLigado ? 202 : espelhoDesligadoHeight
        case .mensagens: return 272
        case .historico: return historyHeight + 12
        case .nota: return Self.noteEditorHeight + 28  // +8 do padding da zona de escrita
        case .link: return linkAberto ? linkWebHeight + linkHeaderHeight : espelhoDesligadoHeight
        case .anotacao: return annotationButtonHeight * 2 + 6
        case .agenda: return agendaHeight
        case .lembretesApple: return 330
        case .monitores: return 192
        // dois anéis + até quatro sessões
        case .agentes: return 150
        }
    }

}

struct NotchSectionInputs: Equatable {
    var music = false
    var shelf = false
    var history = false
    var messages = false
    var note = false
    var link = false
    var annotation = false
    var agentes = false
}
