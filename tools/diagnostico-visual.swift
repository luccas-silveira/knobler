// Coleta pontual do defeito visual no app instalado, sem reiniciá-lo.
// Grava geometria e imagens somente no diretório temporário do sistema.
// Os PNGs podem conter notas/mensagens visíveis; não devem ser commitados.
// Executar com: bash tools/diagnostico-visual.sh

import AppKit
import ApplicationServices
import ScreenCaptureKit

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}
func geometry(_ element: AXUIElement, depth: Int = 0) -> [String: Any] {
    var result: [String: Any] = ["role": attribute(element, kAXRoleAttribute) as? String ?? "unknown"]
    if let value = attribute(element, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
        var point = CGPoint.zero
        if AXValueGetValue(value as! AXValue, .cgPoint, &point) { result["position"] = [point.x, point.y] }
    }
    if let value = attribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
        var size = CGSize.zero
        if AXValueGetValue(value as! AXValue, .cgSize, &size) { result["size"] = [size.width, size.height] }
    }
    // ponytail: limita profundidade e filhos; uma árvore maior pode sair truncada.
    if depth < 6, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
        result["children"] = children.prefix(80).map { geometry($0, depth: depth + 1) }
    }
    return result
}
@main
struct Capture {
    @MainActor
    static func main() async {
        do { try await capturar() }
        catch {
            fputs("Falha na coleta visual: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    static func capturar() async throws {
        _ = NSApplication.shared
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.zoi.knobler" }) else {
            throw NSError(domain: "KnoblerDiagnostico", code: 1, userInfo: [NSLocalizedDescriptionKey: "Knobler não está em execução"])
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("knobler-visual-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var evidence: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "pid": app.processIdentifier]
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        evidence["accessibilityTrusted"] = AXIsProcessTrusted()
        evidence["accessibilityWindows"] = (attribute(axApp, kAXWindowsAttribute) as? [AXUIElement] ?? []).map { geometry($0) }
        evidence["screens"] = NSScreen.screens.map { screen -> [String: Any] in
            ["display": (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
             "frame": [screen.frame.minX, screen.frame.minY, screen.frame.width, screen.frame.height],
             "scale": screen.backingScaleFactor, "safeAreaTop": screen.safeAreaInsets.top]
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: URL(string: "http://127.0.0.1:4477/status")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let status = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "KnoblerDiagnostico", code: 2, userInfo: [NSLocalizedDescriptionKey: "API local não retornou status válido"])
        }
        let fields = Set(["display", "mode", "focus", "visible", "frame"])
        evidence["notches"] = (status["notches"] as? [[String: Any]] ?? []).map { $0.filter { fields.contains($0.key) } }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        var captures: [[String: Any]] = []
        for window in content.windows where window.owningApplication?.processID == app.processIdentifier {
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            config.showsCursor = false
            let start = ISO8601DateFormatter().string(from: Date())
            do {
                let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
                let name = "window-\(window.windowID).png"
                guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { continue }
                try png.write(to: dir.appendingPathComponent(name))
                captures.append(["windowID": window.windowID, "date": start, "frame": [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height], "file": name])
            } catch {
                captures.append(["windowID": window.windowID, "date": start, "error": error.localizedDescription])
            }
        }
        evidence["captures"] = captures
        let json = try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: dir.appendingPathComponent("geometry.json"))
        print(dir.path)
    }
}
