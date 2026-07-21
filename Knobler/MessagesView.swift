//
//  MessagesView.swift
//  Knobler
//
//  Aba de Mensagens LAN no notch: lista de online → conversa → escrever.
//

import SwiftUI

struct MessagesView: View {
    @ObservedObject var vm: NotchViewModel
    @EnvironmentObject var lan: LANMessaging
    @EnvironmentObject var store: MessageStore

    // Seleção mora no VM (vm.selectedThreadPeerID) pra que openThread (clique no
    // card de entrada) consiga abrir a conversa certa. Aqui é só leitura/escrita.
    @State private var draft = ""
    @State private var allowReply = true

    var body: some View {
        Group {
            if lan.permissionDenied {
                info("Libere a Rede Local em Ajustes › Privacidade › Rede Local.")
            } else if let id = vm.selectedThreadPeerID {
                conversation(peerID: id)
            } else {
                peerList
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Lista de online

    private var peerList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if lan.peers.isEmpty {
                info("Ninguém online na rede.")
            } else {
                ForEach(lan.peers) { peer in
                    Button { open(peer.id) } label: { peerRow(peer) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func peerRow(_ peer: Peer) -> some View {
        HStack(spacing: 8) {
            avatar(peerID: peer.id, name: peer.name).frame(width: 28, height: 28)
            Text(peer.name).font(.footnote.weight(.medium))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
    }

    // MARK: Conversa

    private func conversation(peerID: String) -> some View {
        let peer = lan.peer(withID: peerID)
        let name = peer?.name ?? store.name(for: peerID) ?? "?"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { vm.selectedThreadPeerID = nil } label: {
                    Image(systemName: "chevron.left")
                }.buttonStyle(.plain)
                avatar(peerID: peerID, name: name).frame(width: 22, height: 22)
                Text(name).font(.footnote.weight(.semibold))
                Spacer()
                if peer == nil {
                    Text("offline").font(.caption2).foregroundStyle(.white.opacity(0.4))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.messages(for: peerID)) { bubble($0) }
                }
            }
            .frame(maxHeight: 200)
            composer(peer: peer)
        }
    }

    private func bubble(_ m: PeerMessage) -> some View {
        let media = m.mediaFile.flatMap { store.mediaURL($0) }
        // com imagem o balão toma a largura toda (sem recuo do lado oposto)
        return HStack {
            if !m.incoming, media == nil { Spacer(minLength: 24) }
            VStack(alignment: m.incoming ? .leading : .trailing, spacing: 4) {
                if let url = media {
                    MediaThumb(url: url)
                        .aspectRatio(MessageMedia.aspect(url), contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if !m.text.isEmpty { Text(m.text).font(.footnote) }
                if !m.incoming, !m.delivered {
                    Text("não entregue").font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(m.incoming ? 0.10 : 0.22)))
            if m.incoming, media == nil { Spacer(minLength: 24) }
        }
    }

    private func composer(peer: Peer?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if vm.pendingAttachment != nil || vm.attachmentFailed { attachmentBar }
            HStack(spacing: 6) {
                Toggle("", isOn: $allowReply).labelsHidden().toggleStyle(.switch).scaleEffect(0.7)
                    .help("Permite resposta")
                Button(action: pickAttachment) { Image(systemName: "photo") }
                    .buttonStyle(.plain).help("Anexar foto ou GIF")
                TextField("Mensagem…", text: $draft)
                    .textFieldStyle(.plain).font(.footnote)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
                    .onSubmit { sendDraft(to: peer) }
                Button { sendDraft(to: peer) } label: { Image(systemName: "paperplane.fill") }
                    .buttonStyle(.plain)
                    .disabled(peer == nil || (vm.pendingAttachment == nil &&
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
    }

    private var attachmentBar: some View {
        HStack(spacing: 6) {
            if let a = vm.pendingAttachment {
                Image(systemName: a.kind == .gif ? "photo.stack" : "photo")
                Text("\(a.kind.ext.uppercased()) · \(a.data.count / 1024) KB").font(.caption2)
                Button { vm.pendingAttachment = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            } else {
                Text("Não deu pra anexar (formato ou tamanho).").font(.caption2)
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.7))
    }

    // MARK: Ações

    private func open(_ peerID: String) {
        vm.selectedThreadPeerID = peerID
        if let peer = lan.peer(withID: peerID) {
            store.rememberName(peer.name, for: peerID)
            // ponytail: só busca a foto se ainda não temos cache (evita ida à rede a cada toque)
            if store.avatar(for: peerID) == nil {
                lan.fetchProfile(from: peer) { profile in
                    if let jpeg = profile?.avatarJPEG { store.cacheAvatar(jpeg, for: peerID) }
                }
            }
        }
    }

    private func pickAttachment() {
        MessageMedia.pick { picked in
            vm.pendingAttachment = picked.map { .init(data: $0.0, kind: $0.1) }
            vm.attachmentFailed = picked == nil
            // o painel de arquivos tira o mouse do notch: reabre na conversa
            vm.tab = .messages
            vm.setExpandedDirect(true)
        }
    }

    private func sendDraft(to peer: Peer?) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let media = vm.pendingAttachment
        guard let peer, !text.isEmpty || media != nil else { return }
        draft = ""
        vm.pendingAttachment = nil
        vm.attachmentFailed = false
        let reply = allowReply
        // grava a cópia local antes de enviar: o balão mostra o que saiu daqui
        let file = media.flatMap { store.saveMedia($0.data, ext: $0.kind.ext) }
        lan.send(text, to: peer, allowReply: reply, media: media.map { ($0.data, $0.kind) }) { ok in
            store.append(PeerMessage(id: UUID().uuidString, peerID: peer.id, incoming: false,
                                     text: text, allowReply: reply, at: Date(), delivered: ok,
                                     mediaFile: file))
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func avatar(peerID: String, name: String) -> some View {
        if let img = store.avatar(for: peerID) {
            Image(nsImage: img).resizable().scaledToFill().clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(.gray.opacity(0.35))
                Text(String(name.prefix(1)).uppercased())
                    .font(.caption2.weight(.semibold))
            }
        }
    }

    private func info(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
    }
}
