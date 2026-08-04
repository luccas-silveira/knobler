import Foundation

enum AnnotationTool: String, CaseIterable, Codable {
    case freehand, line, arrow, rectangle, ellipse, text, laser, spotlight, eraser

    var title: String {
        switch self {
        case .freehand: return "Desenho livre"
        case .line: return "Linha"
        case .arrow: return "Seta"
        case .rectangle: return "Retângulo"
        case .ellipse: return "Elipse"
        case .text: return "Texto"
        case .laser: return "Laser"
        case .spotlight: return "Holofote"
        case .eraser: return "Borracha"
        }
    }

    /// Símbolo SF do botão da seção Anotação.
    var symbol: String {
        switch self {
        case .freehand: return "scribble"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .text: return "textformat"
        case .laser: return "wand.and.rays"
        case .spotlight: return "flashlight.on.fill"
        case .eraser: return "eraser"
        }
    }

    /// Tecla do atalho enquanto a anotação está ativa — o mesmo mapa do
    /// DemoPro, que é de onde vem o hábito de quem migra.
    var key: Character {
        switch self {
        case .text: return "'"
        case .freehand: return "s"
        case .line: return "q"
        case .arrow: return "a"
        case .rectangle: return "z"
        case .ellipse: return "e"
        case .laser: return "l"
        case .spotlight: return "h"
        case .eraser: return "b"
        }
    }
}

enum AnnotationActivationMode: String, Codable {
    case pressAndHold
    case toggle

    static let `default`: Self = .pressAndHold
}

enum AnnotationBackground: String, CaseIterable, Codable {
    case transparent, white, black

    var title: String {
        switch self {
        case .transparent: return "Transparente"
        case .white: return "Quadro branco"
        case .black: return "Quadro negro"
        }
    }
}

enum AnnotationShortcut {
    /// macOS virtual key code for the left Control key.
    static let defaultKeyCode = 59
}

struct AnnotationPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

struct AnnotationColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let yellow = Self(red: 1, green: 0.82, blue: 0.05, alpha: 1)

    /// `#RRGGBB` — o formato que os Ajustes gravam no UserDefaults. Alpha fica
    /// de fora: nada na UI o expõe, e todo traço nasce opaco.
    var hex: String {
        func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

}

// extension e não corpo do tipo: um `init` lá dentro apagaria o memberwise
// `init(red:green:blue:alpha:)`, que meio mundo usa.
extension AnnotationColor {
    /// Tolera com e sem `#`. Devolve `nil` pra qualquer outra coisa — quem lê o
    /// UserDefaults cai no padrão em vez de pintar preto por acidente.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  alpha: 1)
    }
}

struct AnnotationStyle: Codable, Equatable {
    var color = AnnotationColor.yellow
    var lineWidth = 6.0
    var opacity = 1.0
}

struct AnnotationElement: Codable, Equatable, Identifiable {
    let id: UUID
    var tool: AnnotationTool
    var points: [AnnotationPoint]
    var text: String?
    var style: AnnotationStyle

    init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        points: [AnnotationPoint],
        text: String? = nil,
        style: AnnotationStyle = .init()
    ) {
        self.id = id
        self.tool = tool
        self.points = points
        self.text = text
        self.style = style
    }
}

struct AnnotationDocument: Codable, Equatable {
    private(set) var elements: [AnnotationElement] = []
    private var undoStack: [[AnnotationElement]] = []
    private var redoStack: [[AnnotationElement]] = []

    init() {}

    init(elements: [AnnotationElement]) {
        self.elements = elements
    }

    mutating func append(_ element: AnnotationElement) {
        saveUndoPoint()
        elements.append(element)
        redoStack.removeAll()
    }

    mutating func clear() {
        guard !elements.isEmpty else { return }
        saveUndoPoint()
        elements.removeAll()
        redoStack.removeAll()
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(elements)
        elements = previous
        return true
    }

    @discardableResult
    mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(elements)
        elements = next
        return true
    }

    mutating func remove(_ id: UUID) {
        guard elements.contains(where: { $0.id == id }) else { return }
        saveUndoPoint()
        elements.removeAll { $0.id == id }
        redoStack.removeAll()
    }

    private mutating func saveUndoPoint() {
        undoStack.append(elements)
        if undoStack.count > 100 { undoStack.removeFirst() }
    }
}
