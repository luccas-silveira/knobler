//
//  LinkPreviewView.swift
//  Knobler
//
//  A seção Link do card: a página inteira, sem barra de navegador. O cabeçalho
//  tem só o que não dá pra fazer dentro da página — voltar, abrir no navegador
//  de verdade e fechar.
//

import SwiftUI
import WebKit

struct LinkPreviewView: View {
    @ObservedObject var preview: LinkPreview

    var body: some View {
        VStack(spacing: 0) {
            cabecalho
            ZStack(alignment: .top) {
                WebViewRepresentable(webView: preview.webView)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    // o zoom faz o site enxergar uma janela de desktop em vez
                    // de um celular. A largura é constante (o card do link tem
                    // tamanho fixo), então não precisa de GeometryReader — que
                    // além disso mediria depois do primeiro layout, com a página
                    // já desenhada no breakpoint errado.
                    .onAppear {
                        preview.ajustarZoom(paraLargura: NotchView.linkContentWidth)
                    }
                if preview.carregando {
                    ProgressView(value: preview.progresso)
                        .progressViewStyle(.linear)
                        .frame(height: 2)
                        .padding(.horizontal, 2)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var cabecalho: some View {
        HStack(spacing: 8) {
            Button(action: preview.voltar) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(!preview.podeVoltar)
            .opacity(preview.podeVoltar ? 0.9 : 0.3)

            Text(preview.titulo)
                .font(.caption.weight(.medium))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)

            Button(action: preview.abrirFora) {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.plain)
            .help("Abrir no navegador padrão")

            Button(action: preview.fechar) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.55))
        }
        .font(.system(size: 12))
        .padding(.horizontal, 2)
        .padding(.bottom, 6)
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
