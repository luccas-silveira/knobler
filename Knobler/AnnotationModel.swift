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
    /// macOS virtual key code for the right Control key.
    static let defaultKeyCode = 62
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
