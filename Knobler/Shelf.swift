//
//  Shelf.swift
//  Knobler
//
//  Prateleira de arquivos: arraste pro notch (expande sozinho ao aproximar),
//  os itens ficam no card expandido e saem arrastando de volta pro Finder.
//  ponytail: persiste paths em UserDefaults (app não é sandboxed) —
//  bookmarks security-scoped só se um dia sandboxar.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ShelfStore: ObservableObject {
    @Published private(set) var entradas: [ShelfEntry] = [] {
        didSet { persistir() }
    }
    /// Conversão esperando confirmação. Um de cada vez: abrir outra descarta a
    /// anterior, senão duas pastas temporárias ficariam vivas sem dono na tela.
    @Published var preview: ShelfPreview?
    private static let capacity = 8
    private static let storageKey = "shelfItems"

    private func persistir() {
        UserDefaults.standard.set(ShelfOrdem.codificar(entradas), forKey: Self.storageKey)
    }

    init() {
        let salvo = UserDefaults.standard.object(forKey: Self.storageKey)
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
    func remover(_ entrada: ShelfEntry) {
        entradas.removeAll { $0.id == entrada.id }
    }

    func clear() {
        entradas.removeAll()
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
        self.preview = nil
    }

    @MainActor
    func cancelPreview() {
        preview?.descartar()
        preview = nil
    }
}

/// Espera TODOS os providers de arquivo de um drop e entrega as URLs de uma vez
/// (tickets 006 e 007).
///
/// Cada callback escreve no próprio índice, na main — a ordem do drop é a ordem
/// da pilha, e `capa` (o que a miniatura mostra e o menu de contexto opera) fica
/// determinística em vez de sorteada pela ordem de chegada. Sem lock porque só a
/// main toca o buffer.
///
/// ponytail: um provider que nunca chama de volta segura o drop inteiro em vez
/// de perder um arquivo só. Sem timeout até isso aparecer na prática.
enum ShelfArquivos {
    static func juntos(_ providers: [NSItemProvider],
                       pronto: @escaping ([URL]) -> Void) {
        guard !providers.isEmpty else { return }
        var recebidos = [URL?](repeating: nil, count: providers.count)
        var faltam = providers.count
        for (i, provider) in providers.enumerated() {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let url = ShelfArquivos.url(from: item)
                DispatchQueue.main.async {
                    if let url, url.isFileURL { recebidos[i] = url }
                    faltam -= 1
                    guard faltam == 0 else { return }
                    let urls = recebidos.compactMap { $0 }
                    if !urls.isEmpty { pronto(urls) }
                }
            }
        }
    }

    fileprivate static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
                ?? String(data: data, encoding: .utf8).flatMap(URL.init(string:))
        }
        if let texto = item as? String { return URL(string: texto) }
        return nil
    }
}

