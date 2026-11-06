import Foundation

// Nota de voz gravada: a fonte do microfone (o gravador do ditado no app, uma
// falsa nos gates), a forma de onda de 64 barras e a duração que vão no
// `POST /v1/enviar/voz` (docs/whatsapp-ponte.md:630-656).

/// Quem grava. `comecar` entrega o nível (0…1) de qualquer thread; `parar`
/// devolve as amostras Float32 mono 16 kHz.
protocol WAFonteDeMicrofone: AnyObject {
    func comecar(nivel: @escaping (Float) -> Void) throws
    func parar() -> [Float]
}

enum WAOnda {
    static let barras = 64
    static let taxa = 16000

    /// Exatamente 64 inteiros de 0 a 100, normalizados pela barra mais alta.
    /// Poucos níveis esticam (cada barra pega o nível da sua posição); muitos
    /// fazem a média por fatia. Sem níveis ou só silêncio: 64 zeros.
    static func reduzir(niveis: [Float]) -> [Int] {
        let zeros = [Int](repeating: 0, count: barras)
        let n = niveis.count
        guard n > 0 else { return zeros }
        let limpos = niveis.map { $0.isFinite ? max(0, $0) : 0 }
        let fatias: [Float] = (0..<barras).map { i in
            if n <= barras { return limpos[i * n / barras] }
            let de = i * n / barras
            let ate = max(de + 1, (i + 1) * n / barras)
            return limpos[de..<ate].reduce(0, +) / Float(ate - de)
        }
        guard let maior = fatias.max(), maior > 0 else { return zeros }
        return fatias.map { min(100, max(0, Int(($0 / maior * 100).rounded()))) }
    }

    /// Duração em segundos inteiros, arredondada pra cima, de 1 a 3600.
    static func segundos(amostras16k: Int) -> Int {
        let s = (max(0, amostras16k) + taxa - 1) / taxa
        return min(3600, max(1, s))
    }
}

struct WAGravacaoEmCurso: Equatable {
    let chave: WAChave
    let inicio: Date
    var nivel: Float
}
