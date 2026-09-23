//
//  TextoDaTelaServico.swift
//  Knobler
//
//  O coordenador do Texto da tela: permissão, foto de cada monitor, camada de
//  seleção, OCR, clipboard e aviso no notch. É o PluginServico da peça —
//  nascer registra o ⌃⇧T, parar() o remove.
//

import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import os

private let log = Logger(subsystem: "com.zoi.knobler", category: "TextoDaTela")

final class TextoDaTelaServico: PluginServico {
    static let atalho = KeyboardShortcuts.Name(
        "textoDaTela",
        default: .init(carbonKeyCode: kVK_ANSI_T, carbonModifiers: controlKey | shiftKey))

    private let avisar: (NotchNotification) -> Void
    private var selecao: SelecaoDeTela?
    private var ocupado = false
    /// Apaga o ícone da faixa do notch quando a peça desliga.
    var aoParar: (() -> Void)?

    init(avisar: @escaping (NotchNotification) -> Void) {
        self.avisar = avisar
        KeyboardShortcuts.enable(Self.atalho)
        KeyboardShortcuts.onKeyDown(for: Self.atalho) { [weak self] in self?.acionar() }
    }

    func parar() {
        KeyboardShortcuts.removeHandlers(for: Self.atalho)
        selecao?.cancelar()
        aoParar?()
    }

    /// Atalho, ícone do notch ou menu. Segundo toque com a seleção aberta é ignorado.
    func acionar() {
        guard !ocupado else { return }
        guard CGPreflightScreenCaptureAccess() else {
            // Primeiro pedido mostra o balão; depois dele o macOS não pergunta
            // de novo (e o status não distingue negada de nunca pedida), então
            // os acionamentos seguintes abrem os Ajustes no painel certo.
            let chave = "textoDaTela.pediuGravacao"
            if UserDefaults.standard.bool(forKey: chave) {
                NSWorkspace.shared.open(Permission.gravacaoTela.settingsURL)
            } else {
                UserDefaults.standard.set(true, forKey: chave)
                Permission.gravacaoTela.request {}
            }
            return
        }
        ocupado = true
        Task { @MainActor in
            do {
                let fotos = try await Self.fotografar()
                // sem foto nenhuma a camada não abriria e o serviço ficaria preso em `ocupado`
                guard !fotos.isEmpty else { return falhou() }
                let camada = SelecaoDeTela(fotos: fotos) { [weak self] resultado in
                    self?.selecao = nil
                    guard let self else { return }
                    guard let escolha = resultado,
                          let foto = fotos.first(where: { $0.tela == escolha.0 })?.foto else {
                        self.ocupado = false
                        return
                    }
                    self.ler(foto: foto, tela: escolha.0, rect: escolha.1)
                }
                selecao = camada
                camada.mostrar()
            } catch {
                log.error("captura falhou: \(error.localizedDescription, privacy: .public)")
                falhou()
            }
        }
    }

    private func ler(foto: CGImage, tela: NSScreen, rect: CGRect) {
        let escala = CGFloat(foto.width) / tela.frame.width
        let pixels = TextoDaTela.recortePixels(selecao: rect, tela: tela.frame, escala: escala)
        guard let recorte = foto.cropping(to: pixels) else { return falhou() }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let resultado = Result { try TextoDaTela.linhas(em: recorte) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.ocupado = false
                switch resultado {
                case .failure(let error):
                    log.error("OCR falhou: \(error.localizedDescription, privacy: .public)")
                    self.falhou()
                case .success(let linhas) where linhas.isEmpty:
                    self.avisar(NotchNotification(appName: "Knobler", title: "Nenhum texto encontrado", body: ""))
                case .success(let linhas):
                    let texto = linhas.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(texto, forType: .string)
                    self.avisar(NotchNotification(appName: "Knobler", title: "Texto copiado",
                                                  body: TextoDaTela.resumo(texto)))
                }
            }
        }
    }

    private func falhou() {
        ocupado = false
        avisar(NotchNotification(appName: "Knobler", title: "Não consegui ler a tela", body: ""))
    }

    /// Uma foto por monitor, na resolução nativa, sem o cursor.
    @MainActor
    private static func fotografar() async throws -> [(tela: NSScreen, foto: CGImage)] {
        let conteudo = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var fotos: [(tela: NSScreen, foto: CGImage)] = []
        for tela in NSScreen.screens {
            let id = tela.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = conteudo.displays.first(where: { $0.displayID == id }) else { continue }
            let filtro = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(tela.frame.width * tela.backingScaleFactor)
            config.height = Int(tela.frame.height * tela.backingScaleFactor)
            config.showsCursor = false
            let foto = try await SCScreenshotManager.captureImage(contentFilter: filtro, configuration: config)
            fotos.append((tela, foto))
        }
        return fotos
    }
}
