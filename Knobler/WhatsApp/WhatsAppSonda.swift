import Combine
import Foundation
import os

// Sondagem de identificação da ponte do WhatsApp: a fonte única de "a ponte se
// identificou" que a vitrine e a lista de atalhos leem. Aqui só se decide SE
// sonda; o `GET /v1/ponte`, a releitura no 401 e a leitura da tabela ficam em
// `WACliente.identificar()`. Mac sem ponte não abre conexão nenhuma
// (docs/whatsapp-ponte.md:65-66).

private let log = Logger(subsystem: "com.zoi.knobler", category: "whatsapp")

@MainActor
final class WhatsAppSonda: ObservableObject {
    static let shared = WhatsAppSonda()

    /// `nil` = nunca sondou.
    @Published private(set) var conclusao: WAConclusaoDaSonda?

    var identificada: Bool {
        if case .presente = conclusao { return true }
        return false
    }

    private let existeChave: () -> Bool
    private let fabricaDeCliente: () -> WACliente
    private var cliente: WACliente?

    /// Hora da última sondagem que saiu pela rede (não da última chamada).
    private var ultimaSondagem: Date?
    private static let janela: TimeInterval = 30

    init(existeChave: @escaping () -> Bool = { WAChaveDaPonte.existe() },
         fabricaDeCliente: @escaping () -> WACliente = { WACliente() }) {
        self.existeChave = existeChave
        self.fabricaDeCliente = fabricaDeCliente
    }

    /// Sonda sempre (respeitando só a regra do arquivo da chave).
    func sondar() async {
        await sondar(agora: Date())
    }

    /// Sonda só se a última sondagem tem mais de 30 s. Sem arquivo de chave,
    /// conclui `.semChave` na hora: olhar o arquivo não custa conexão.
    func sondarSeVelha(agora: Date = Date()) async {
        if existeChave(), let ultimaSondagem, agora.timeIntervalSince(ultimaSondagem) < Self.janela {
            return
        }
        await sondar(agora: agora)
    }

    private func sondar(agora: Date) async {
        guard existeChave() else {
            atualizar(.semChave)
            return
        }
        let cliente = self.cliente ?? fabricaDeCliente()
        self.cliente = cliente
        ultimaSondagem = agora
        atualizar(await cliente.identificar())
    }

    private func atualizar(_ nova: WAConclusaoDaSonda) {
        guard nova != conclusao else { return }
        log.info("ponte do WhatsApp: \(String(describing: nova), privacy: .public)")
        conclusao = nova
    }
}
