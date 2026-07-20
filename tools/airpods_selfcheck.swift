//
//  tools/airpods_selfcheck.swift — self-check do parser de bateria dos AirPods.
//  Roda: swiftc -parse-as-library -swift-version 5 Knobler/AirPodsBattery.swift \
//        tools/airpods_selfcheck.swift -o build/apcheck && ./build/apcheck
//

import Foundation

@main
enum AirPodsSelfCheck {
    static func json(_ s: String) -> Data { s.data(using: .utf8)! }

    static func main() {
        // caso feliz: AirPods com L/R/estojo
        let full = json("""
        { "SPBluetoothDataType": [ { "device_connected": [
          { "Fone de Alguém": {
              "device_batteryLevelLeft": "90%",
              "device_batteryLevelRight": "89%",
              "device_batteryLevelCase": "31%",
              "device_minorType": "Headphones" } },
          { "Alto-falante": { "device_minorType": "Speaker" } }
        ] } ] }
        """)
        precondition(AirPodsBattery.parse(from: full)
            == AirPodsBattery(name: "Fone de Alguém", left: 90, right: 89, case_: 31), "full")

        // componente ausente vira nil (AirPods Max: sem estojo)
        let noCase = json("""
        { "SPBluetoothDataType": [ { "device_connected": [
          { "Max": { "device_batteryLevelLeft": "70%", "device_batteryLevelRight": "72%", "device_minorType": "Headphones" } }
        ] } ] }
        """)
        precondition(AirPodsBattery.parse(from: noCase)
            == AirPodsBattery(name: "Max", left: 70, right: 72, case_: nil), "noCase")

        // fone sem bateria + não-fones → nil (não é AirPods)
        let noBattery = json("""
        { "SPBluetoothDataType": [ { "device_connected": [
          { "Teclado": { "device_minorType": "Keyboard" } },
          { "Fone burro": { "device_minorType": "Headphones" } }
        ] } ] }
        """)
        precondition(AirPodsBattery.parse(from: noBattery) == nil, "noBattery")

        // nada conectado → nil
        precondition(AirPodsBattery.parse(
            from: json(#"{ "SPBluetoothDataType": [ { "device_connected": [] } ] }"#)) == nil, "empty")

        // JSON lixo → nil (não crasha)
        precondition(AirPodsBattery.parse(from: json("nao é json")) == nil, "garbage")

        // bateria como número puro também parseia
        let intPct = json("""
        { "SPBluetoothDataType": [ { "device_connected": [
          { "Fone": { "device_batteryLevelLeft": 55, "device_minorType": "Headphones" } }
        ] } ] }
        """)
        precondition(AirPodsBattery.parse(from: intPct)
            == AirPodsBattery(name: "Fone", left: 55, right: nil, case_: nil), "intPct")

        print("airpods parser: OK")
    }
}
