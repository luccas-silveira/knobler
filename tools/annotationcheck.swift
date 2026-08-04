import Foundation

@main
struct AnnotationCheck {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("annotationcheck: \(message)") }
    }

    static func main() {
        check(AnnotationTool.allCases.contains(.freehand), "freehand tool missing")
        check(AnnotationTool.allCases.contains(.arrow), "arrow tool missing")
        check(AnnotationTool.allCases.contains(.rectangle), "rectangle tool missing")
        check(AnnotationActivationMode.default == .pressAndHold, "DemoPro default must be press-and-hold")
        check(AnnotationBackground.allCases.count == 3, "annotation backgrounds missing")
        check(AnnotationShortcut.defaultKeyCode == 59, "left Control key code must remain stable")
        let teclas = AnnotationTool.allCases.map(\.key)
        check(Set(teclas).count == teclas.count, "tool shortcuts must be unique")
        check(!teclas.contains(where: { "urxwk".contains($0) }),
              "tool shortcuts must not collide with undo/redo/clear/boards")
        check(AnnotationTool.allCases.allSatisfy { !$0.symbol.isEmpty }, "every tool needs an SF Symbol")

        // cor <-> hex: é o formato que os Ajustes gravam no UserDefaults
        check(AnnotationColor.yellow.hex == "#FFD10D", "yellow should round-trip to hex")
        // ida e volta pelo hex, não igualdade de Double: 0.82 não sobrevive ao
        // arredondamento pra byte, e o que importa é a cor pintada ser a mesma.
        check(AnnotationColor(hex: "#FFD10D")?.hex == AnnotationColor.yellow.hex,
              "hex should parse back to the same color")
        check(AnnotationColor(hex: "ff0000")?.red == 1, "hex without # should parse")
        check(AnnotationColor(hex: "#FFF") == nil, "short hex should be rejected")
        check(AnnotationColor(hex: "nope!!") == nil, "garbage hex should be rejected")

        var document = AnnotationDocument()
        document.append(.init(tool: .freehand, points: [AnnotationPoint(x: 1, y: 2), AnnotationPoint(x: 3, y: 4)]))
        document.append(.init(tool: .arrow, points: [AnnotationPoint(x: 5, y: 6), AnnotationPoint(x: 7, y: 8)]))
        check(document.elements.count == 2, "append should add elements")
        check(document.undo(), "undo should remove the latest element")
        check(document.elements.count == 1, "undo should remove one element")
        check(document.redo(), "redo should restore the latest element")
        check(document.elements.count == 2, "redo should restore one element")
        document.clear()
        check(document.elements.isEmpty, "clear should remove all elements")
        check(document.undo(), "clear should be undoable")
        check(document.elements.count == 2, "undo should restore a cleared document")

        print("annotationcheck: OK")
    }
}
