//
//  Wire.swift
//  Knobler
//
//  Protocolo de fio das mensagens LAN: pacote JSON tagueado por "t",
//  emoldurado com prefixo de 4 bytes (tamanho, big-endian) + corpo.
//  Só Foundation — sem Network — pra ser testável isolado (tools/wirecheck.swift).
//

import Foundation

enum Packet: Codable, Equatable {
    case profileRequest
    case profileResponse(id: String, name: String, avatar: Data?)
    /// `media`/`mime` presentes = foto ou GIF anexado (texto pode vir vazio).
    case message(id: String, from: String, fromName: String, text: String, reply: Bool,
                 media: Data? = nil, mime: String? = nil)
    case ack

    private enum Key: String, CodingKey {
        case t, id, name, avatar, from, fromName, text, reply, media, mime
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .profileRequest:
            try c.encode("profile", forKey: .t)
        case let .profileResponse(id, name, avatar):
            try c.encode("profileResp", forKey: .t)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(avatar, forKey: .avatar) // Data → base64 no JSON
        case let .message(id, from, fromName, text, reply, media, mime):
            try c.encode("msg", forKey: .t)
            try c.encode(id, forKey: .id)
            try c.encode(from, forKey: .from)
            try c.encode(fromName, forKey: .fromName)
            try c.encode(text, forKey: .text)
            try c.encode(reply, forKey: .reply)
            try c.encodeIfPresent(media, forKey: .media) // Data → base64 no JSON
            try c.encodeIfPresent(mime, forKey: .mime)
        case .ack:
            try c.encode("ack", forKey: .t)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .t) {
        case "profile":
            self = .profileRequest
        case "profileResp":
            self = .profileResponse(
                id: try c.decode(String.self, forKey: .id),
                name: try c.decode(String.self, forKey: .name),
                avatar: try c.decodeIfPresent(Data.self, forKey: .avatar))
        case "msg":
            self = .message(
                id: try c.decode(String.self, forKey: .id),
                from: try c.decode(String.self, forKey: .from),
                fromName: try c.decode(String.self, forKey: .fromName),
                text: try c.decode(String.self, forKey: .text),
                reply: try c.decode(Bool.self, forKey: .reply),
                media: try c.decodeIfPresent(Data.self, forKey: .media),
                mime: try c.decodeIfPresent(String.self, forKey: .mime))
        case "ack":
            self = .ack
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .t, in: c, debugDescription: "tipo de pacote desconhecido")
        }
    }
}

enum WireError: Error { case tooBig }

enum Frame {
    /// Teto do corpo JSON. Anexo cru cabe em `maxMedia`; o base64 infla ~33%.
    static let maxSize = 12 * 1024 * 1024
    /// Teto do anexo (foto/GIF) antes de virar base64.
    static let maxMedia = 6 * 1024 * 1024

    /// 4 bytes de tamanho (big-endian) + corpo JSON.
    static func encode(_ packet: Packet) throws -> Data {
        let body = try JSONEncoder().encode(packet)
        guard body.count <= maxSize else { throw WireError.tooBig }
        var len = UInt32(body.count).bigEndian
        var out = Data(bytes: &len, count: 4)
        out.append(body)
        return out
    }

    static func decode(_ body: Data) throws -> Packet {
        try JSONDecoder().decode(Packet.self, from: body)
    }
}

/// Anexo de imagem aceito no fio. Só três tipos, e o `mime` declarado tem que
/// bater com os bytes mágicos — remetente não escolhe a extensão do arquivo
/// que vamos gravar nem nos empurra outro formato disfarçado.
enum MediaKind: String {
    case jpeg, png, gif

    var mime: String { "image/\(rawValue)" }
    var ext: String { rawValue == "jpeg" ? "jpg" : rawValue }

    /// Identifica pelos bytes; `nil` = não é imagem suportada.
    static func detect(_ data: Data) -> MediaKind? {
        let head = [UInt8](data.prefix(8))
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        if head.starts(with: Array("GIF8".utf8)) { return .gif }
        return nil
    }

    /// Valida um anexo recebido: tamanho, bytes mágicos e coerência com o `mime`.
    static func validate(_ data: Data, mime: String?) -> MediaKind? {
        guard data.count <= Frame.maxMedia, let kind = detect(data), kind.mime == mime else { return nil }
        return kind
    }
}
