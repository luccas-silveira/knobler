import Combine
import Foundation
import os

// Estado do WhatsApp como singleton: liga o cliente HTTP, o canal ao vivo e o
// estado puro (`WAEstado`). Nasce inerte — nada de rede no `init` — e só
// `start()` cria o canal; o canal real sem arquivo de chave nunca abre socket,
// então Mac sem ponte não abre conexão nenhuma. Rotas em
// docs/whatsapp-ponte.md:449-722, `ref` em :272-275, `ressincronize` em
// :773-775, `sincronizacao` em :932-939.
//
// Leitura: o Knobler nunca marca lida sozinho. `POST /v1/lida` sai só pelo
// botão (`marcarLida`) e depois de um envio que deu certo.

private let log = Logger(subsystem: "com.zoi.knobler", category: "whatsapp")

enum WAConexao: Equatable {
    case inerte, semChave, foraDoAr, chaveNaoConfere, incompativel(Int), carregando, pronta
}

@MainActor
final class WhatsAppStore: ObservableObject {
    static let shared = WhatsAppStore()

    @Published private(set) var estado = WAEstado()
    @Published private(set) var conexao: WAConexao = .inerte
    @Published private(set) var canalAberto = false
    /// Conversa cujo campo de texto (seção ou card) tem o foco agora. Quem liga
    /// e desliga são as views, quando o campo ganha e perde foco. Um só: o foco
    /// de teclado está numa tela de cada vez, e o ditado global escreve aqui.
    @Published var campoEmUso: WAChave?

    /// Canal aberto **e** alguma conta conectada.
    var ponteConectada: Bool {
        canalAberto && estado.contas.contains { $0.estado == .conectada }
    }

    /// Quem grava a nota de voz: o app entrega o gravador do ditado
    /// (`WhatsAppPeca.ligar`); sem fonte, gravar diz "Sem acesso ao microfone".
    var fonteDeMicrofone: WAFonteDeMicrofone?
    /// Onde o Ogg da nota de voz espera a ponte ler; o arquivo some depois da resposta.
    var pastaDeEnvio: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.zoi.knobler/envio", isDirectory: true)
    @Published private(set) var gravacao: WAGravacaoEmCurso?
    @Published private(set) var erroDeGravacao: String?
    /// Por que o último anexo não saiu (acima do limite, cópia que falhou).
    @Published private(set) var erroDeAnexo: String?
    /// Faixa "Respondendo a …" por conta+conversa: sobrevive a fechar a
    /// conversa e o notch; some ao enviar ou no x/Esc.
    @Published private(set) var citacoes: [WAChave: WACitacao] = [:]
    /// Arquivo escolhido no clipe e ainda não enviado, por conta+conversa.
    @Published private(set) var anexos: [WAChave: URL] = [:]

    /// Cache da mídia recebida, com o mesmo cliente da ponte.
    private(set) var midia: WAMidiaCache

    /// Mensagem recebida (não minha), uma vez por mensagem.
    var aoChegarMensagem: ((WAMensagem, WAConversa, WAConta?) -> Void)?

    private let cliente: WACliente
    private let fabricaDeCanal: (WACliente) -> WACanalProtocolo
    /// Relógio do store (testes injetam um que avança à mão).
    private let agora: () -> Date
    /// Grupos lidos de `GET /v1/grupo`, com a hora da leitura: valem 10 min,
    /// como na ponte (docs/whatsapp-ponte.md:558-561).
    private var grupos: [WAChave: (grupo: WAGrupo, lido: Date)] = [:]
    private static let validadeDoGrupo: TimeInterval = 10 * 60
    private var canal: WACanalProtocolo?

