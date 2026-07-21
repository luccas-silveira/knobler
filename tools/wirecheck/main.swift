//
//  main.swift — self-check do protocolo de fio. NÃO faz parte do alvo.
//  Rodar: xcrun swiftc Knobler/Wire.swift tools/wirecheck/main.swift -o /tmp/wirecheck && /tmp/wirecheck
//

import Foundation

// round-trip de mensagem
let msg = Packet.message(id: "m1", from: "u1", fromName: "Luccas", text: "olá", reply: true)
let framed = try Frame.encode(msg)
assert(framed.count > 4, "moldura tem prefixo + corpo")
let n = framed.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
assert(Int(n) == framed.count - 4, "prefixo bate com o tamanho do corpo")
assert(try! Frame.decode(framed.suffix(from: 4)) == msg, "mensagem sobrevive ao round-trip")

// mensagem com reply:false também sobrevive (o outro valor do bool)
let msgNoReply = Packet.message(id: "m2", from: "u2", fromName: "Ana", text: "oi", reply: false)
assert(try! Frame.decode(Frame.encode(msgNoReply).suffix(from: 4)) == msgNoReply,
       "reply:false sobrevive ao round-trip")

// round-trip de perfil com avatar (Data → base64 → Data)
let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
let prof = Packet.profileResponse(id: "u1", name: "Luccas", avatar: jpeg)
assert(try! Frame.decode(Frame.encode(prof).suffix(from: 4)) == prof, "perfil+avatar sobrevive")

// perfil SEM avatar (nil) — exercita o ramo encodeIfPresent/decodeIfPresent
let profNil = Packet.profileResponse(id: "u3", name: "Bia", avatar: nil)
assert(try! Frame.decode(Frame.encode(profNil).suffix(from: 4)) == profNil, "perfil sem avatar sobrevive")

// profileRequest e ack
assert(try! Frame.decode(Frame.encode(.profileRequest).suffix(from: 4)) == .profileRequest)
assert(try! Frame.decode(Frame.encode(.ack).suffix(from: 4)) == .ack)

// tag "t" desconhecida → decode lança (não trava o processo silenciosamente)
let bogus = Data(#"{"t":"xpto"}"#.utf8)
do { _ = try Frame.decode(bogus); assert(false, "tag desconhecida deveria lançar") }
catch is DecodingError { /* esperado */ }

// teto do frame
let huge = Packet.message(id: "x", from: "x", fromName: "x",
                          text: String(repeating: "a", count: Frame.maxSize + 1), reply: false)
do { _ = try Frame.encode(huge); assert(false, "deveria estourar o teto") }
catch WireError.tooBig { /* esperado */ }

// mensagem com anexo sobrevive ao round-trip (Data → base64 → Data)
let gif = Data(Array("GIF89a".utf8) + [0, 1, 2])
let withMedia = Packet.message(id: "m3", from: "u1", fromName: "Luccas", text: "olha",
                               reply: true, media: gif, mime: "image/gif")
assert(try! Frame.decode(Frame.encode(withMedia).suffix(from: 4)) == withMedia,
       "mensagem com anexo sobrevive")

// mensagem sem anexo continua decodificando (campos ausentes → nil)
assert(try! Frame.decode(Data(#"{"t":"msg","id":"m4","from":"u","fromName":"n","text":"oi","reply":false}"#.utf8))
       == .message(id: "m4", from: "u", fromName: "n", text: "oi", reply: false),
       "msg antigo (sem campos de mídia) ainda decodifica")

// validação do anexo: tipo detectado pelos bytes e coerente com o mime
assert(MediaKind.validate(gif, mime: "image/gif") == .gif, "gif válido passa")
assert(MediaKind.validate(gif, mime: "image/png") == nil, "mime mentindo é rejeitado")
assert(MediaKind.validate(Data([0xFF, 0xD8, 0xFF, 0]), mime: "image/jpeg") == .jpeg, "jpeg passa")
assert(MediaKind.validate(Data("<script>".utf8), mime: "image/png") == nil, "não-imagem é rejeitada")
assert(MediaKind.validate(Data(repeating: 0x47, count: Frame.maxMedia + 1), mime: "image/gif") == nil,
       "anexo acima do teto é rejeitado")
assert(MediaKind.gif.ext == "gif" && MediaKind.jpeg.ext == "jpg", "extensão do arquivo")

print("wire ok")
