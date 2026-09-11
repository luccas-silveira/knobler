// A moldura tem identidade estável; transições de conteúdo não participam da sua medida.
import SwiftUI

struct NotchShell<Content: View>: View {
    let presentation: NotchPresentation
    let reduceMotion: Bool
    @ViewBuilder var content: () -> Content

    private var motion: Animation {
        presentation.mode == .closed
            ? .spring(response: 0.30, dampingFraction: 0.95)
            : .spring(response: 0.42, dampingFraction: 0.76)
    }

    var body: some View {
        let shape = NotchShape(topCornerRadius: presentation.compact ? 6 : 14,
                               bottomCornerRadius: presentation.compact ? 12 : 30)
        // Overlay não aumenta a moldura para acomodar uma view que está saindo.
        shape.fill(.black)
            .frame(width: presentation.size.width, height: presentation.size.height)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) { content() }
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : motion, value: presentation)
            }
            .clipShape(shape)
            .compositingGroup()
            .shadow(color: .black.opacity(presentation.mode == .closed ? 0 : 0.35), radius: 12, y: 5)
            .animation(reduceMotion ? nil : motion, value: presentation)
    }
}
