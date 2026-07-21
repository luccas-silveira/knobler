//
//  Peer.swift
//  Knobler
//
//  Modelos das mensagens LAN. `Peer` referencia um endpoint Bonjour vivo;
//  `PeerMessage`/`PeerProfile` são dados puros (persistência + fio).
//

import Foundation
import Network

/// Uma pessoa descoberta na rede agora (some quando o Bonjour a remove).
struct Peer: Identifiable, Equatable {
    let id: String            // UUID vindo do TXT record
    var name: String          // nome de exibição (TXT record)
    var endpoint: NWEndpoint  // pra abrir conexão
    var online: Bool = true

    static func == (a: Peer, b: Peer) -> Bool {
        a.id == b.id && a.name == b.name && a.online == b.online
    }
}

/// Mensagem trocada. `peerID` é sempre o OUTRO lado (remetente se incoming,
/// destinatário se outgoing). `delivered` só importa em outgoing.
struct PeerMessage: Identifiable, Codable, Equatable {
    let id: String
    let peerID: String
    let incoming: Bool
    var text: String
    var allowReply: Bool
    let at: Date
    var delivered: Bool = true
}

/// Perfil publicado por um peer (resposta ao pedido `profile`).
struct PeerProfile: Codable, Equatable {
    let id: String
    let name: String
    var avatarJPEG: Data?
}
