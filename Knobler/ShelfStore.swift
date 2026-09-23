// Estado e persistência da prateleira, sem depender das views de arraste.
import Foundation
import Combine

final class ShelfStore: ObservableObject {
    @Published private(set) var entradas: [ShelfEntry] = [] {
        didSet {
            persistir()
            // A pilha aberta some por caminhos que não são ação dela: remover,
            // clear, a saída ao arrastar, e até um `add` (o arquivo re-arrastado
            // do Finder sai da pilha pelo dedupe do 004). Todos passam por aqui;
            // espalhar a reconciliação por mutador deixaria o próximo caminho
            // novo de fora.
            pilhaAberta = ShelfOrdem.pilhaAberta(pilhaAberta, em: entradas)
            // qualquer mudança invalida o desfazer: devolver a lista antiga
            // apagaria o que chegou depois. Quem remove grava DEPOIS de atribuir.
            desfazivel = nil
        }
    }
    /// A linha como estava antes do último ✕ ou "Limpar". Vive 5 s.
    @Published private(set) var desfazivel: [ShelfEntry]?
    private var expiracao: DispatchWorkItem?
    static let janelaDeDesfazer: TimeInterval = 5
    /// A pilha que está aberta em grade, tomando o card (ticket 008). Volátil:
    /// não entra no `shelfItems`, porque o notch não deve reabrir amanhã na
    /// pilha que alguém olhou hoje.
    @Published var pilhaAberta: ShelfEntry?
    /// Conversão esperando confirmação. Um de cada vez: abrir outra descarta a
    /// anterior, senão duas pastas temporárias ficariam vivas sem dono na tela.
    @Published var preview: ShelfPreview?
    private static let capacity = 8
    private static let storageKey = "shelfItems"
    private let defaults: UserDefaults

    private func persistir() {
        defaults.set(ShelfOrdem.codificar(entradas), forKey: Self.storageKey)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let salvo = defaults.object(forKey: Self.storageKey)
        entradas = ShelfOrdem.decodificar(salvo, capacidade: Self.capacity)
        // `didSet` NÃO roda em atribuição dentro do init: sem esta chamada a
        // migração ficaria só em memória, o array plano continuaria no disco e
        // seria relido (e reinvertido) a cada lançamento.
        if (salvo as? [String]) != nil { persistir() }
    }

    /// Os arquivos de todas as entradas, achatados. Só pra quem opera em
    /// arquivo (AirDrop); quem conta VAGA usa `entradas.count`.
    var arquivos: [URL] { entradas.flatMap(\.urls) }

    func add(_ url: URL) { add([url]) }

    /// Uma atribuição só: o didSet grava no UserDefaults a cada uma.
    func add(_ urls: [URL]) {
        entradas = ShelfOrdem.inserir(urls, em: entradas, capacidade: Self.capacity)
    }

    /// Abre a pilha em grade. Item solto não abre nada.
    func abrirPilha(_ alvo: ShelfEntry) {
        guard alvo.isPilha, entradas.contains(where: { $0.id == alvo.id }) else { return }
        pilhaAberta = alvo
    }

    /// Tira UM arquivo de dentro de uma entrada (ticket 008). É o mesmo caminho
    /// do ✕ da célula e do arraste de um arquivo pra fora da pilha aberta; o
    /// `didSet` fecha a grade sozinho quando a pilha deixa de existir.
    func removerArquivo(_ url: URL, de alvo: ShelfEntry) {
        entradas = ShelfOrdem.remover(url, de: alvo, em: entradas)
    }

    /// Junta arquivos numa entrada que já está na linha (ticket 007).
    func empilhar(_ urls: [URL], em alvo: ShelfEntry) {
        entradas = ShelfOrdem.empilhar(urls, em: alvo, entradas: entradas)
    }

    /// Abre a pilha: os arquivos voltam a ser itens soltos (ticket 007).
    func desempilhar(_ alvo: ShelfEntry) {
        entradas = ShelfOrdem.desempilhar(alvo, em: entradas, capacidade: Self.capacity)
    }

    /// Tira a entrada inteira. Remover um arquivo de dentro de uma pilha é
    /// outra ação, e ela ainda não existe.
    /// `desfazivel: false` é a saída por arraste: o arquivo foi pra outro
    /// lugar de propósito, não há o que desfazer.
    func remover(_ entrada: ShelfEntry, desfazivel: Bool = true) {
        guard entradas.contains(where: { $0.id == entrada.id }) else { return }
        let anterior = entradas
        entradas.removeAll { $0.id == entrada.id }
        if desfazivel { guardarDesfazer(anterior) }
    }

    func clear() {
        // a atribuição zeraria o desfazer mesmo sem nada pra limpar
        guard !entradas.isEmpty else { return }
        let anterior = entradas
        entradas.removeAll()
        guardarDesfazer(anterior)
    }

    func desfazer() {
        guard let anterior = desfazivel else { return }
        expiracao?.cancel()
        entradas = anterior
    }

    private func guardarDesfazer(_ anterior: [ShelfEntry]) {
        desfazivel = anterior
        expiracao?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.desfazivel = nil }
        expiracao = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.janelaDeDesfazer, execute: item)
    }

    /// Abre o preview de uma conversão. Substitui o que estiver aberto.
    @MainActor
    func startPreview(_ url: URL, to target: ConversionTarget) {
        preview?.descartar()
        preview = ShelfPreview(source: url, target: target)
    }

    /// Grava o resultado ao lado do original e põe no shelf.
    @MainActor
    func confirmPreview() {
        guard let preview else { return }
        // só a primeira página volta pro shelf: um PDF de 30 páginas estouraria
        // a prateleira (capacidade 8) e empurraria tudo pra fora
        if let first = preview.salvar().first { add(first) }
        if !preview.failed && !preview.running { self.preview = nil }
    }

    @MainActor
    func cancelPreview() {
        preview?.descartar()
        preview = nil
    }
}

