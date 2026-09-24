import Foundation

/// Últimas cores tiradas pelo conta-gotas, HEX, mais recente primeiro.
/// Singleton: uma lista só pra todas as telas.
final class CoresRecentes: ObservableObject {
    static let shared = CoresRecentes()
    static let limite = 8
    @Published private(set) var lista: [String]

    private init() { lista = UserDefaults.standard.stringArray(forKey: "coresRecentes") ?? [] }

    static func registrar(_ hex: String, em lista: [String]) -> [String] {
        Array(([hex] + lista.filter { $0 != hex }).prefix(limite))
    }

    func adicionar(_ hex: String) {
        lista = Self.registrar(hex, em: lista)
        UserDefaults.standard.set(lista, forKey: "coresRecentes")
    }

    /// Só memória, pro harness de snapshot: não toca o UserDefaults de quem roda.
    func carregar(_ nova: [String]) { lista = nova }
    func limpar() { lista = [] }
}
