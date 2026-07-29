//
//  makeicon.swift
//  Gera Knobler/AppIcon.icns a partir da marca do site (a silhueta do notch,
//  mesma geometria de NotchShape.swift / NotchShape.astro).
//
//  Rodar só quando a marca mudar:
//    swiftc -O -o build/makeicon tools/makeicon.swift && ./build/makeicon
//
//  Corpo: squircle preto na grade do macOS (824 pt de corpo num canvas de
//  1024). Marca: o notch VAZADO — buraco de verdade, via even-odd, pra que o
//  ícone leia igual em qualquer fundo.

import AppKit

extension NSBezierPath {
    /// NSBezierPath só tem cúbica; `NotchShape` é escrito em quadráticas.
    /// Conversão exata: C1 = P0 + 2/3(C−P0), C2 = P3 + 2/3(C−P3).
    func quad(to p: CGPoint, control c: CGPoint) {
        let p0 = currentPoint
        curve(to: p,
              controlPoint1: CGPoint(x: p0.x + 2.0 / 3 * (c.x - p0.x),
                                     y: p0.y + 2.0 / 3 * (c.y - p0.y)),
              controlPoint2: CGPoint(x: p.x + 2.0 / 3 * (c.x - p.x),
                                     y: p.y + 2.0 / 3 * (c.y - p.y)))
    }
}

/// Caminho do notch. Porte literal de `NotchShape.path(in:)` — se um dos dois
/// mudar, o outro tem que acompanhar.
///
/// O app desenha com Y pra baixo (SwiftUI) e o AppKit tem Y pra cima, então
/// `minY`/`maxY` trocam de papel: aqui o topo (onde os cantos flarejam pra
/// dentro) é `maxY`.
func notchPath(in rect: CGRect, top: CGFloat, bottom: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    p.quad(to: CGPoint(x: rect.minX + top, y: rect.maxY - top),
           control: CGPoint(x: rect.minX + top, y: rect.maxY))
    p.line(to: CGPoint(x: rect.minX + top, y: rect.minY + bottom))
    p.quad(to: CGPoint(x: rect.minX + top + bottom, y: rect.minY),
           control: CGPoint(x: rect.minX + top, y: rect.minY))
    p.line(to: CGPoint(x: rect.maxX - top - bottom, y: rect.minY))
    p.quad(to: CGPoint(x: rect.maxX - top, y: rect.minY + bottom),
           control: CGPoint(x: rect.maxX - top, y: rect.minY))
    p.line(to: CGPoint(x: rect.maxX - top, y: rect.maxY - top))
    p.quad(to: CGPoint(x: rect.maxX, y: rect.maxY),
           control: CGPoint(x: rect.maxX - top, y: rect.maxY))
    p.close()
    return p
}

/// Um tamanho do ícone. `side` é o canvas inteiro; o corpo ocupa 80,5% dele,
/// que é a proporção da grade de ícones do macOS (824 em 1024).
func renderIcon(side: CGFloat) -> NSBitmapImageRep {
    let px = Int(side)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx

    // Corpo sangrando até a borda do canvas, sem a margem da grade do macOS:
    // ícone com transparência em volta faz o Tahoe compor a arte dentro de
    // uma moldura clara dele, e o resultado é uma borda gigante que não é
    // nossa. O sistema aplica a própria máscara arredondada por cima.
    let bodyRect = CGRect(x: 0, y: 0, width: side, height: side)
    let corner = side * 0.225

    NSColor.black.setFill()
    NSBezierPath(roundedRect: bodyRect, xRadius: corner, yRadius: corner).fill()

    // notch branco centrado, na proporção 22:9 da marca da nav
    let notchW = side * 0.42
    let notchH = notchW * 9 / 22
    let notchRect = CGRect(x: bodyRect.midX - notchW / 2,
                           y: bodyRect.midY - notchH / 2,
                           width: notchW, height: notchH)
    NSColor.white.setFill()
    notchPath(in: notchRect, top: notchW * 3 / 22, bottom: notchW * 5 / 22).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/Knobler.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// nomes que o iconutil exige
let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, side) in sizes {
    let rep = renderIcon(side: side)
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: iconset.appendingPathComponent("\(name).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Knobler/AppIcon.icns"]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil falhou\n".data(using: .utf8)!)
    exit(1)
}
print("Knobler/AppIcon.icns gerado")
