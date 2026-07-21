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

// round-trip de perfil com avatar (Data → base64 → Data)
let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
let prof = Packet.profileResponse(id: "u1", name: "Luccas", avatar: jpeg)
assert(try! Frame.decode(Frame.encode(prof).suffix(from: 4)) == prof, "perfil+avatar sobrevive")

// profileRequest e ack
assert(try! Frame.decode(Frame.encode(.profileRequest).suffix(from: 4)) == .profileRequest)
assert(try! Frame.decode(Frame.encode(.ack).suffix(from: 4)) == .ack)

// teto de 64 KB
let huge = Packet.message(id: "x", from: "x", fromName: "x",
                          text: String(repeating: "a", count: 70_000), reply: false)
do { _ = try Frame.encode(huge); assert(false, "deveria estourar o teto") }
catch WireError.tooBig { /* esperado */ }

print("wire ok")
