//
//  DevAvisos.swift
//  Knobler
//
//  Canal de avisos do desenvolvedor: um JSON público no repo, buscado no mesmo
//  ritmo do Updater (launch + 24 h), vira card no notch e entra no histórico.
//
//  Por que polling e não o relay: `webhookNotifications` é opt-in e nasce
//  desligado, então um broadcast pelo relay só alcançaria quem já pareou —
//  provavelmente a minoria. O JSON alcança 100% da base sem infra nova.
//
//  Timer próprio, não carona no `Updater.check()`: lá existe um
//  `guard force || automatic`, e quem desligasse "verificar atualizações"
//  perderia junto os avisos críticos.
//
//  O arquivo não conhece SwiftUI, AppKit nem AppSettings de propósito — é o que
//  deixa o `avisoscheck` compilar o filtro isolado (mesma razão do
//  `CalendarAviso` e do `NovidadesCatalogo`). Quem converte `Aviso` em
//  `NotchNotification` é o AppDelegate.
//

import Foundation
import os

/// Botão do card de aviso. `url` é sempre https — ver `DevAvisos.saneadas`.
struct AvisoAcao: Equatable, Decodable {
    let titulo: String
    let url: String
}

/// Um aviso já filtrado e saneado, pronto pra virar card.
struct Aviso: Equatable {
    let id: String
    let titulo: String
    let corpo: String
    /// Crítico atravessa o toggle desligado. Não atravessa o silêncio de
    /// reunião: quem silencia uma call perde mais do que ganha, e o card fica
    /// no Histórico.
    let critico: Bool
    let iconEmoji: String?
    let som: Bool
    let acoes: [AvisoAcao]
}

// MARK: - Feed cru

/// O que o JSON traz. Tudo opcional menos id/titulo/corpo: campo desconhecido
/// numa versão futura é ignorado sozinho pelo Decodable, e campo ausente numa
/// versão antiga não pode derrubar o parse.
private struct AvisoCru: Decodable {
    let id: String
    let titulo: String
    let corpo: String
    let prioridade: String?
    let iconEmoji: String?
    let som: Bool?
    let minVersao: String?
    let maxVersao: String?
    let acoes: [AvisoAcao]?
}

private struct FeedCru: Decodable {
    let versaoSchema: Int
    let avisos: [AvisoCru]
}

// MARK: - Filtro (puro)

enum DevAvisos {
    /// Bump obriga a pensar em quem roda a versão antiga: schema diferente é
    /// descartado inteiro, então um bump silencia o canal pra toda a base velha.
    static let versaoSchema = 1

    static let feedPadrao =
        "https://raw.githubusercontent.com/luccas-silveira/knobler/master/avisos.json"

    /// Tetos duros. O JSON é entrada de fora virando UI clicável: sem eles um
    /// arquivo errado (ou adulterado no caminho) enche o histórico, que tem cap
    /// de 300, e estoura o card.
    static let maxBytes = 64 * 1024
    static let maxAvisos = 10
    static let maxTitulo = 80
    static let maxCorpo = 400
    static let maxAcoes = 2

    static let chaveVistos = "avisos.vistos"
    /// ponytail: override do feed pra testar sem publicar nada
    /// (`defaults write com.zoi.knobler avisos.feedURL ...`). Quem escreve
    /// defaults já é dono da conta — não abre nada que já não estivesse aberto.
    static let chaveFeed = "avisos.feedURL"
    /// Teto da lista de já-vistos: ela só cresce, e ninguém consulta o passado
    /// remoto. Os mais recentes ficam.
    static let maxVistos = 100

    /// Avisos que esta instalação deve mostrar agora, na ordem do arquivo.
    ///
    /// - Parameters:
    ///   - vistos: ids já mostrados alguma vez (nunca reaparecem).
    ///   - ligado: o toggle de Ajustes. `false` silencia os normais, nunca os críticos.
    static func aplicaveis(json: Data,
                           versaoInstalada: String,
                           vistos: Set<String>,
                           ligado: Bool) -> [Aviso] {
        // JSON malformado é silencioso, igual à falha de rede do Updater: não
        // existe aviso bom o bastante pra justificar um alerta de erro de parse.
        guard json.count <= maxBytes,
              let feed = try? JSONDecoder().decode(FeedCru.self, from: json),
              feed.versaoSchema == versaoSchema
        else { return [] }

        var usados = Set<String>()
        var saida: [Aviso] = []
        // teto aplicado no cru: um arquivo gigante nem chega a ser processado
        for cru in feed.avisos.prefix(maxAvisos) {
            let id = cru.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !vistos.contains(id), usados.insert(id).inserted else { continue }
            guard dentroDaFaixa(instalada: versaoInstalada, min: cru.minVersao, max: cru.maxVersao)
            else { continue }

            let critico = cru.prioridade == "critica"
            guard critico || ligado else { continue }

            let titulo = trunca(cru.titulo, em: maxTitulo)
            guard !titulo.isEmpty else { continue }   // card sem título não diz nada

            saida.append(Aviso(id: id,
                               titulo: titulo,
                               corpo: trunca(cru.corpo, em: maxCorpo),
                               critico: critico,
                               iconEmoji: cru.iconEmoji?.isEmpty == false ? cru.iconEmoji : nil,
                               som: cru.som ?? false,
                               acoes: saneadas(cru.acoes)))
        }
        return saida
    }

