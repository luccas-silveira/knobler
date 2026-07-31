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
        check(AnnotationShortcut.defaultKeyCode == 62, "right Control key code must remain stable")

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