/// Aproximou um arquivo do notch → expande na hora; soltou → entra na prateleira.
struct ShelfDropDelegate: DropDelegate {
    let shelf: ShelfStore
    let vm: NotchViewModel

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL, .url, .plainText])
    }

    func dropEntered(info: DropInfo) {
        vm.setExpandedDirect(true)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL, .url, .plainText])
        guard !providers.isEmpty else { return false }
        // marca o arraste que terminou aqui dentro, pro 005 não confundir
        // empilhamento com saída — o `loadItem` abaixo é assíncrono, então isto
        // precisa ser síncrono e antes dele
        ShelfArrasteInterno.pendente = true
        // Os arquivos do MESMO drop viram uma entrada só (ticket 006): os
        // demais tipos (link, texto) continuam cada um por si.
        let arquivos = providers.filter {
            $0.registeredTypeIdentifiers.contains(UTType.fileURL.identifier)
        }
        // arraste que saiu da própria prateleira não vira entrada nova: quem
        // resolve esse caso é o fim da sessão de arraste (ticket 007)
        if !ShelfArrasteInterno.origemInterna {
            ShelfArquivos.juntos(arquivos) { [weak shelf] urls in shelf?.add(urls) }
        }
        for provider in providers where !arquivos.contains(provider) {
            carregar(provider)
        }
        return true
    }

    /// Espera TODOS os providers de arquivo do drop e chama `add` uma vez só.
    ///
    /// Decide o caminho pelo que ESTE provider registra, não por qual lista
    /// veio cheia.
    ///
    /// O motivo é o Chrome: arrastar um link de lá anuncia
    /// `com.apple.pasteboard.promised-file-url`, que conforma a `public.file-url`.
    /// Filtrar por conformidade (`itemProviders(for: [.fileURL])`) pescava o
    /// link junto, mandava pro caminho de arquivo e o `loadItem` devolvia nada —
    /// o notch abria e o link sumia sem erro. Por isso a comparação aqui é com
    /// o identificador **exato**.
    /// Só os providers que NÃO são arquivo chegam aqui: os de arquivo saem
    /// agrupados pelo `ShelfArquivos.juntos` (ticket 006).
    private func carregar(_ provider: NSItemProvider) {
        let tipos = provider.registeredTypeIdentifiers
        if tipos.contains(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                guard let url = ShelfArquivos.url(from: item), LinkBrowser.isWebLink(url) else { return }
                abrir(url)
            }
            return
        }
        guard tipos.contains(UTType.plainText.identifier) else { return }
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
            guard let texto = Self.texto(from: item),
                  !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            // texto que é só uma URL vale mais como link que como .txt
            if let url = URL(string: texto.trimmingCharacters(in: .whitespacesAndNewlines)),
               LinkBrowser.isWebLink(url) {
                abrir(url)
                return
            }
            Self.materializar(shelf) { try ShelfDrop.materializar(texto: texto) }
        }
    }

    /// O provider entrega `Data`, `URL` ou `NSURL` conforme a origem do arraste.

    private static func texto(from item: NSSecureCoding?) -> String? {
        if let texto = item as? String { return texto }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    /// Link arrastado só abre o preview. **Não** vira item da prateleira: ela é
    /// pra arquivo que você vai usar depois, e encher de atalho de cada link
    /// espiado empurraria pra fora o que estava lá (a capacidade é 8).
    private func abrir(_ url: URL) {
        // Sem a peça instalada a ação some, calada (regra 5): o link solto
        // não vira preview nem item da prateleira (comentário acima: link
        // nunca materializa como arquivo).
        guard PluginHost.shared.estaInstalado(.previewLink) else { return }
        DispatchQueue.main.async { [vm] in
            LinkPreview.shared.abrir(url, on: vm.displayID)
            vm.setExpandedDirect(true)
            vm.pedirFoco(.link)
        }
    }

    /// Escreve fora da main (é I/O) e entra no shelf na main.
    private static func materializar(_ shelf: ShelfStore, _ escrever: @escaping () throws -> URL) {
        do {
            let url = try escrever()
            DispatchQueue.main.async { [weak shelf] in shelf?.add(url) }
        } catch {
            NSLog("knobler: não deu pra guardar o item arrastado: \(error)")
            NSSound.beep()
        }
    }
}

struct ShelfRowView: View {
    @ObservedObject var shelf: ShelfStore
    /// Foco na prateleira ao abrir o preview de conversão.
    var vm: NotchViewModel?
    /// Envio por AirDrop que reporta estado no notch. nil (harness de snapshot,
    /// que não tem AppDelegate) cai no envio mudo de sempre.
    var onAirDrop: (([URL]) -> Void)?

    private func enviar(_ urls: [URL]) {
        if let onAirDrop { onAirDrop(urls) } else { Sharing.airdrop(urls) }
    }

    var body: some View {
        if let preview = shelf.preview {
            ShelfPreviewView(preview: preview, shelf: shelf)
        } else {
            grade
        }
    }

