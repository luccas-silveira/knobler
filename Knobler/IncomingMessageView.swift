//
//  IncomingMessageView.swift
//  Knobler
//
//  Card que desce do notch quando chega uma mensagem LAN: foto + nome +
//  texto e, se permitido, resposta rápida. Clicar abre a conversa na aba.
//

import SwiftUI

struct IncomingMessageView: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject var store: MessageStore
    let incoming: NotchViewModel.IncomingMessage

    @State private var reply = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { vm.openThread(peerID: incoming.peerID) } label: { header }
                .buttonStyle(.plain)
            if incoming.allowReply { replyField }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 8) {
            avatar.frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(incoming.name).font(.footnote.weight(.semibold))
                Text(incoming.text).font(.caption).foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button { vm.dismissIncoming() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
            }.buttonStyle(.plain)
        }
    }

    private var replyField: some View {
        HStack(spacing: 6) {
            TextField("Responder…", text: $reply)
                .textFieldStyle(.plain).font(.footnote)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.10)))
                .onSubmit(send)
            Button(action: send) { Image(systemName: "paperplane.fill") }
                .buttonStyle(.plain)
                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func send() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        reply = ""
        vm.onSendReply?(incoming.peerID, text)
        vm.dismissIncoming()
    }

    @ViewBuilder
    private var avatar: some View {
        if let img = store.avatar(for: incoming.peerID) {
            Image(nsImage: img).resizable().scaledToFill().clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(.gray.opacity(0.35))
                Text(String(incoming.name.prefix(1)).uppercased())
                    .font(.footnote.weight(.semibold))
            }
        }
    }
}