    /// Faixa ausente = vale pra todas as versões. Faixa presente e **malformada
    /// = não vale pra ninguém**: `isNewer` devolve false pra lixo, então sem
    /// validar o formato antes um "0.19" com typo viraria aviso pra toda a base.
    static func dentroDaFaixa(instalada: String, min: String?, max: String?) -> Bool {
        guard versionComponents(instalada) != nil else { return false }
        if let min {
            guard versionComponents(min) != nil, !isNewer(min, than: instalada) else { return false }
        }
        if let max {
            guard versionComponents(max) != nil, !isNewer(instalada, than: max) else { return false }
        }
        return true
    }

    /// Só `https`. O `openURL` do card aceita `file://` e `app://` pros lembretes
    /// locais; um JSON remoto não pode abrir arquivo, app nem `javascript:`.
    static func saneadas(_ acoes: [AvisoAcao]?) -> [AvisoAcao] {
        (acoes ?? []).compactMap { acao -> AvisoAcao? in
            let titulo = trunca(acao.titulo, em: maxTitulo)
            guard !titulo.isEmpty,
                  let url = URL(string: acao.url),
                  url.scheme?.lowercased() == "https",
                  url.host?.isEmpty == false
            else { return nil }
            return AvisoAcao(titulo: titulo, url: acao.url)
        }
        .prefix(maxAcoes)
        .map { $0 }
    }

    private static func trunca(_ s: String, em limite: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= limite ? t : String(t.prefix(limite - 1)) + "…"
    }

    /// Ids vistos + os novos, podados pelo teto (mais recentes no fim).
    static func vistosAtualizados(_ atuais: [String], novos: [String]) -> [String] {
        var lista = atuais.filter { !novos.contains($0) } + novos
        if lista.count > maxVistos { lista.removeFirst(lista.count - maxVistos) }
        return lista
    }
}

// MARK: - Controller

/// Busca o feed no launch e a cada 24 h, e entrega os avisos que passaram pelo
/// filtro. Não decide nada sobre o card — quem publica é o AppDelegate.
final class DevAvisosController {
    /// Chamado na main queue, uma vez por aviso novo.
    var onAviso: ((Aviso) -> Void)?
    /// O toggle de Ajustes. O controller não conhece AppSettings.
    var ligadoProvider: () -> Bool = { true }

    private let log = Logger(subsystem: "com.zoi.knobler", category: "avisos")
    private static let interval: TimeInterval = 24 * 60 * 60
    /// Mesma folga do Updater: deixa o app terminar de subir antes de gastar rede.
    private static let launchDelay: TimeInterval = 45
    private var timer: Timer?

    var versaoInstalada: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0.0.0"
    }

    private var feedURL: URL? {
        let s = UserDefaults.standard.string(forKey: DevAvisos.chaveFeed) ?? DevAvisos.feedPadrao
        return URL(string: s)
    }

    /// Agenda a primeira busca e o ciclo de 24 h. Idempotente.
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

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Chamado na main queue (timer e launch). O toggle e os vistos são lidos
    /// aqui, antes do request: ler de dentro do callback exigiria um
    /// `main.sync`, que é deadlock esperando acontecer.
    func check() {
        guard let url = feedURL else { return }
        let ligado = ligadoProvider()
        let vistos = UserDefaults.standard.stringArray(forKey: DevAvisos.chaveVistos) ?? []
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // o raw do GitHub serve com cache de CDN; sem isto um aviso corrigido
        // demora mais que o necessário pra chegar
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self,
                  let data,
                  let http = response as? HTTPURLResponse, http.statusCode == 200
            else { return }   // rede/404: silencioso, igual ao Updater

            let avisos = DevAvisos.aplicaveis(json: data,
                                              versaoInstalada: self.versaoInstalada,
                                              vistos: Set(vistos),
                                              ligado: ligado)
            guard !avisos.isEmpty else { return }
            self.log.info("avisos novos: \(avisos.count, privacy: .public)")

            DispatchQueue.main.async {
                // grava ANTES de publicar: se o app morrer no meio, o pior caso
                // é perder um aviso — não repeti-lo em todo launch.
                UserDefaults.standard.set(
                    DevAvisos.vistosAtualizados(vistos, novos: avisos.map(\.id)),
                    forKey: DevAvisos.chaveVistos)
                avisos.forEach { self.onAviso?($0) }
            }
        }.resume()
    }
}