    private var grade: some View {
        HStack(spacing: 14) {
            ForEach(shelf.entradas) { entrada in
                shelfItem(entrada)
            }
            Spacer(minLength: 0)
            Button("Limpar") { shelf.clear() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    /// A linha desenha a capa da entrada, e o menu opera sobre ela — só
    /// "Compartilhar" e "Desempilhar" enxergam a pilha inteira.
    private func shelfItem(_ entrada: ShelfEntry) -> some View {
        let url = entrada.capa
        return VStack(spacing: 3) {
            // miniatura é uma view AppKit = fonte de drag (ver ShelfThumbnailDragView)
            ShelfThumbnailDragView(
                urls: entrada.urls,
                // soltou esta entrada em cima de outra: as duas viram uma pilha,
                // na posição da entrada de baixo (ticket 007)
                onSoltouSobre: { alvo in shelf.empilhar(entrada.urls, em: ShelfEntry(alvo)) }
            ) { aceitou, dentroDoNotch in
                if ShelfOrdem.saiAoArrastar(
                    aceitou: aceitou, dentroDoNotch: dentroDoNotch,
                    habilitado: AppSettings.shared.shelfSaiAoArrastar) {
                    shelf.remover(entrada)
                }
            }
            .frame(width: 30, height: 30)
            .background(alignment: .bottomTrailing) { folhasDaPilha(entrada) }
            .overlay(alignment: .bottomTrailing) { contagemDaPilha(entrada) }
            Text(entrada.isPilha ? "\(entrada.urls.count) arquivos" : url.lastPathComponent)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: 58)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                shelf.remover(entrada)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6), .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -5)
        }
        .contextMenu {
            if let link = ShelfDrop.link(de: url) {
                // "Abrir no notch" some sem a peça instalada (regra 5); "Abrir
                // no navegador" não depende dela e continua sempre disponível.
                if PluginHost.shared.estaInstalado(.previewLink) {
                    Button("Abrir no notch") {
                        LinkPreview.shared.abrir(link, on: vm?.displayID)
                        vm?.focar(.link)
                    }
                }
                Button("Abrir no navegador") { NSWorkspace.shared.open(link) }
                Divider()
            }
            // Sem a peça instalada, "Converter" some — calado, sem aviso e sem
            // botão desabilitado (regra 5).
            let targets = PluginHost.shared.estaInstalado(.conversao)
                ? FileConverter.targets(for: url) : []
            if !targets.isEmpty {
                Menu("Converter") {
                    ForEach(targets, id: \.self) { target in
                        Button(target.label) {
                            shelf.startPreview(url, to: target)
                            vm?.focar(.shelf)
                        }
                    }
                }
            }
            Menu("Compartilhar") {
                Button("Enviar por AirDrop") { enviar(entrada.urls) }
                Button("Compartilhar…") { Sharing.share(entrada.urls) }
                // "tudo" conta ARQUIVOS, não vagas: é o que vai no envio.
                if shelf.arquivos.count > 1 {
                    Divider()
                    Button("Enviar tudo por AirDrop (\(shelf.arquivos.count))") {
                        enviar(shelf.arquivos)
                    }
                }
            }
            Divider()
            Button("Mostrar no Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            if entrada.isPilha {
                Button("Desempilhar") { shelf.desempilhar(entrada) }
            }
            Button("Remover do shelf") { shelf.remover(entrada) }
        }
        .transition(.blurReplace)
    }

    /// Duas folhas atrás da miniatura: o que diz "é pilha" sem ler número.
    @ViewBuilder
    private func folhasDaPilha(_ entrada: ShelfEntry) -> some View {
        if entrada.isPilha {
            ZStack {
                ForEach([4.0, 2.0], id: \.self) { desvio in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.18))
                        .frame(width: 30, height: 30)
                        .offset(x: desvio, y: desvio)
                }
            }
        }
    }

    /// Quantos arquivos a pilha tem.
    @ViewBuilder
    private func contagemDaPilha(_ entrada: ShelfEntry) -> some View {
        if entrada.isPilha {
            Text("\(entrada.urls.count)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 3)
                .background(Capsule().fill(.black.opacity(0.75)))
                .offset(x: 8, y: 4)
        }
    }

}
