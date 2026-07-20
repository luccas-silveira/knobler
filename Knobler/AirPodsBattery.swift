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

    /// Menor nível reportado (pra aviso de bateria baixa). nil se nada reportou.
    var minLevel: Int? { [left, right, case_].compactMap { $0 }.min() }

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
            return AirPodsBattery(name: name, left: left, right: right, case_: case_)
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