    /// Sobe a cada `stop`/`_zerar`: resposta de pedido antigo não mexe no estado.
    private var epoca: UInt64 = 0
    /// Sobe a cada carga (abertura do canal ou `ressincronize`): só a última termina.
    private var cargaAtual: UInt64 = 0
    /// A próxima abertura do canal relê tudo (primeira vez ou depois de
    /// `ressincronize`/`stop`); senão relê só contas e pareamento.
    private var pendenteCompleta = true
    /// Conversas abertas, contadas por tela (duas telas podem abrir a mesma).
    private var abertas: [WAChave: Int] = [:]
    /// Páginas de mensagens em voo: duas telas abrindo juntas pedem uma vez só.
    private var paginasEmVoo: Set<WAChave> = []
    /// Cursor `antes` da última página de `/v1/conversas` lida por conta;
    /// ausente = a lista daquela conta chegou ao fim.
    private var cursorDeConversas: [String: String] = [:]
    private var listasEmVoo: Set<String> = []
    private var contadorDeRef = 0
    /// `POST /v1/pareamento` em voo: duas telas pedindo juntas viram um pedido só.
    private var pareamentoEmVoo = false
    /// A fonte que está gravando e os níveis que ela já entregou (viram a onda).
    private var fonteEmUso: WAFonteDeMicrofone?
    private var niveisDaGravacao: [Float] = []
    /// Sobe a cada gravação: nível atrasado de uma gravação encerrada não volta.
    private var sessaoDeGravacao: UInt64 = 0

    init(cliente: WACliente? = nil, fabricaDeCanal: ((WACliente) -> WACanalProtocolo)? = nil,
         agora: @escaping () -> Date = Date.init) {
        let cliente = cliente ?? WACliente()
        self.cliente = cliente
        self.agora = agora
        self.midia = WAMidiaCache(cliente: cliente)
        self.fabricaDeCanal = fabricaDeCanal ?? { cliente in
            WACanal(porta: WAConfig.porta(), chave: { cliente.chave(relendo: $0) })
        }
    }

    // MARK: - Ciclo de vida

    func start() {
        Task { await iniciar() }
    }

    func iniciar() async {
        guard canal == nil else { return }
        let c = fabricaDeCanal(cliente)
        let ep = epoca
        c.aoMudarEstado = { [weak self] e in Self.naMain { self?.canalMudou(e, epoca: ep) } }
        c.aoEvento = { [weak self] e in Self.naMain { self?.receber(e, epoca: ep) } }
        c.aoRessincronizar = { [weak self] _, _ in Self.naMain { self?.ressincronizar(epoca: ep) } }
        canal = c
        c.iniciar()
    }

    func stop() {
        epoca &+= 1
        cancelarGravacao()
        if let c = canal {
            // solta os callbacks antes: nada que o canal entregue depois chega aqui
            c.aoMudarEstado = nil
            c.aoEvento = nil
            c.aoRessincronizar = nil
            c.parar()
        }
        canal = nil
        canalAberto = false
        conexao = .inerte
        pendenteCompleta = true
        paginasEmVoo = []
        listasEmVoo = []
        pareamentoEmVoo = false
    }

