//
//  permissioncheck.swift
//  Cobre a parte pura do diagnóstico de instalação (Permissions.swift): é ela
//  que decide se o painel avisa "o app não vai aparecer na lista do Ajustes do
//  Sistema" — a falha que fez uma instalação nova não achar as permissões.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/Permissions.swift tools/permissioncheck.swift \
//    -o /tmp/permissioncheck && /tmp/permissioncheck
//

import Foundation

@main
enum PermissionCheck {
    static func main() {
        let home = "/Users/alguem"

        // Translocação vence tudo: mesmo em quarentena, é ela que o usuário precisa resolver.
        assert(Permission.issue(
            path: "/private/var/folders/x1/AppTranslocation/ABC/d/Knobler.app",
            quarantined: true, home: home) == .translocado,
            "caminho translocado deve reportar .translocado")

        assert(Permission.issue(path: "/Applications/Knobler.app",
                                quarantined: true, home: home) == .emQuarentena,
               "quarentena deve ser detectada mesmo em /Applications")

        assert(Permission.issue(path: "/Applications/Knobler.app",
                                quarantined: false, home: home) == nil,
               "instalação canônica deve ser sadia")

        assert(Permission.issue(path: "\(home)/Applications/Knobler.app",
                                quarantined: false, home: home) == nil,
               "~/Applications também é instalação válida")

        assert(Permission.issue(path: "\(home)/Downloads/Knobler.app",
                                quarantined: false, home: home)
               == .foraDeApplications("\(home)/Downloads"),
               "fora de /Applications deve reportar a pasta")

        // /Applications-algo-mais não pode passar por /Applications.
        assert(Permission.issue(path: "/ApplicationsAntigas/Knobler.app",
                                quarantined: false, home: home)
               == .foraDeApplications("/ApplicationsAntigas"),
               "prefixo parecido não pode contar como /Applications")

        // Toda causa tem texto de usuário — a UI mostra os dois campos direto.
        for issue in [Permission.InstallIssue.translocado, .emQuarentena,
                      .foraDeApplications("/tmp")] {
            assert(!issue.mensagem.isEmpty, "mensagem vazia em \(issue)")
            assert(!issue.comoResolver.isEmpty, "comoResolver vazio em \(issue)")
        }

        print("permissioncheck: OK")
    }
}
