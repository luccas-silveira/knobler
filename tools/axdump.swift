//
//  tools/axdump.swift — despeja a árvore de Acessibilidade das janelas da
//  Central de Notificações. Serve pra descobrir o formato de um alerta (AirDrop,
//  pedido de permissão…) antes de escrever heurística no interceptor.
//  NÃO faz parte do alvo do app.
//
//  Rodar (com o alerta NA TELA):
//  xcrun swiftc -parse-as-library -swift-version 5 tools/axdump.swift -o /tmp/axdump \
//    && /tmp/axdump
//
//  Precisa de Acessibilidade pro binário/terminal que executa.
//

import AppKit
import ApplicationServices

@main
struct AXDump {
    static func main() {
        guard AXIsProcessTrusted() else {
            print("⚠️  sem permissão de Acessibilidade para este processo")
            exit(1)
        }
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.notificationcenterui").first
        else {
            print("Central de Notificações não está rodando")
            exit(1)
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        let windows = copy(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
        print("janelas: \(windows.count)")
        for (i, window) in windows.enumerated() {
            print("── janela \(i) ──")
            dump(window)
        }
    }

    static func dump(_ element: AXUIElement, depth: Int = 0) {
        guard depth <= 12 else { return }
        let pad = String(repeating: "  ", count: depth)
        var line = "\(pad)\(string(element, kAXRoleAttribute) ?? "?")"
        if let subrole = string(element, kAXSubroleAttribute) { line += " [\(subrole)]" }
        if let title = string(element, kAXTitleAttribute), !title.isEmpty {
            line += " title=\(title.debugDescription)"
        }
        if let value = string(element, kAXValueAttribute), !value.isEmpty {
            line += " value=\(value.debugDescription)"
        }
        if let desc = string(element, kAXDescriptionAttribute), !desc.isEmpty {
            line += " desc=\(desc.debugDescription)"
        }
        let actions = actionNames(element)
        if !actions.isEmpty { line += " actions=\(actions)" }
        print(line)
        for child in children(element) { dump(child, depth: depth + 1) }
    }

    // MARK: - Helpers AX

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        copy(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func actionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }
}