    /// O canal entrega na main (delegate e relógio na fila main). Se um dia
    /// vier de outra fila, o salto preserva a ordem em vez de abortar.
    private nonisolated static func naMain(_ bloco: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(bloco)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(bloco) }
        }
    }

    // MARK: - Canal

    private func canalMudou(_ e: WAEstadoDoCanal, epoca ep: UInt64) {
        guard ep == epoca else { return }
        canalAberto = e == .aberto
        switch e {
        case .aberto:
            let completa = pendenteCompleta
            if completa { conexao = .carregando }
            carregar(completa: completa, esvaziando: false)
        case .semChave: conexao = .semChave
        case .foraDoAr: conexao = .foraDoAr
        case .chaveNaoConfere: conexao = .chaveNaoConfere
        case .incompativel(let n): conexao = .incompativel(n)
        case .parado: conexao = .inerte
        case .conectando: break
        }
    }

    private func receber(_ e: WAEvento, epoca ep: UInt64) {
        guard ep == epoca else { return }
        switch e {
        case let .numerado(_, conta, _, dados):
            let efeito = estado.aplicar(dados, conta: conta)
            if case let .midia(conversa, alvo, ok) = dados {
                midia.recuperou(chave: WAChave(conta: conta, jid: conversa), alvo: alvo, ok: ok)
            }
            if case .sincronizacao = dados {
                Task { await recarregarConversas(conta: conta) }
            }
            if case let .mensagemNova(m, cv) = efeito, !m.deMim {
                aoChegarMensagem?(m, cv, estado.contas.first { $0.conta == conta })
            }
        case let .conta(c):
            estado.aplicar(conta: c)
        case let .pareamento(p):
            estado.pareamento = p
            if p.estado == .sucesso { Task { await recarregarContas() } }
        case .ola, .ressincronize, .desconhecido:
            break
        }
    }

    /// Jornal novo ou `desde` fora da retenção: descarta as conversas e relê
    /// contas, conversas e as conversas abertas (docs/whatsapp-ponte.md:773-775).
    private func ressincronizar(epoca ep: UInt64) {
        guard ep == epoca else { return }
        estado.esvaziarConversas()
        cursorDeConversas = [:]
        pendenteCompleta = true
        carregar(completa: true, esvaziando: true)
    }

    // MARK: - Carga

    private func carregar(completa: Bool, esvaziando: Bool) {
        cargaAtual &+= 1
        let carga = cargaAtual
        let ep = epoca
        Task { await executarCarga(completa: completa, esvaziando: esvaziando, carga: carga, epoca: ep) }
    }

    /// Completa: contas, depois conversas de cada conta (e pareamento na
    /// abertura, e as conversas abertas no `ressincronize`). Reabertura depois
    /// de queda: só contas e pareamento — os eventos perdidos vêm pelo `desde`.
    private func executarCarga(completa: Bool, esvaziando: Bool, carga: UInt64, epoca ep: UInt64) async {
        func vigente() -> Bool { ep == epoca && carga == cargaAtual }
        do {
            let contas = try await cliente.contas()
            guard vigente() else { return }
            estado.substituirContas(contas)

            async let pareamento = esvaziando ? nil : lerPareamento()
            if completa {
                for (conta, resultado) in await lerConversas(contas.map(\.conta)) {
                    guard vigente() else { return }
                    aplicarConversas(conta: conta, resultado)
                }
            }
            let p = await pareamento
            guard vigente() else { return }
            if !esvaziando { estado.pareamento = p }
            if esvaziando {
                for k in abertas.keys { await lerPagina(k) }
                guard vigente() else { return }
            }
            if completa { pendenteCompleta = false }
            if canalAberto { conexao = .pronta }
        } catch {
            guard vigente() else { return }
            log.error("WhatsApp: carga falhou — \(String(describing: error), privacy: .public)")
            conexao = Self.conexao(do: error)
        }
    }

    private nonisolated func lerPareamento() async -> WAPareamento? {
        do { return try await cliente.pareamentoAtual() } catch {
            log.notice("WhatsApp: pareamento não lido — \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private nonisolated func lerConversas(_ contas: [String]) async -> [(String, Result<WARespostaConversas, Error>)] {
        await withTaskGroup(of: (String, Result<WARespostaConversas, Error>).self) { grupo in
            for conta in contas {
                grupo.addTask {
                    do { return (conta, .success(try await self.cliente.conversas(conta: conta))) } catch {
                        return (conta, .failure(error))
                    }
                }
            }
            var saida: [(String, Result<WARespostaConversas, Error>)] = []
            for await r in grupo { saida.append(r) }
            return saida
        }
    }

    /// Primeira página: troca a lista da conta e recomeça o cursor dela.
    private func aplicarConversas(conta: String, _ r: Result<WARespostaConversas, Error>) {
        switch r {
        case .success(let pagina):
            estado.substituirConversas(conta: conta, pagina.conversas)
            cursorDeConversas[conta] = pagina.antes
        case .failure(let erro):
            // ponytail: uma conta que falha não segura a carga das outras
            log.error("WhatsApp: conversas da conta não lidas — \(String(describing: erro), privacy: .public)")
        }
    }

    /// Evento `sincronizacao`: um lote do histórico entrou; relê as conversas da conta.
    private func recarregarConversas(conta: String) async {
        let ep = epoca
        let r = await lerConversas([conta])
        guard ep == epoca, let lida = r.first else { return }
        aplicarConversas(conta: lida.0, lida.1)
    }

    /// Página seguinte da lista (a última linha apareceu): pede com o cursor
    /// guardado da conta e acrescenta sem repetir `jid`. Sem cursor, a lista
    /// já chegou ao fim e nada é pedido.
    func carregarMaisConversas(conta: String) async {
        guard let cursor = cursorDeConversas[conta], listasEmVoo.insert(conta).inserted else { return }
        let ep = epoca
        defer { if ep == epoca { listasEmVoo.remove(conta) } }
        do {
            let pagina = try await cliente.conversas(conta: conta, antes: cursor)
            // uma recarga da primeira página no meio do caminho vence esta
            guard ep == epoca, cursorDeConversas[conta] == cursor else { return }
            let atuais = estado.conversas(da: conta)
            let vistos = Set(atuais.map(\.jid))
            estado.substituirConversas(conta: conta, atuais + pagina.conversas.filter { !vistos.contains($0.jid) })
            cursorDeConversas[conta] = pagina.antes
        } catch {
            log.error("WhatsApp: página de conversas não lida — \(String(describing: error), privacy: .public)")
        }
    }

    /// Pareamento com sucesso: a conta nova aparece em `/v1/contas`.
    private func recarregarContas() async {
        let ep = epoca
        do {
            let contas = try await cliente.contas()
            guard ep == epoca else { return }
            estado.substituirContas(contas)
        } catch {
            log.error("WhatsApp: contas não relidas — \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Pareamento e reconexão

    /// Tela do QR de uma conta deslogada: pede um pareamento à ponte. Com um
    /// em `iniciando`/`qr` não pede de novo (o evento `pareamento` troca o QR
    /// sozinho); com `409 pareamento_em_andamento` adota o do corpo. Só QR (A82).
    func iniciarPareamento() async {
        switch estado.pareamento?.estado {
        case .iniciando?, .qr?: return
        default: await pedirPareamento()
        }
    }

    /// "Gerar outro" do QR expirado: inicia um pareamento novo.
    func gerarOutroQR() async {
        await pedirPareamento()
    }

    private func pedirPareamento() async {
        guard !pareamentoEmVoo else { return }
        pareamentoEmVoo = true
        let ep = epoca
        defer { if ep == epoca { pareamentoEmVoo = false } }
        do {
            let p = try await cliente.iniciarPareamento()
            guard ep == epoca else { return }
            estado.pareamento = p
        } catch {
            log.error("WhatsApp: pareamento não iniciado — \(String(describing: error), privacy: .public)")
        }
    }

    /// "Tentar de novo" da chave que não confere ou ausente (e da ponte fora):
    /// relê o arquivo da chave e acorda o canal, que reconecta na hora.
    func tentarDeNovo() async {
        _ = cliente.chave(relendo: true)
        canal?.acordou()
    }

    /// ponytail: erro que não é de chave nem de rede também cai em `.foraDoAr`,
    /// pra a tela não ficar presa em "carregando"; a próxima abertura tenta de novo.
    private static func conexao(do erro: Error) -> WAConexao {
        switch erro as? WAErroDoCliente {
        case .semChave?: return .semChave
        case .chaveNaoConfere?: return .chaveNaoConfere
        default: return .foraDoAr
        }
    }

    // MARK: - Conversa

    /// Conta a tela e lê a página mais recente se a conversa ainda não tem
    /// bolhas. Nunca marca lida.
    func abrir(_ k: WAChave) async {
        abertas[k, default: 0] += 1
        guard !estado.carregada(k) else { return }
        await lerPagina(k)
    }

    func fechar(_ k: WAChave) {
        guard let n = abertas[k] else { return }
        abertas[k] = n > 1 ? n - 1 : nil
    }

    func carregarMais(_ k: WAChave) async {
        guard let cursor = estado.antes[k] else { return }
        await lerPagina(k, antes: cursor)
    }

    private func lerPagina(_ k: WAChave, antes cursor: String? = nil) async {
        guard paginasEmVoo.insert(k).inserted else { return }
        let ep = epoca
        defer { if ep == epoca { paginasEmVoo.remove(k) } }
        do {
            let r = try await cliente.mensagens(conta: k.conta, conversa: k.jid, antes: cursor)
            guard ep == epoca else { return }
            estado.inserirMensagens(r.mensagens, em: k, antes: r.antes, maisVelhas: cursor != nil)
        } catch {
            log.error("WhatsApp: mensagens não lidas — \(String(describing: error), privacy: .public)")
        }
    }

    func marcarLida(_ k: WAChave) async {
        do {
            _ = try await cliente.marcarLida(conta: k.conta, conversa: k.jid)
        } catch {
            log.error("WhatsApp: marcar lida falhou — \(String(describing: error), privacy: .public)")
        }
    }

    /// Participantes de uma conversa de grupo, para o cabeçalho. Pede
    /// `GET /v1/grupo` só para jid `@g.us` e guarda 10 min; conversa
    /// individual é `nil` sem pedido. Falha devolve o que estava guardado.
    func grupo(_ k: WAChave) async -> WAGrupo? {
        guard k.jid.hasSuffix("@g.us") else { return nil }
        let pedido = agora()
        if let g = grupos[k], pedido.timeIntervalSince(g.lido) < Self.validadeDoGrupo { return g.grupo }
        let ep = epoca
        do {
            let g = try await cliente.grupo(conta: k.conta, jid: k.jid)
            guard ep == epoca else { return g }
            grupos[k] = (g, pedido)
            return g
        } catch {
            log.error("WhatsApp: grupo não lido — \(String(describing: error), privacy: .public)")
            return grupos[k]?.grupo
        }
    }

    // MARK: - Envio

    /// O campo e a faixa de citação de `k` esvaziam já com o envio em voo.
    func enviarTexto(_ texto: String, para k: WAChave, citando: WACitacao?) async {
        let ref = novoRef()
        definirRascunho("", para: k)
        citacoes[k] = nil
        estado.comecarEnvio(chave: k, texto: texto, citacao: citando, ref: ref,
                            agora: Int(Date().timeIntervalSince1970), remetente: k.conta)
        await enviar(texto, para: k, citar: citando?.id, ref: ref)
    }

    /// Reenvia a bolha que falhou com `ref` novo, no mesmo lugar.
    func retentar(idLocal: String, em k: WAChave) async {
        guard let b = estado.bolhas(de: k).first(where: { $0.id == idLocal }),
              case .falhou? = b.envio,
              // ponytail: nota de voz e anexo que falharam não reenviam (a cópia já foi apagada)
              b.mensagem.tipo == .texto else { return }
        let ref = novoRef()
        estado.retentar(idLocal: idLocal, novoRef: ref, chave: k)
        await enviar(b.mensagem.texto, para: k, citar: b.mensagem.citacao?.id, ref: ref)
    }

    /// Responder é ler: a conversa só vira lida depois de o envio dar certo.
    private func enviar(_ texto: String, para k: WAChave, citar: String?, ref: String) async {
        let ep = epoca
        do {
            let r = try await cliente.enviarTexto(conta: k.conta, para: k.jid, texto: texto, citar: citar, ref: ref)
            guard ep == epoca else { return }
            estado.confirmarEnvio(ref: ref, mensagem: r.mensagem, chave: k)
        } catch {
            guard ep == epoca else { return }
            log.error("WhatsApp: envio falhou — \(String(describing: error), privacy: .public)")
            estado.falharEnvio(ref: ref, chave: k)
            return
        }
        await marcarLida(k)
    }

    func reagir(_ emoji: String, a alvo: String, em k: WAChave) async {
        do {
            try await cliente.reagir(conta: k.conta, conversa: k.jid, alvo: alvo, emoji: emoji)
        } catch {
            log.error("WhatsApp: reação falhou — \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Anexo

    /// Foto, vídeo ou documento. Acima de 100 MiB não sai. A cópia em
    /// `pastaDeEnvio` vive só até a resposta: a ponte lê tudo antes de
    /// responder (docs/whatsapp-ponte.md:600-602).
    func enviarAnexo(_ url: URL, para k: WAChave, legenda: String?) async {
        erroDeAnexo = nil
        let tamanho = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard tamanho <= WAAnexo.limite else {
            erroDeAnexo = "Arquivo maior que 100 MB"
            return
        }
        let ep = epoca
        let pasta = pastaDeEnvio
        let copia: URL
        do {
            copia = try await Task.detached(priority: .userInitiated) {
                try WAAnexo.prepararEnvio(url, pasta: pasta)
            }.value
        } catch {
            log.error("WhatsApp: anexo não copiado — \(String(describing: error), privacy: .public)")
            erroDeAnexo = "Não deu pra ler o arquivo"
            return
        }
        defer { try? FileManager.default.removeItem(at: copia) }
        guard ep == epoca else { return }
        // saiu: o chip do anexo e a legenda (o campo) esvaziam
        anexos[k] = nil
        definirRascunho("", para: k)

        let tipo = WAAnexo.tipo(paraArquivo: url)
        let tipoDaBolha: WATipoMensagem
        switch tipo {
        case "imagem": tipoDaBolha = .imagem
        case "video": tipoDaBolha = .video
        default: tipoDaBolha = .documento
        }
        let texto = legenda ?? ""
        let ref = novoRef()
        estado.comecarEnvio(chave: k, texto: texto, tipo: tipoDaBolha, citacao: nil, ref: ref,
                            agora: Int(Date().timeIntervalSince1970), remetente: k.conta)
        do {
            let r = try await cliente.enviarMidia(conta: k.conta, para: k.jid, tipo: tipo, arquivo: copia,
                                                  nome: url.lastPathComponent,
                                                  legenda: texto.isEmpty ? nil : texto, citar: nil, ref: ref)
            guard ep == epoca else { return }
            estado.confirmarEnvio(ref: ref, mensagem: r.mensagem, chave: k)
        } catch {
            guard ep == epoca else { return }
            log.error("WhatsApp: envio de anexo falhou — \(String(describing: error), privacy: .public)")
            estado.falharEnvio(ref: ref, chave: k)
            return
        }
        await marcarLida(k)
    }

    // MARK: - Nota de voz

    func gravar(em k: WAChave) {
        guard gravacao == nil else { return }
        guard let fonte = fonteDeMicrofone else {
            erroDeGravacao = "Sem acesso ao microfone"
            return
        }
        sessaoDeGravacao &+= 1
        let sessao = sessaoDeGravacao
        niveisDaGravacao = []
        do {
            try fonte.comecar { [weak self] n in Self.naMain { self?.registrarNivel(n, sessao: sessao) } }
        } catch {
            log.error("WhatsApp: gravação não começou — \(String(describing: error), privacy: .public)")
            erroDeGravacao = "Sem acesso ao microfone"
            return
        }
        erroDeGravacao = nil
        fonteEmUso = fonte
        gravacao = WAGravacaoEmCurso(chave: k, inicio: Date(), nivel: 0)
    }

    private func registrarNivel(_ n: Float, sessao: UInt64) {
        guard sessao == sessaoDeGravacao, gravacao != nil else { return }
        niveisDaGravacao.append(n)
        gravacao?.nivel = n
    }

    func cancelarGravacao() {
        guard gravacao != nil else { return }
        _ = fonteEmUso?.parar()
        encerrarGravacao()
    }

    private func encerrarGravacao() {
        sessaoDeGravacao &+= 1
        fonteEmUso = nil
        niveisDaGravacao = []
        gravacao = nil
    }

    /// Para o microfone e manda como voz. Menos de 0,5 s é descartado. O Ogg
    /// fica na `pastaDeEnvio` só até a resposta: a ponte lê tudo antes de
    /// responder (docs/whatsapp-ponte.md:600-603).
    func pararEEnviarGravacao() async {
        guard let g = gravacao else { return }
        let amostras = fonteEmUso?.parar() ?? []
        let niveis = niveisDaGravacao
        encerrarGravacao()
        guard amostras.count >= WAOnda.taxa / 2 else {
            log.notice("WhatsApp: nota de voz curta demais, descartada")
            return
        }
        let k = g.chave
        let ep = epoca
        let arquivo: URL
        do {
            arquivo = try await gravarOgg(amostras)
        } catch {
            log.error("WhatsApp: nota de voz não codificada — \(String(describing: error), privacy: .public)")
            return
        }
        defer { try? FileManager.default.removeItem(at: arquivo) }

        let ref = novoRef()
        estado.comecarEnvio(chave: k, texto: "", tipo: .voz, citacao: nil, ref: ref,
                            agora: Int(Date().timeIntervalSince1970), remetente: k.conta)
        do {
            let r = try await cliente.enviarVoz(conta: k.conta, para: k.jid, arquivo: arquivo,
                                                segundos: WAOnda.segundos(amostras16k: amostras.count),
                                                onda: WAOnda.reduzir(niveis: niveis), citar: nil, ref: ref)
            guard ep == epoca else { return }
            estado.confirmarEnvio(ref: ref, mensagem: r.mensagem, chave: k)
        } catch {
            guard ep == epoca else { return }
            log.error("WhatsApp: envio de voz falhou — \(String(describing: error), privacy: .public)")
            estado.falharEnvio(ref: ref, chave: k)
            return
        }
        await marcarLida(k)
    }

    /// Codifica fora da main e grava `voz-<UUID>.ogg` na pasta de envio (0700).
    private func gravarOgg(_ amostras: [Float]) async throws -> URL {
        let pasta = pastaDeEnvio
        return try await Task.detached(priority: .userInitiated) {
            let (pacotes, preSkip) = try WACodificadorOpus().codificar(amostras)
            let dados = OggOpus.arquivo(pacotes: pacotes, preSkip: preSkip,
                                        totalAmostras48k: amostras.count * 3)
            let fm = FileManager.default
            try fm.createDirectory(at: pasta, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: pasta.path)
            let url = pasta.appendingPathComponent("voz-\(UUID().uuidString).ogg")
            try dados.write(to: url, options: .atomic)
            return url
        }.value
    }

    /// `k-<n>`: único no processo e bem abaixo dos 64 caracteres do contrato.
    private func novoRef() -> String {
        contadorDeRef += 1
        return "k-\(contadorDeRef)"
    }

    // MARK: - Rascunho

    func rascunho(_ k: WAChave) -> String { estado.rascunho(de: k) }

    func definirRascunho(_ texto: String, para k: WAChave) {
        estado.definirRascunho(texto, para: k)
    }

    /// Texto do ditado para o campo `chave` (`WAChave.texto`). Só escreve se
    /// esse é o campo em uso; junta ao rascunho com um espaço. `false` = o
    /// campo mudou no meio, e o ditado copia o texto (como no Ask).
    func receberDitado(_ texto: String, chave: String) -> Bool {
        guard let k = campoEmUso, k.texto == chave else { return false }
        let atual = rascunho(k)
        let novo: String
        if atual.isEmpty {
            novo = texto
        } else if atual.last?.isWhitespace == true {
            novo = atual + texto
        } else {
            novo = atual + " " + texto
        }
        definirRascunho(novo, para: k)
        return true
    }

    // MARK: - Citação e anexo pendente

    func citacao(_ k: WAChave) -> WACitacao? { citacoes[k] }

    func citar(_ m: WAMensagem, em k: WAChave) {
        citacoes[k] = WACitacao(id: m.id, remetente: m.remetente, texto: m.texto)
    }

    func cancelarCitacao(_ k: WAChave) { citacoes[k] = nil }

    func anexoPendente(_ k: WAChave) -> URL? { anexos[k] }

    /// `nil` tira o anexo (x no chip).
    func definirAnexo(_ url: URL?, para k: WAChave) {
        anexos[k] = url
        erroDeAnexo = nil
    }

    // MARK: - Harness

    /// Só snapshot: a gravação em curso sem microfone.
    func _injetarGravacao(_ g: WAGravacaoEmCurso?) {
        gravacao = g
    }

    /// Só testes e snapshot: põe o estado direto, sem canal.
    func _injetar(estado: WAEstado, conexao: WAConexao, canalAberto: Bool) {
        self.estado = estado
        self.conexao = conexao
        self.canalAberto = canalAberto
    }

    /// Só snapshot: o grupo já lido, sem pedir à ponte.
    func _injetar(grupo: WAGrupo, em k: WAChave) {
        grupos[k] = (grupo, agora())
    }

    /// Só snapshot: a mídia sai de uma pasta temporária, não do cache real.
    func _usarMidia(raiz: URL) {
        midia = WAMidiaCache(raiz: raiz, cliente: cliente)
    }

    /// Só testes e snapshot: volta ao recém-criado (inerte, sem canal, vazio).
    func _zerar() {
        stop()
        estado = WAEstado()
        abertas = [:]
        cursorDeConversas = [:]
        grupos = [:]
        campoEmUso = nil
        citacoes = [:]
        anexos = [:]
        cancelarGravacao()
    }
}
