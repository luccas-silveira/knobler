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

        // minLevel = menor componente reportado (nil se nenhum reportou)
        precondition(AirPodsBattery(name: "x", left: 90, right: 30, case_: 50).minLevel == 30, "minLevel")
        precondition(AirPodsBattery(name: "x", left: nil, right: nil, case_: nil).minLevel == nil, "minLevel nil")

        // modelo pelo device_productID (string hex, qualquer caixa)
        let pro2 = json("""
        { "SPBluetoothDataType": [ { "device_connected": [
          { "AirPods Pro": { "device_batteryLevelLeft": "100%", "device_batteryLevelRight": "90%",
            "device_batteryLevelCase": "82%", "device_minorType": "Headphones",
            "device_productID": "0x2024" } }
        ] } ] }
        """)
        precondition(AirPodsBattery.parse(from: pro2)?.model == .pro, "pro2 usb-c")
        precondition(AirPodsModel(productID: 0x200E) == .pro, "pro1")
        precondition(AirPodsModel(productID: 0x2013) == .gen3, "gen3")
        precondition(AirPodsModel(productID: 0x2019) == .gen4, "gen4")
        precondition(AirPodsModel(productID: 0x201B) == .gen4, "gen4 anc")
        precondition(AirPodsModel(productID: 0x200F) == .gen12, "gen2")
        precondition(AirPodsModel(productID: 0x200A) == .max, "max")
        precondition(AirPodsModel(productID: 0x9999) == .unknown, "desconhecido")
        precondition(AirPodsModel(productID: nil) == .unknown, "sem id")

        // caixa baixa e lixo no campo
        let lower = json("""
        { "SPBluetoothDataType": [ { "device_connected": [
          { "F": { "device_batteryLevelLeft": "50%", "device_minorType": "Headphones", "device_productID": "0x200e" } }
        ] } ] }
        """)
        precondition(AirPodsBattery.parse(from: lower)?.model == .pro, "hex minúsculo")
        let lixo = json("""
        { "SPBluetoothDataType": [ { "device_connected": [
          { "F": { "device_batteryLevelLeft": "50%", "device_minorType": "Headphones", "device_productID": "zz" } }
        ] } ] }
        """)
        precondition(AirPodsBattery.parse(from: lixo)?.model == .unknown, "id lixo")

        // símbolos: nomes pré-macOS 15; Max sem estojo
        precondition(AirPodsModel.pro.leftSymbol == "airpodpro.left", "lado pro")
        precondition(AirPodsModel.gen12.caseSymbol == "airpods.chargingcase", "estojo gen12")
        precondition(AirPodsModel.max.caseSymbol == nil, "max sem estojo")
        precondition(AirPodsModel.unknown.pairSymbol == "airpodspro", "fallback")

        // nível da ilha: menor fone reportado, estojo fora
        precondition(AirPodsBattery(name: "x", left: 80, right: 40, case_: 5).islandLevel == 40, "ilha min")
        precondition(AirPodsBattery(name: "x", left: nil, right: 60, case_: 5).islandLevel == 60, "ilha um lado")
        precondition(AirPodsBattery(name: "x", left: nil, right: nil, case_: 5).islandLevel == nil, "ilha sem fones")
        precondition(AirPodsBattery.isLow(10) && !AirPodsBattery.isLow(11), "limite baixo")

        // fotos do macOS: ID exato primeiro, depois o irmão de mesmo visual
        precondition(AirPodsBattery.parse(from: pro2)?.productID == 0x2024, "guarda o id")
        precondition(AirPodsModel.pro.photoIDs(productID: 0x2024) == [0x2024, 0x2014, 0x200E], "pro usb-c")
        precondition(AirPodsModel.pro.photoIDs(productID: 0x2014) == [0x2014, 0x200E], "sem repetir")
        precondition(AirPodsModel.unknown.photoIDs(productID: nil) == [], "desconhecido sem foto")
        precondition(AirPodsModel.gen12.photoIDs(productID: nil) == [0x200F, 0x2002], "gen12 sem id")

        print("airpods parser: OK")
    }
}
