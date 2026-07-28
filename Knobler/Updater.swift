//
//  Updater.swift — descobre e instala novas versões do Knobler.
//
//  Fonte da verdade: o release mais recente em github.com/luccas-silveira/knobler.
//  Este arquivo é deliberadamente autocontido (não conhece AppSettings, o notch,
//  nem a tela de Ajustes) para que tools/updatercheck.swift o compile isolado.
//

import AppKit    // NSApp.terminate no relaunch
import Foundation

/// Uma versão publicada no GitHub Releases.
struct Release: Equatable {
    /// "0.9.0" — sem o "v" da tag.
    let version: String
    /// Notas já limpas de markdown, prontas pro card.
    let notes: String
    /// Página do release (fallback quando não dá pra instalar sozinho).
    let url: URL
    /// O .zip anexado. nil = sem caminho de download direto.
    let asset: URL?
}

enum UpdateState: Equatable {
    case available(Release)
    case installing
    case failed(String)
}

// MARK: - Comparação de versão

/// Quebra "0.9.0" (ou "v0.9.0") em [0, 9, 0]. nil se não for X.Y.Z numérico.
private func versionComponents(_ v: String) -> [Int]? {
    let trimmed = v.hasPrefix("v") ? String(v.dropFirst()) : v
    let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    let numbers = parts.compactMap { Int($0) }
    return numbers.count == 3 ? numbers : nil
}

/// true se `a` é uma versão maior que `b`. Comparação por componente numérico —
/// "0.10.0" > "0.9.0", que a comparação de string erraria. Entrada malformada
/// devolve false: na dúvida, não anunciar update.
func isNewer(_ a: String, than b: String) -> Bool {
    guard let x = versionComponents(a), let y = versionComponents(b) else { return false }
    for (l, r) in zip(x, y) where l != r { return l > r }
    return false
}

// MARK: - Notas do release

/// O body do release vem em markdown (o release.sh copia do CHANGELOG). O card
/// mostra texto puro. ponytail: strip ingênuo (#, **, `) — cobre o que o
/// CHANGELOG usa; se um dia entrar link ou tabela, aí sim vale um parser.
func stripMarkdown(_ s: String) -> String {
    s.split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            var l = String(line.drop(while: { $0 == "#" }))
            l = l.replacingOccurrences(of: "**", with: "")
            l = l.replacingOccurrences(of: "`", with: "")
            return l.trimmingCharacters(in: .whitespaces)
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Parse da API

private struct APIRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL
    }
    let tagName: String
    let htmlUrl: URL
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
}

/// Converte a resposta de /releases/latest num Release.
/// Devolve nil para draft/prerelease — nenhum dos dois deve virar aviso.
func parseRelease(_ data: Data) throws -> Release? {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let api = try decoder.decode(APIRelease.self, from: data)
    guard !api.draft, !api.prerelease else { return nil }
    let version = api.tagName.hasPrefix("v") ? String(api.tagName.dropFirst()) : api.tagName
    return Release(
        version: version,
        notes: stripMarkdown(api.body ?? ""),
        url: api.htmlUrl,
        asset: api.assets.first { $0.name.hasSuffix(".zip") }?.browserDownloadUrl
    )
}

// MARK: - Updater

final class Updater: ObservableObject {
    static let shared = Updater()

    /// nil = nenhuma novidade (ou ainda não checou).
    @Published private(set) var state: UpdateState?

    /// Versão que o usuário mandou embora com "Depois". Persistida: o aviso não
    /// volta a incomodar até sair uma versão diferente.
    private(set) var skippedVersion: String? {
        didSet { UserDefaults.standard.set(skippedVersion, forKey: Self.skippedKey) }
    }

    /// Checagem periódica ligada. Quem manda aqui é o AppDelegate, espelhando
    /// AppSettings.checkForUpdates — o Updater não conhece as preferências.
    var automatic = true

    private static let skippedKey = "updateSkippedVersion"
    private static let lastCheckKey = "updateLastCheck"
    private static let feed = URL(
        string: "https://api.github.com/repos/luccas-silveira/knobler/releases/latest")!
    /// ponytail: 24h fixo. Vira preferência se alguém reclamar.
    private static let interval: TimeInterval = 24 * 60 * 60
    /// Folga pro app terminar de subir antes de gastar rede.
    private static let launchDelay: TimeInterval = 30

    private var timer: Timer?

    private init() {
        skippedVersion = UserDefaults.standard.string(forKey: Self.skippedKey)
    }

    /// Versão rodando agora, do Info.plist. "0.0.0" só em build sem MARKETING_VERSION.
    var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0.0.0"
    }

    /// true quando existe update disponível mas o usuário já disse "Depois".
    var isSkipped: Bool {
        guard case .available(let release) = state else { return false }
        return release.version == skippedVersion
    }

    /// Agenda a primeira checagem e o ciclo de 24h. Idempotente.
    func start() {
        timer?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchDelay) { [weak self] in
            self?.check()
        }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// `force` = o usuário clicou "Verificar agora": ignora o toggle e o intervalo.
    func check(force: Bool = false) {
        guard force || automatic else { return }
        if !force, let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < Self.interval { return }

        var request = URLRequest(url: Self.feed)
        request.timeoutInterval = 15
        // sem esta linha o GitHub responde com um envelope de mídia legado
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            // Falha de rede e rate limit (403) são silenciosos: não existe update
            // bom o bastante pra justificar um alerta de erro de rede.
            guard let data,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let release = try? parseRelease(data) else { return }
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            guard isNewer(release.version, than: self.installedVersion) else {
                DispatchQueue.main.async { self.state = nil }
                return
            }
            DispatchQueue.main.async { self.state = .available(release) }
        }.resume()
    }

    /// "Depois": some do notch, continua nos Ajustes.
    func skipCurrent() {
        guard case .available(let release) = state else { return }
        skippedVersion = release.version
        objectWillChange.send()
    }
}
