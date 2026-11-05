// Gate da etapa 13 do WhatsApp: o banner do WhatsApp Desktop some enquanto a
// ponte está conectada (o card da ponte já avisa e responde) e passa como hoje
// quando ela está fora. Só as regras puras de Knobler/NotificationRules.swift;
// a ligação no interceptor e no AppDelegate é o whatsappbannerligacaocheck.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/NotificationRules.swift tools/whatsappbannercheck.swift \
//     -o /tmp/whatsappbannercheck && /tmp/whatsappbannercheck
//
// Compilar só com NotificationRules.swift já prova que as regras não importam
// nada do WhatsApp (o estado da ponte entra por parâmetro, A37).

import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappbannercheck.swift:\(linha))")
        exit(1)
    }
}

@main
enum WhatsAppBannerCheck {
    static func main() {
        testBundleID()
        testEhBanner()
        testDescarta()
        print("whatsappbannercheck ok")
    }

    static func testBundleID() {
        exigir(NotificationRules.whatsAppBundleID == "net.whatsapp.WhatsApp",
               "bundle id do WhatsApp Desktop: \(NotificationRules.whatsAppBundleID)")
    }

    // MARK: - é banner do WhatsApp?

    static func testEhBanner() {
        func eh(_ nome: String?, _ bundle: String? = nil) -> Bool {
            NotificationRules.ehBannerDoWhatsApp(appName: nome, bundleID: bundle)
        }
        // pelo nome
        exigir(eh("WhatsApp"), "\"WhatsApp\" é banner do WhatsApp")
        exigir(eh("\u{200E}WhatsApp"), "\"\\u{200E}WhatsApp\" (marca de direção grudada) é banner do WhatsApp")
        exigir(eh("whatsapp"), "\"whatsapp\" (minúsculo) é banner do WhatsApp")
        exigir(eh("WHATSAPP"), "\"WHATSAPP\" é banner do WhatsApp")
        exigir(eh(" WhatsApp\u{200E} "), "\" WhatsApp\\u{200E} \" (espaço e marca nas pontas) é banner do WhatsApp")
        exigir(eh("WhatsApp", "net.whatsapp.WhatsApp"), "nome e bundle do WhatsApp é banner do WhatsApp")
        // pelo bundle id, sem nome legível
        exigir(eh(nil, "net.whatsapp.WhatsApp"), "bundle net.whatsapp.WhatsApp com nome nil é banner do WhatsApp")

        // não são
        exigir(!eh("WhatsApp Business"), "\"WhatsApp Business\" não é banner do WhatsApp")
        exigir(!eh("\u{200E}WhatsApp Business"), "\"\\u{200E}WhatsApp Business\" não é banner do WhatsApp")
        exigir(!eh("Luccas"), "\"Luccas\" (nome de quem mandou, heurística errada) não é banner do WhatsApp")
        exigir(!eh("Mensagens"), "\"Mensagens\" não é banner do WhatsApp")
        exigir(!eh("Mensagens", "com.apple.MobileSMS"), "Mensagens com o bundle dele não é banner do WhatsApp")
        exigir(!eh("Zap WhatsApp"), "\"Zap WhatsApp\" (contém o nome mas não é) não é banner do WhatsApp")
        exigir(!eh(""), "nome vazio não é banner do WhatsApp")
        exigir(!eh(nil, nil), "nil/nil não é banner do WhatsApp")
        exigir(!eh(nil, "com.apple.MobileSMS"), "bundle de outro app com nome nil não é banner do WhatsApp")
    }

    // MARK: - descarta?

    static func testDescarta() {
        func descarta(_ nome: String?, _ bundle: String?, _ ponte: Bool) -> Bool {
            NotificationRules.descartaBannerDoWhatsApp(appName: nome, bundleID: bundle, ponteConectada: ponte)
        }
        // ponte conectada: banner do WhatsApp some
        exigir(descarta("WhatsApp", "net.whatsapp.WhatsApp", true),
               "ponte conectada: banner do WhatsApp (nome + bundle) tem que ser descartado")
        exigir(descarta("\u{200E}WhatsApp", nil, true),
               "ponte conectada: banner \"\\u{200E}WhatsApp\" sem bundle tem que ser descartado")
        exigir(descarta(nil, "net.whatsapp.WhatsApp", true),
               "ponte conectada: banner só com bundle do WhatsApp tem que ser descartado")

        // ponte fora: o banner passa como hoje
        exigir(!descarta("WhatsApp", "net.whatsapp.WhatsApp", false),
               "ponte fora: banner do WhatsApp nunca é descartado")
        exigir(!descarta("\u{200E}WhatsApp", nil, false),
               "ponte fora: banner \"\\u{200E}WhatsApp\" nunca é descartado")
        exigir(!descarta(nil, "net.whatsapp.WhatsApp", false),
               "ponte fora: banner só com bundle do WhatsApp nunca é descartado")

        // outro app: nunca, com ou sem ponte
        for ponte in [true, false] {
            exigir(!descarta("Mensagens", "com.apple.MobileSMS", ponte),
                   "banner do Mensagens nunca é descartado (ponte \(ponte))")
            exigir(!descarta("WhatsApp Business", nil, ponte),
                   "banner do WhatsApp Business nunca é descartado (ponte \(ponte))")
            exigir(!descarta("Luccas", nil, ponte),
                   "banner com o nome de quem mandou (\"Luccas\") nunca é descartado (ponte \(ponte))")
            exigir(!descarta(nil, nil, ponte),
                   "banner sem nome nem bundle nunca é descartado (ponte \(ponte))")
        }
    }
}
