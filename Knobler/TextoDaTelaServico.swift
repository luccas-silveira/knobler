//
//  TextoDaTelaServico.swift
//  Knobler
//
//  O coordenador do Texto da tela: permissão, seleção, OCR, clipboard e aviso
//  no notch. A seleção é a do próprio macOS (`screencapture -i`, a mesma do
//  ⌘⇧4): cursor em mira, sem congelar nem escurecer a tela, multi-monitor e
//  Esc de graça. É o PluginServico da peça — nascer registra o ⌃⇧T, parar()
//  o remove.
//

import AppKit
import Carbon.HIToolbox
import os

private let log = Logger(subsystem: "com.zoi.knobler", category: "TextoDaTela")

final class TextoDaTelaServico: PluginServico {
    static let atalho = KeyboardShortcuts.Name(
        "textoDaTela",
        default: .init(carbonKeyCode: kVK_ANSI_T, carbonModifiers: controlKey | shiftKey))

    private let avisar: (NotchNotification) -> Void
    private var selecao: Process?
    /// Peça desinstalada no meio de uma seleção: não lê nem avisa.
    private var parado = false
    /// Apaga o ícone da faixa do notch quando a peça desliga.
    var aoParar: (() -> Void)?

    init(avisar: @escaping (NotchNotification) -> Void) {
        self.avisar = avisar
        KeyboardShortcuts.enable(Self.atalho)
        KeyboardShortcuts.onKeyDown(for: Self.atalho) { [weak self] in self?.acionar() }
    }

    func parar() {
        parado = true
        KeyboardShortcuts.removeHandlers(for: Self.atalho)
        selecao?.terminate()
        aoParar?()
    }

    /// Atalho, ícone do notch ou menu. Segundo toque com a seleção aberta é ignorado.
    func acionar() {
        guard selecao == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            // Primeiro pedido mostra o balão; depois dele o macOS não pergunta
            // de novo (e o status não distingue negada de nunca pedida), então
            // os acionamentos seguintes abrem os Ajustes no painel certo.
            if UserDefaults.standard.bool(forKey: Permission.chavePediuGravacao) {
                NSWorkspace.shared.open(Permission.gravacaoTela.settingsURL)
            } else {
                Permission.gravacaoTela.request {}
            }
            return
        }
        let arquivo = FileManager.default.temporaryDirectory
            .appendingPathComponent("knobler-texto-\(UUID().uuidString).png")
        let processo = Process()
        processo.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i seleção interativa, -s só retângulo (sem modo janela), -x sem som
        processo.arguments = ["-i", "-s", "-x", arquivo.path]
        processo.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.selecionou(arquivo) }
        }
        do {
            try processo.run()
            selecao = processo
        } catch {
            log.error("screencapture não abriu: \(error.localizedDescription, privacy: .public)")
            falhou()
        }
    }

    /// Esc ou clique sem arrasto: o screencapture sai sem gravar arquivo — cancelamento calado.
    private func selecionou(_ arquivo: URL) {
        selecao = nil
        defer { try? FileManager.default.removeItem(at: arquivo) }
        guard !parado, FileManager.default.fileExists(atPath: arquivo.path) else { return }
        guard let fonte = CGImageSourceCreateWithURL(arquivo as CFURL, nil),
              let imagem = CGImageSourceCreateImageAtIndex(fonte, 0, nil) else { return falhou() }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let resultado = Result { try TextoDaTela.linhas(em: imagem) }
            DispatchQueue.main.async {
                guard let self, !self.parado else { return }
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
        avisar(NotchNotification(appName: "Knobler", title: "Não consegui ler a tela", body: ""))
    }
}
