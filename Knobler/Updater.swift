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

    /// Dá pra instalar de dentro do app, ou só resta abrir a página do release?
    /// Cacheado de propósito: descobrir isso roda `brew list` (~1s), e a UI lê
    /// esta propriedade a cada redraw — sondar no `body` travaria a janela.
    @Published private(set) var canInstall = false

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
                DispatchQueue.main.async {
                    self.state = nil
                    self.canInstall = false
                }
                return
            }
            // já estamos fora da main queue: a sonda do brew cabe aqui
            let installable = self.probeCanInstall(release)
            DispatchQueue.main.async {
                self.canInstall = installable
                self.state = .available(release)
            }
        }.resume()
    }

    /// "Depois": some do notch, continua nos Ajustes.
    func skipCurrent() {
        guard case .available(let release) = state else { return }
        skippedVersion = release.version
        objectWillChange.send()
    }
}

// MARK: - Instalação

extension Updater {
    /// Caminhos do brew: Apple Silicon primeiro, Intel depois.
    private static var brewPaths: [String] {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    }

    private var brewPath: String? {
        Self.brewPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// O app veio do cask? Se sim, atualizar por fora desincronizaria o Caskroom.
    private var installedViaBrew: Bool {
        guard let brew = brewPath else { return false }
        return run(brew, ["list", "--cask", "knobler"]).status == 0
    }

    /// Substituir o bundle só é seguro em /Applications — num build de
    /// desenvolvimento isso apagaria a árvore de build debaixo do Xcode.
    private var isInApplications: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    var releaseURL: URL? {
        guard case .available(let release) = state else { return nil }
        return release.url
    }

    /// Descobre se dá pra instalar sozinho. **Chame fora da main queue**: o
    /// `brew list` daqui leva ~1s. O resultado vira o `canInstall` publicado.
    func probeCanInstall(_ release: Release) -> Bool {
        if installedViaBrew { return true }
        return release.asset != nil && isInApplications
    }

    /// Roda um binário e devolve status + saída. Lê até EOF antes do wait para
    /// não travar se a saída encher o buffer do pipe.
    private func run(_ path: String, _ args: [String],
                     env: [String: String] = [:]) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if !env.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            env.forEach { merged[$0.key] = $0.value }
            p.environment = merged
        }
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch { return (-1, "", "não consegui executar \(path)") }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                String(decoding: outData, as: UTF8.self),
                String(decoding: errData, as: UTF8.self))
    }

    /// Última linha não-vazia — o que vale mostrar de um stderr de 40 linhas.
    private func lastLine(_ s: String) -> String {
        s.split(separator: "\n").last.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? "erro desconhecido"
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async { self.state = .failed(message) }
    }

    /// Instala a versão disponível e reinicia o app. Não bloqueia a main queue.
    func install() {
        guard case .available(let release) = state else { return }
        DispatchQueue.main.async { self.state = .installing }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let ok = self.installedViaBrew
                ? self.installViaBrew()
                : self.installDirect(release)
            if ok { self.relaunch() }
        }
    }

    // MARK: caminho brew

    private func installViaBrew() -> Bool {
        guard let brew = brewPath else {
            fail("Homebrew não encontrado."); return false
        }
        // ponytail: `git pull` só no tap. `brew update` completo busca todos os
        // taps da máquina e leva ~30s pra descobrir uma linha de versão.
        let repo = run(brew, ["--repository", "luccas-silveira/knobler"])
            .out.trimmingCharacters(in: .whitespacesAndNewlines)
        if !repo.isEmpty, FileManager.default.fileExists(atPath: repo) {
            _ = run("/usr/bin/git", ["-C", repo, "pull", "--ff-only", "-q"])
        }
        let upgrade = run(brew, ["upgrade", "--cask", "knobler"],
                          env: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
        guard upgrade.status == 0 else {
            fail(lastLine(upgrade.err.isEmpty ? upgrade.out : upgrade.err)); return false
        }
        return true
    }

    // MARK: caminho direto

    private func installDirect(_ release: Release) -> Bool {
        guard let asset = release.asset else {
            fail("Este release não tem .zip pra baixar."); return false
        }
        // A URL vem do JSON da API; se esse JSON for adulterado, o download
        // apontaria pra qualquer lugar. Só aceitamos o host e o repo oficiais.
        guard asset.scheme == "https",
              asset.host == "github.com",
              asset.path.hasPrefix("/luccas-silveira/knobler/releases/download/") else {
            fail("Origem do download não confere."); return false
        }
        guard isInApplications else {
            fail("O Knobler não está em /Applications."); return false
        }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("knobler-update-\(release.version)")
        try? fm.removeItem(at: work)
        guard (try? fm.createDirectory(at: work, withIntermediateDirectories: true)) != nil else {
            fail("Não consegui criar a pasta temporária."); return false
        }
        defer { try? fm.removeItem(at: work) }

        // 1. baixa o zip (~7MB) de forma síncrona — já estamos fora da main queue
        let zip = work.appendingPathComponent("Knobler.zip")
        guard let data = try? Data(contentsOf: asset), (try? data.write(to: zip)) != nil else {
            fail("Falha ao baixar a atualização."); return false
        }

        // 2. extrai preservando os atributos do bundle
        let extracted = work.appendingPathComponent("extraido")
        let unzip = run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])
        guard unzip.status == 0 else {
            fail("Falha ao extrair: \(lastLine(unzip.err))"); return false
        }
        let newApp = extracted.appendingPathComponent("Knobler.app")
        guard fm.fileExists(atPath: newApp.path) else {
            fail("O zip não contém Knobler.app."); return false
        }

        // 3. sanidade antes de encostar em /Applications.
        // --verify --strict prova só que o bundle é internamente íntegro, não
        // QUEM assinou. Exigimos também o bundle ID: um zip trocado por outro
        // app válido (assinado por qualquer um) não passa daqui.
        let verify = run("/usr/bin/codesign", ["--verify", "--strict", newApp.path])
        guard verify.status == 0 else {
            fail("Assinatura inválida no app baixado."); return false
        }
        // ponytail: não comparamos a *identidade* com a do app atual de propósito
        // — a transição de Apple Development pro cert local (Knobler Local
        // Signing) é esperada e travaria o primeiro update. A confiança vem do
        // canal: HTTPS + host e repo fixos, validados acima.
        let plist = newApp.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: plist)
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            fail("O app baixado não é o Knobler."); return false
        }
        let downloaded = info?["CFBundleShortVersionString"] as? String
        guard downloaded == release.version else {
            fail("O app baixado é \(downloaded ?? "?"), esperava \(release.version)."); return false
        }

        // 4. quarantine fora antes de mover (é o que o postflight do cask faz)
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        // 5. troca atômica; falha típica aqui é /Applications sem permissão
        do {
            _ = try fm.replaceItemAt(Bundle.main.bundleURL, withItemAt: newApp,
                                     backupItemName: nil, options: [.usingNewMetadataOnly])
        } catch {
            fail("Não consegui substituir o app: \(error.localizedDescription)")
            return false
        }
        return true
    }

    // MARK: relaunch

    /// O processo atual sobrevive à substituição do bundle (o inode antigo segue
    /// vivo), então quem reabre o app tem que ser alguém de fora: um shell que
    /// espera este PID morrer.
    private func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundleURL.path
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done; "
            + "sleep 1; open -a \"\(path)\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}
