//
//  AirPodsBattery.swift
//  Knobler
//
//  Bateria por componente dos AirPods conectados, lida do JSON do
//  `system_profiler SPBluetoothDataType -json`. Modelo puro (Foundation) —
//  o parser é testável isolado (tools/airpods_selfcheck.swift).
//

import Foundation

struct AirPodsBattery: Equatable {
    var name: String
    var left: Int?
    var right: Int?
    /// `case` é palavra reservada em Swift.
    var case_: Int?
    /// Modelo pelo `device_productID`; define os ícones. Último campo com
    /// default pra o init memberwise antigo continuar valendo.
    var model: AirPodsModel = .unknown
    /// `device_productID` cru: escolhe a foto do macOS do modelo exato.
    var productID: Int?

    /// Menor nível reportado (pra aviso de bateria baixa). nil se nada reportou.
    var minLevel: Int? { [left, right, case_].compactMap { $0 }.min() }

    /// O que a ilha mostra: o fone mais descarregado. Estojo fica fora, como no iPhone.
    var islandLevel: Int? { [left, right].compactMap { $0 }.min() }

    /// Mesmo limite do aviso do `BluetoothMonitor`.
    static func isLow(_ level: Int) -> Bool { level <= 10 }

    /// Extrai os AirPods conectados do JSON do system_profiler. nil se não há
    /// fone reportando bateria (só teclado/mouse/alto-falante, ou nada).
    static func parse(from data: Data) -> AirPodsBattery? {
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let group = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
            let connected = group["device_connected"] as? [[String: Any]]
        else { return nil }

        for entry in connected {
            // cada item é um dict de chave única: nome do device → propriedades
            guard let (name, raw) = entry.first,
                  let props = raw as? [String: Any],
                  props["device_minorType"] as? String == "Headphones"
            else { continue }

            let left = pct(props["device_batteryLevelLeft"])
            let right = pct(props["device_batteryLevelRight"])
            let case_ = pct(props["device_batteryLevelCase"])
            // AirPods reportam ao menos um nível; fone burro (sem bateria) é ignorado
            guard left != nil || right != nil || case_ != nil else { continue }
            let id = (props["device_productID"] as? String)
                .flatMap { Int($0.lowercased().replacingOccurrences(of: "0x", with: ""), radix: 16) }
            return AirPodsBattery(name: name, left: left, right: right, case_: case_,
                                  model: AirPodsModel(productID: id), productID: id)
        }
        return nil
    }

    /// "90%" → 90; número puro → ele mesmo; qualquer outra coisa → nil.
    private static func pct(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        guard let s = value as? String else { return nil }
        let digits = s.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }
}

/// Por que o monitor anunciou: conexão abre a ilha, bateria baixa abre o card.
enum AirPodsAnnounce: Equatable { case connected, lowBattery }

/// Modelos pelos Product IDs da Apple (vendor 0x004C). Fonte: AirBattery e
/// status-trio; ver docs/superpowers/research/2026-09-22-airpods-animados-research.md.
enum AirPodsModel: Equatable {
    case pro, gen12, gen3, gen4, max, unknown

    init(productID: Int?) {
        switch productID {
        case 0x200E, 0x2014, 0x2024, 0x2027, 0x2028: self = .pro
        case 0x2002, 0x200F: self = .gen12
        case 0x2013: self = .gen3
        case 0x2019, 0x201B: self = .gen4
        case 0x200A, 0x201F: self = .max
        default: self = .unknown
        }
    }

    /// AirPods 4 só tem símbolo próprio a partir do macOS 15.2; antes usa o da 3ª.
    private var gen4Disponivel: Bool {
        if #available(macOS 15.2, *) { return true }
        return false
    }

    var pairSymbol: String {
        switch self {
        case .pro, .unknown: return "airpodspro"
        case .gen12: return "airpods"
        case .gen3: return "airpods.gen3"
        case .gen4: return gen4Disponivel ? "airpods.gen4" : "airpods.gen3"
        case .max: return "airpodsmax"
        }
    }

    var leftSymbol: String { side("left") }
    var rightSymbol: String { side("right") }

    /// Lados usam o singular ("airpod.left"), exceto o 4, que já nasceu no plural.
    private func side(_ lado: String) -> String {
        switch self {
        case .pro, .unknown: return "airpodpro.\(lado)"
        case .gen12: return "airpod.\(lado)"
        case .gen3: return "airpod.gen3.\(lado)"
        case .gen4: return gen4Disponivel ? "airpods.gen4.\(lado)" : "airpod.gen3.\(lado)"
        case .max: return "airpodsmax"
        }
    }

    /// Product IDs a tentar nas fotos do macOS, na ordem: o exato e depois
    /// irmãos de mesmo visual (o catálogo do sistema não tem todo ID).
    func photoIDs(productID: Int?) -> [Int] {
        let irmaos: [Int]
        switch self {
        case .pro: irmaos = [0x2014, 0x200E]
        case .gen12: irmaos = [0x200F, 0x2002]
        case .gen3: irmaos = [0x2013]
        case .gen4, .max, .unknown: irmaos = []
        }
        var ids = productID.map { [$0] } ?? []
        for id in irmaos where !ids.contains(id) { ids.append(id) }
        return ids
    }

    /// nil = sem estojo (Max): a coluna some.
    var caseSymbol: String? {
        switch self {
        case .pro, .unknown: return "airpodspro.chargingcase.wireless"
        case .gen12: return "airpods.chargingcase"
        case .gen3: return "airpods.gen3.chargingcase.wireless"
        case .gen4: return gen4Disponivel ? "airpods.gen4.chargingcase.wireless" : "airpods.gen3.chargingcase.wireless"
        case .max: return nil
        }
    }
}
